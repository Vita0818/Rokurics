//
//  CanonicalProductionExecutionGuardTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Testing
@testable import RokuricsMac

struct CanonicalProductionExecutionGuardTests {
    @Test func tokenMissingRollbackPlanFails() {
        let audit = CanonicalProductionExecutionGuard.evaluate(
            mode: .productionExecute,
            token: CanonicalKernelFacadeTestSupport.token(rollbackPlanID: nil),
            policy: CanonicalProductionExecutionPolicy(requiredDomains: [.recordingMetadata, .fileRuntime], requiredPorts: [.file]),
            domains: [.recordingMetadata, .fileRuntime],
            ports: CanonicalProductionPortSet(file: CanonicalTestProductionFilePort()),
            rollbackPlan: nil,
            dryRunReportID: CanonicalKernelFacadeTestSupport.dryRunReportID,
            dryRunEquivalence: CanonicalKernelFacadeTestSupport.equivalentDryRunReport(),
            readinessReport: CanonicalKernelFacadeTestSupport.readyReadinessReport(),
            unresolvedConflictCount: 0
        )

        #expect(audit.allowed == false)
        #expect(audit.rejectionReasons.contains(.missingRollbackPlan))
    }

    @Test func tokenMissingDryRunEquivalenceFails() {
        let audit = CanonicalProductionExecutionGuard.evaluate(
            mode: .productionExecute,
            token: CanonicalKernelFacadeTestSupport.token(dryRunReportID: nil),
            policy: CanonicalProductionExecutionPolicy(requiredDomains: [.recordingMetadata, .fileRuntime], requiredPorts: [.file]),
            domains: [.recordingMetadata, .fileRuntime],
            ports: CanonicalProductionPortSet(file: CanonicalTestProductionFilePort()),
            rollbackPlan: CanonicalKernelFacadeTestSupport.rollbackPlan(),
            dryRunReportID: nil,
            dryRunEquivalence: nil,
            readinessReport: CanonicalKernelFacadeTestSupport.readyReadinessReport(),
            unresolvedConflictCount: 0
        )

        #expect(audit.allowed == false)
        #expect(audit.rejectionReasons.contains(.dryRunNotEquivalent))
    }

    @Test func dryRunOnlyPortFailsAsMissingProductionPort() {
        let audit = CanonicalProductionExecutionGuard.evaluate(
            mode: .productionExecute,
            token: CanonicalKernelFacadeTestSupport.token(),
            policy: CanonicalProductionExecutionPolicy(requiredDomains: [.recordingMetadata, .fileRuntime], requiredPorts: [.file]),
            domains: [.recordingMetadata, .fileRuntime],
            ports: MacCanonicalDryRunPorts.makePortSet(),
            rollbackPlan: CanonicalKernelFacadeTestSupport.rollbackPlan(),
            dryRunReportID: CanonicalKernelFacadeTestSupport.dryRunReportID,
            dryRunEquivalence: CanonicalKernelFacadeTestSupport.equivalentDryRunReport(),
            readinessReport: CanonicalKernelFacadeTestSupport.readyReadinessReport(),
            unresolvedConflictCount: 0
        )

        #expect(audit.allowed == false)
        #expect(audit.rejectionReasons.contains(.missingProductionPort))
    }

    @Test func unresolvedConflictAndBlockedMigrationFail() {
        let blockedReadiness = CanonicalDryRunReadinessReport(
            states: [.productionBlocked],
            portReadiness: CanonicalProductionPortSet(file: CanonicalTestProductionFilePort()).readiness(),
            blockers: [CanonicalDryRunBlocker(domain: .conflicts, kind: .unresolvedConflict, reason: "manualReview")],
            eligibleForRuntimeSwitch: false
        )
        let audit = CanonicalProductionExecutionGuard.evaluate(
            mode: .productionExecute,
            token: CanonicalKernelFacadeTestSupport.token(),
            policy: CanonicalProductionExecutionPolicy(requiredDomains: [.recordingMetadata, .fileRuntime], requiredPorts: [.file]),
            domains: [.recordingMetadata, .fileRuntime],
            ports: CanonicalProductionPortSet(file: CanonicalTestProductionFilePort()),
            rollbackPlan: CanonicalKernelFacadeTestSupport.rollbackPlan(),
            dryRunReportID: CanonicalKernelFacadeTestSupport.dryRunReportID,
            dryRunEquivalence: CanonicalKernelFacadeTestSupport.equivalentDryRunReport(),
            readinessReport: blockedReadiness,
            unresolvedConflictCount: 1
        )

        #expect(audit.rejectionReasons.contains(.unresolvedConflict))
        #expect(audit.rejectionReasons.contains(.productionMigrationBlocked))
    }
}
