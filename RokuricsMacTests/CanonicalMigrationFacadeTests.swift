//
//  CanonicalMigrationFacadeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalMigrationFacadeTests {
    @Test func defaultFacadeRejectsProductionExecutionEvenWithTokenAndFakePorts() async throws {
        let rootURL = try makeTempRoot("mac-facade-disabled")
        let facade = CanonicalMacMigrationFacade(
            ports: MacCanonicalProductionPorts.makeFakeInMemoryPortSet(
                rootURL: rootURL,
                rootToken: CanonicalRootToken("test-root")
            )
        )

        let result = await facade.executeWithGuard(
            CanonicalKernelFacadeTestSupport.productionInput(),
            token: CanonicalKernelFacadeTestSupport.token()
        )

        #expect(result.succeeded == false)
        #expect(result.payload?.guardAudit?.rejectionReasons.contains(.modeDisabled) == true)
    }

    @Test func testHarnessFacadeCanExecuteAgainstFakePortsOnly() async throws {
        let rootURL = try makeTempRoot("mac-facade-fake")
        let policy = CanonicalProductionExecutionPolicy(
            requiredDomains: [.recordingMetadata, .fileRuntime],
            requiredPorts: [.file, .transport, .upload, .apply],
            requireOwnerApproval: true,
            requireRollbackPlan: true,
            requireDryRunEquivalence: true,
            requireMigrationGateUnblocked: true
        )
        let facade = CanonicalMacMigrationFacade(
            configuration: .testProductionExecute(policy: policy),
            ports: MacCanonicalProductionPorts.makeFakeInMemoryPortSet(
                rootURL: rootURL,
                rootToken: CanonicalRootToken("test-root")
            )
        )

        let result = await facade.executeWithGuard(
            CanonicalKernelFacadeTestSupport.productionInput(),
            token: CanonicalKernelFacadeTestSupport.token()
        )
        let writtenURL = rootURL.appendingPathComponent("metadata/recording-01.json")

        #expect(result.succeeded)
        #expect(result.payload?.trace.sideEffects.first?.kind == .fileWrite)
        #expect(try Data(contentsOf: writtenURL) == Data("metadata".utf8))
    }

    @Test func productionExecuteStillRequiresTestHarnessToken() async throws {
        let rootURL = try makeTempRoot("mac-facade-token")
        let facade = CanonicalMacMigrationFacade(
            configuration: .testProductionExecute(),
            ports: MacCanonicalProductionPorts.makeFakeInMemoryPortSet(
                rootURL: rootURL,
                rootToken: CanonicalRootToken("test-root")
            )
        )
        let nonHarnessToken = CanonicalProductionExecutionToken(
            mode: .productionExecute,
            domainAllowlist: [.recordingMetadata, .fileRuntime],
            nodeRole: .mac,
            syncRunID: "sync-run-mac",
            dryRunEquivalentReportID: CanonicalKernelFacadeTestSupport.dryRunReportID,
            rollbackPlanID: "rollback-plan-01",
            ownerApproved: true
        )

        let result = await facade.executeWithGuard(
            CanonicalKernelFacadeTestSupport.productionInput(),
            token: nonHarnessToken
        )

        #expect(result.succeeded == false)
        #expect(result.payload?.guardAudit?.rejectionReasons.contains(.blockedProductionExecute) == true)
    }

    @Test func dryRunFacadeBuildsShadowPreparationWithoutRuntimeSwitch() throws {
        let facade = CanonicalMacMigrationFacade(
            configuration: .dryRun(),
            ports: MacCanonicalProductionPorts.makeDisabledPortSet()
        )
        let local = CanonicalProductionTestFixtures.snapshot()
        let peer = CanonicalProductionTestFixtures.snapshot(
            node: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone")
        )

        let preparation = facade.prepareShadowExecution(
            local: local,
            peer: peer,
            currentRuntimeReadiness: CanonicalProductionTestFixtures.completeRuntimeReadiness(),
            context: CanonicalDryRunMigrationContext(dryRunID: "mac-dry-run-01")
        )

        let unwrapped = try #require(preparation)
        #expect(unwrapped.dryRunPlan.dryRunID == "mac-dry-run-01")
        #expect(unwrapped.productionInput.steps.isEmpty)
        #expect(unwrapped.productionInput.dryRunReportID == "mac-dry-run-01")
        #expect(unwrapped.migrationGate.productionMigrationBlocked)
    }

    private func makeTempRoot(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rokurics-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
