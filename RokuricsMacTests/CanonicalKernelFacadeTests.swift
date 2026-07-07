//
//  CanonicalKernelFacadeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalKernelFacadeTests {
    @Test func disabledDefaultRejectsExecuteProduction() async {
        let result = await CanonicalKernelFacade().executeProduction(
            CanonicalKernelFacadeTestSupport.productionInput(),
            token: CanonicalKernelFacadeTestSupport.token()
        )

        #expect(result.payload?.succeeded == false)
        #expect(result.payload?.trace.sideEffects.isEmpty == true)
        #expect(result.payload?.guardAudit?.rejectionReasons.contains(.modeDisabled) == true)
    }

    @Test func dryRunModeReturnsDryRunReportOnly() {
        let facade = CanonicalKernelFacade(
            configuration: CanonicalKernelConfiguration(mode: .dryRun),
            environment: CanonicalKernelEnvironment(ports: MacCanonicalDryRunPorts.makePortSet())
        )
        let local = CanonicalProductionTestFixtures.snapshot()
        let peer = CanonicalProductionTestFixtures.snapshot(node: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"))
        let result = facade.dryRunMigration(
            local: local,
            peer: peer,
            currentRuntimeReadiness: CanonicalProductionTestFixtures.completeRuntimeReadiness(),
            trigger: .periodic,
            context: CanonicalDryRunMigrationContext(
                retryRuntimeMigrated: true,
                macPendingSyncMigrated: true,
                userDataMigrationDesigned: true,
                uiIntegrationMigrated: true
            )
        )

        #expect(result.succeeded)
        #expect(result.payload?.dryRunID != nil)
        #expect(result.audit.sideEffects.isEmpty)
    }

    @Test func productionExecuteWithoutTokenFailsBeforePortCall() async {
        let facade = CanonicalKernelFacadeTestSupport.productionFacade()
        let result = await facade.executeProduction(CanonicalKernelFacadeTestSupport.productionInput(), token: nil)

        #expect(result.payload?.succeeded == false)
        #expect(result.payload?.trace.sideEffects.isEmpty == true)
        #expect(result.payload?.guardAudit?.rejectionReasons.contains(.modeDisabled) == true)
    }

    @Test func productionExecuteWithFakePortProducesRedactedSideEffectTrace() async {
        let facade = CanonicalKernelFacadeTestSupport.productionFacade()
        let result = await facade.executeProduction(
            CanonicalKernelFacadeTestSupport.productionInput(),
            token: CanonicalKernelFacadeTestSupport.token()
        )

        #expect(result.payload?.succeeded == true)
        #expect(result.payload?.trace.sideEffects.map(\.kind).contains(.fileWrite) == true)
        #expect(result.payload?.trace.redactedSummaries.contains { $0.contains("/Users/") } == false)
    }
}
