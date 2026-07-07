//
//  CanonicalMigrationGateTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalMigrationGateTests {
    @Test func missingPortsKeepProductionMigrationBlocked() throws {
        let local = CanonicalProductionTestFixtures.snapshot()
        let peer = CanonicalProductionTestFixtures.snapshot(node: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"))
        let plan = try CanonicalDryRunMigrationPlanner().plan(
            local: local,
            peer: peer,
            ports: CanonicalProductionPortSet(),
            currentRuntimeReadiness: CanonicalProductionTestFixtures.completeRuntimeReadiness(),
            trigger: .manual
        )

        #expect(plan.readinessReport.states.contains(.productionAdapterMissing))
        #expect(plan.readinessReport.states.contains(.productionBlocked))
        #expect(plan.readinessReport.eligibleForRuntimeSwitch == false)
        #expect(plan.readinessReport.retired == false)
        #expect(plan.blockers.contains { $0.kind == .missingProductionFilePort })
        #expect(plan.blockers.contains { $0.kind == .missingProductionTransportPort })
        #expect(plan.blockers.contains { $0.kind == .missingProductionUploadPort })
        #expect(plan.blockers.contains { $0.kind == .missingProductionApplyPort })
    }

    @Test func equivalentDryRunIsOnlyEligibleForManualMigrationDesign() throws {
        let local = CanonicalProductionTestFixtures.snapshot()
        let peer = CanonicalProductionTestFixtures.snapshot(node: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"))
        let plan = try CanonicalDryRunMigrationPlanner().plan(
            local: local,
            peer: peer,
            ports: MacCanonicalDryRunPorts.makePortSet(),
            currentRuntimeReadiness: CanonicalProductionTestFixtures.completeRuntimeReadiness(),
            trigger: .manual
        )

        #expect(plan.readinessReport.states.contains(.productionPortsDeclared))
        #expect(plan.readinessReport.states.contains(.dryRunAvailable))
        #expect(plan.readinessReport.states.contains(.dryRunEquivalent))
        #expect(plan.readinessReport.states.contains(.eligibleForManualMigrationDesign))
        #expect(plan.readinessReport.states.contains(.productionBlocked))
        #expect(plan.readinessReport.eligibleForRuntimeSwitch == false)
        #expect(plan.readinessReport.retired == false)
        #expect(plan.blockers.contains { $0.kind == .uiLegacyRuntime })
        #expect(plan.blockers.contains { $0.kind == .retryRuntimeNotMigrated })
        #expect(plan.blockers.contains { $0.kind == .macPendingSyncLegacy })
        #expect(plan.blockers.contains { $0.kind == .userDataMigrationNotDesigned })
    }

    @Test func unsupportedObjectsBlockShadowOrRuntimeSwitchReadiness() throws {
        let unsupported = CanonicalProductionUnsupportedFact(
            objectID: "unsupported-01",
            domain: .studyItems,
            reason: "unknownStudyItemKind"
        )
        let local = CanonicalProductionTestFixtures.snapshot(unsupportedFacts: [unsupported])
        let peer = CanonicalProductionTestFixtures.snapshot(node: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"))
        let plan = try CanonicalDryRunMigrationPlanner().plan(
            local: local,
            peer: peer,
            ports: MacCanonicalDryRunPorts.makePortSet(),
            currentRuntimeReadiness: CanonicalProductionTestFixtures.completeRuntimeReadiness(),
            trigger: .manual
        )

        #expect(plan.blockers.contains { $0.kind == .unsupportedObject && $0.domain == .studyItems })
        #expect(plan.readinessReport.states.contains(.productionBlocked))
        #expect(plan.readinessReport.states.contains(.eligibleForRuntimeSwitch) == false)
    }
}
