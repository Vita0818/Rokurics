//
//  CanonicalLibraryMetadataObservationTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalLibraryMetadataObservationTests {
    @Test func macCleanObservationWindowProducesReportOnlyCandidateWithoutRetirementExecution() throws {
        let policy = CanonicalLibraryMetadataObservationPolicy.explicitInternalTest()
        let window = Self.cleanWindow(policy: policy)

        let observationGate = CanonicalLibraryMetadataObservationGate.evaluate(
            window: window,
            policy: policy,
            nodeRole: .mac,
            syncRunID: "sync-run-v820"
        )
        #expect(observationGate.state == .completeReadyForRetirementCandidate)
        #expect(observationGate.complete)

        let retirementReport = CanonicalLibraryMetadataRetirementCandidateGate.evaluate(
            observationGate: observationGate,
            policy: policy,
            nodeRole: .mac,
            syncRunID: "sync-run-v820"
        )
        #expect(retirementReport.retirementCandidateReady)
        #expect(retirementReport.reportOnly)
        #expect(retirementReport.manualAuditRequired)
        #expect(!retirementReport.retirementExecutionPerformed)
        #expect(!retirementReport.legacyDeleted)
        #expect(!retirementReport.legacyDisabled)

        let matrix = CanonicalMigrationDomainMatrix.v820LibraryMetadataObservationReport(
            observationGate: observationGate,
            retirementCandidateReport: retirementReport
        )
        let libraryPolicy = try #require(matrix.policy(for: .libraryMetadata))
        #expect(libraryPolicy.status(for: .retirementCandidate) == .retirementCandidateReady)
        #expect(libraryPolicy.readPathLegacy)
        #expect(!matrix.libraryMetadataPilotComplete)
        #expect(matrix.policies.filter { $0.domain != .libraryMetadata }.allSatisfy { $0.staticOnly })
        #expect(matrix.validate().blockers.isEmpty)
    }

    @Test func macObservationGateBlocksDivergenceRollbackUnsupportedFallbackAndUnsafeEvents() {
        let policy = CanonicalLibraryMetadataObservationPolicy.explicitInternalTest(legacyFallbackAvailable: false)
        let window = Self.cleanWindow(policy: policy)
            .recording(.init(kind: .readSideParallelDivergent))
            .recording(.init(kind: .rollbackFatal))
            .recording(.init(kind: .readSideUnsupportedObject))
            .recording(.init(kind: .syncOrUploadTriggered))

        let gate = CanonicalLibraryMetadataObservationGate.evaluate(
            window: window,
            policy: policy,
            nodeRole: .mac
        )
        #expect(gate.state == .blockedByUnsafeSideEffect)
        #expect(gate.blockers.contains(.divergencePresent))
        #expect(gate.blockers.contains(.rollbackFailure))
        #expect(gate.blockers.contains(.fallbackMissing))
        #expect(gate.blockers.contains(.unsupportedObject))
        #expect(gate.blockers.contains(.unsafeSideEffect))
    }

    @Test func macReadSourceObservationHookDefaultsDisabledAndExplicitlyRecordsReadOnlyEvidence() {
        let result = Self.readSourceResult(canonicalCandidateBuilt: true)
        let seam = MacLibraryMetadataReadSideSeam()

        let disabled = seam.observeReadSource(
            result,
            trigger: .viewRefresh,
            syncRunID: "sync-run-v820"
        )
        #expect(!disabled.enabled)
        #expect(disabled.totalEventCount == 0)

        let observed = seam.observeReadSource(
            result,
            policy: .explicitInternalTest(minimumWriteCanonicalCommitCount: 0),
            trigger: .viewRefresh,
            syncRunID: "sync-run-v820"
        )
        #expect(observed.canonicalReadCandidateBuiltCount == 1)
        #expect(observed.syncOrUploadTriggeredCount == 0)
        #expect(observed.resourceMoveAttemptedCount == 0)
        #expect(observed.contentWrittenCount == 0)
        #expect(observed.uiMutatedCount == 0)
    }

    @Test func macObservationDiagnosticsAreRedacted() {
        let policy = CanonicalLibraryMetadataObservationPolicy.explicitInternalTest()
        let gate = CanonicalLibraryMetadataObservationGate.evaluate(
            window: Self.cleanWindow(policy: policy),
            policy: policy,
            nodeRole: .mac,
            syncRunID: "/Users/vita/secret/sync-run"
        )

        #expect(gate.diagnostics.allSatisfy { !CanonicalProductionRedaction.containsSensitivePathSignal($0.diagnosticsSummary) })
    }

    private static func cleanWindow(
        policy: CanonicalLibraryMetadataObservationPolicy
    ) -> CanonicalLibraryMetadataObservationWindow {
        CanonicalLibraryMetadataObservationWindow(
            observationWindowID: "mac-library-metadata-v820",
            policy: policy
        )
        .recording(.init(kind: .canonicalCommitAttempted))
        .recording(.init(kind: .canonicalCommitSucceeded))
        .recording(.init(kind: .canonicalReadCandidateBuilt))
        .recording(.init(kind: .legacyReadFallbackUsed))
    }

    private static func readSourceResult(
        canonicalCandidateBuilt: Bool
    ) -> CanonicalLibraryMetadataReadSourceResult {
        let legacy = CanonicalLibraryMetadataReadSnapshot(source: .legacy)
        let canonical = CanonicalLibraryMetadataReadSnapshot(source: .canonical)
        return CanonicalLibraryMetadataReadSourceResult(
            mode: .parallelCompare,
            returnedSource: .legacy,
            readSource: CanonicalLibraryMetadataReadSource(source: .legacy, snapshot: legacy),
            legacySnapshot: legacy,
            canonicalCandidate: canonical,
            diffReport: nil,
            gateResult: nil,
            fallback: .legacyDefault,
            fallbackCount: 0,
            canonicalReadServed: false,
            legacyReadReturned: true,
            canonicalCandidateBuilt: canonicalCandidateBuilt,
            fatalForFutureStage: false,
            storeMutated: false,
            syncOrUploadTriggered: false,
            resourceMoved: false,
            contentWritten: false,
            uiMutated: false,
            diagnostics: [],
            diagnosticsSummary: "testReadSourceResult"
        )
    }
}
