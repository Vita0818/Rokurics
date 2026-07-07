//
//  CanonicalDryRunMigrationTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalDryRunMigrationTests {
    @Test func dryRunEquivalentSnapshotsRemainBlockedForRuntimeSwitch() throws {
        let local = CanonicalProductionTestFixtures.snapshot()
        let peer = CanonicalProductionTestFixtures.snapshot(node: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"))
        let plan = try CanonicalDryRunMigrationPlanner().plan(
            local: local,
            peer: peer,
            ports: MacCanonicalDryRunPorts.makePortSet(),
            currentRuntimeReadiness: CanonicalProductionTestFixtures.completeRuntimeReadiness(),
            trigger: .manual,
            context: CanonicalDryRunMigrationContext(
                retryRuntimeMigrated: true,
                macPendingSyncMigrated: true,
                userDataMigrationDesigned: true,
                uiIntegrationMigrated: true
            ),
            generatedAt: CanonicalProductionTestFixtures.date(6_000)
        )

        #expect(plan.equivalenceReport.legacyEquivalence.status(for: .recordingMetadata) == .equivalent)
        #expect(plan.readinessReport.states.contains(.dryRunEquivalent))
        #expect(plan.readinessReport.states.contains(.eligibleForManualMigrationDesign))
        #expect(plan.readinessReport.eligibleForRuntimeSwitch == false)
        #expect(plan.readinessReport.retired == false)
        #expect(plan.diagnostics.contains { $0.kind == .canonicalDryRunCompleted })
    }

    @Test func metadataChurnSuppressionIsConservativeAndNonBlocking() throws {
        let legacy = CanonicalLegacyActionSnapshot(actionIDsByDomain: [
            .recordingMetadata: ["metadataChurn:recording-01"]
        ])
        let local = CanonicalProductionTestFixtures.snapshot(legacyActions: legacy)
        let peer = CanonicalProductionTestFixtures.snapshot(node: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"))
        let plan = try CanonicalDryRunMigrationPlanner().plan(
            local: local,
            peer: peer,
            ports: MacCanonicalDryRunPorts.makePortSet(),
            currentRuntimeReadiness: CanonicalProductionTestFixtures.completeRuntimeReadiness(),
            trigger: .manual,
            context: CanonicalDryRunMigrationContext(
                retryRuntimeMigrated: true,
                macPendingSyncMigrated: true,
                userDataMigrationDesigned: true,
                uiIntegrationMigrated: true
            )
        )

        let report = plan.equivalenceReport.legacyEquivalence.domainReports.first { $0.domain == .recordingMetadata }
        #expect(report?.status == .canonicalMoreConservative)
        #expect(report?.isBlocking == false)
        #expect(plan.blockers.contains { $0.kind == .dryRunDivergence && $0.domain == .recordingMetadata } == false)
    }

    @Test func canonicalAudioUploadWithoutLegacyActionIsAggressiveAndBlocked() throws {
        let local = CanonicalProductionTestFixtures.snapshot(recordings: [CanonicalProductionTestFixtures.recording(audio: true)])
        let peer = CanonicalProductionTestFixtures.snapshot(
            node: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"),
            recordings: [CanonicalProductionTestFixtures.recording(audio: false)]
        )
        let plan = try CanonicalDryRunMigrationPlanner().plan(
            local: local,
            peer: peer,
            ports: MacCanonicalDryRunPorts.makePortSet(),
            currentRuntimeReadiness: CanonicalProductionTestFixtures.completeRuntimeReadiness(),
            trigger: .manual
        )

        #expect(plan.actions.contains { $0.domain == .recordingAudio && $0.kind == .wouldUpload })
        #expect(plan.equivalenceReport.legacyEquivalence.status(for: .recordingAudio) == .canonicalMoreAggressive)
        #expect(plan.blockers.contains { $0.domain == .recordingAudio && $0.kind == .dryRunDivergence })
        #expect(plan.diagnostics.contains { $0.kind == .canonicalDryRunDivergenceDetected })
    }

    @Test func canonicalConflictBlocksDryRunMigration() throws {
        let local = CanonicalProductionTestFixtures.snapshot(
            recordings: [CanonicalProductionTestFixtures.recording(title: "Local", modifiedAt: CanonicalProductionTestFixtures.date(2_000))]
        )
        let peer = CanonicalProductionTestFixtures.snapshot(
            node: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"),
            recordings: [CanonicalProductionTestFixtures.recording(title: "Peer", modifiedAt: CanonicalProductionTestFixtures.date(2_000))]
        )
        let plan = try CanonicalDryRunMigrationPlanner().plan(
            local: local,
            peer: peer,
            ports: MacCanonicalDryRunPorts.makePortSet(),
            currentRuntimeReadiness: CanonicalProductionTestFixtures.completeRuntimeReadiness(),
            trigger: .manual
        )

        #expect(plan.applyPlan.conflicts.isEmpty == false)
        #expect(plan.equivalenceReport.legacyEquivalence.status(for: .recordingMetadata) == .conflict)
        #expect(plan.blockers.contains { $0.kind == .unresolvedConflict })
    }
}
