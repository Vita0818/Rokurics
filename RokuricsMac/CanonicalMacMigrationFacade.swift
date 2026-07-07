//
//  CanonicalMacMigrationFacade.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated struct CanonicalMacMigrationFacadeConfiguration: Sendable {
    var mode: CanonicalKernelExecutionMode
    var productionPolicy: CanonicalProductionExecutionPolicy
    var allowTestHarnessProductionExecution: Bool

    nonisolated init(
        mode: CanonicalKernelExecutionMode = .disabled,
        productionPolicy: CanonicalProductionExecutionPolicy = CanonicalProductionExecutionPolicy(),
        allowTestHarnessProductionExecution: Bool = false
    ) {
        self.mode = mode
        self.productionPolicy = productionPolicy
        self.allowTestHarnessProductionExecution = allowTestHarnessProductionExecution
    }

    nonisolated static func dryRun() -> CanonicalMacMigrationFacadeConfiguration {
        CanonicalMacMigrationFacadeConfiguration(mode: .dryRun)
    }

    nonisolated static func testProductionExecute(
        policy: CanonicalProductionExecutionPolicy = CanonicalProductionExecutionPolicy()
    ) -> CanonicalMacMigrationFacadeConfiguration {
        CanonicalMacMigrationFacadeConfiguration(
            mode: .productionExecute,
            productionPolicy: policy,
            allowTestHarnessProductionExecution: true
        )
    }
}

nonisolated struct CanonicalMacMigrationShadowPreparation: Sendable {
    var dryRunPlan: CanonicalDryRunMigrationPlan
    var migrationGate: CanonicalProductionMigrationGateReport
    var equivalenceReport: CanonicalDryRunEquivalenceReport
    var productionInput: CanonicalProductionExecutionInput
}

nonisolated struct CanonicalMacMigrationFacade: Sendable {
    var configuration: CanonicalMacMigrationFacadeConfiguration
    var ports: CanonicalProductionPortSet
    var snapshotAdapter: MacCanonicalProductionSnapshotAdapter

    nonisolated init(
        configuration: CanonicalMacMigrationFacadeConfiguration = CanonicalMacMigrationFacadeConfiguration(),
        ports: CanonicalProductionPortSet = MacCanonicalProductionPorts.makeDisabledPortSet(),
        snapshotAdapter: MacCanonicalProductionSnapshotAdapter = MacCanonicalProductionSnapshotAdapter()
    ) {
        self.configuration = configuration
        self.ports = ports
        self.snapshotAdapter = snapshotAdapter
    }

    nonisolated func makeSnapshot(_ input: MacCanonicalProductionSnapshotInput) -> CanonicalProductionSnapshot {
        snapshotAdapter.buildSnapshot(from: input)
    }

    nonisolated func runDryRun(
        local: CanonicalProductionSnapshot,
        peer: CanonicalProductionSnapshot,
        currentRuntimeReadiness: CanonicalRuntimeReadinessReport,
        trigger: CanonicalSyncPlanTrigger = .periodic,
        context: CanonicalDryRunMigrationContext = CanonicalDryRunMigrationContext()
    ) -> CanonicalKernelOperationResult<CanonicalDryRunMigrationPlan> {
        kernelFacade.dryRunMigration(
            local: local,
            peer: peer,
            currentRuntimeReadiness: currentRuntimeReadiness,
            trigger: trigger,
            context: context
        )
    }

    nonisolated func buildEquivalenceReport(
        syncPlan: CanonicalSyncPlan,
        applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan,
        localLegacyActions: CanonicalLegacyActionSnapshot
    ) -> CanonicalKernelOperationResult<CanonicalLegacyEquivalenceReport> {
        kernelFacade.compareLegacy(
            syncPlan: syncPlan,
            applyPlan: applyPlan,
            libraryPlan: libraryPlan,
            localLegacyActions: localLegacyActions,
            portReadiness: ports.readiness()
        )
    }

    nonisolated func buildMigrationGate(from plan: CanonicalDryRunMigrationPlan) -> CanonicalProductionMigrationGateReport {
        plan.readinessReport
    }

    nonisolated func prepareShadowExecution(
        local: CanonicalProductionSnapshot,
        peer: CanonicalProductionSnapshot,
        currentRuntimeReadiness: CanonicalRuntimeReadinessReport,
        trigger: CanonicalSyncPlanTrigger = .periodic,
        context: CanonicalDryRunMigrationContext = CanonicalDryRunMigrationContext()
    ) -> CanonicalMacMigrationShadowPreparation? {
        let dryRun = runDryRun(
            local: local,
            peer: peer,
            currentRuntimeReadiness: currentRuntimeReadiness,
            trigger: trigger,
            context: context
        )
        guard let plan = dryRun.payload else {
            return nil
        }
        return CanonicalMacMigrationShadowPreparation(
            dryRunPlan: plan,
            migrationGate: plan.readinessReport,
            equivalenceReport: plan.equivalenceReport,
            productionInput: productionInput(from: plan)
        )
    }

    func executeWithGuard(
        _ input: CanonicalProductionExecutionInput,
        token: CanonicalProductionExecutionToken?
    ) async -> CanonicalKernelOperationResult<CanonicalProductionExecutionResult> {
        if configuration.allowTestHarnessProductionExecution, token?.nodeRole == .testHarness {
            return await kernelFacade.executeProduction(input, token: token)
        }
        if configuration.mode.isShadowPreparationMode {
            let audit = CanonicalProductionExecutionGuard.evaluateShadow(
                mode: configuration.mode,
                token: token,
                domains: input.domains,
                rollbackPlan: input.rollbackPlan,
                dryRunEquivalence: input.dryRunEquivalence,
                unresolvedConflictCount: input.unresolvedConflictCount
            )
            let result = CanonicalProductionExecutionResult(
                operationID: input.operationID,
                mode: configuration.mode,
                succeeded: audit.allowed,
                failures: audit.allowed ? [] : [
                    CanonicalProductionExecutionFailure(
                        operationID: input.operationID,
                        reason: audit.rejectionReasons.map(\.rawValue).joined(separator: ",")
                    )
                ],
                guardAudit: audit
            )
            let report = CanonicalKernelAuditReport(
                operation: .executeProduction,
                mode: configuration.mode,
                productionAudit: audit
            )
            return audit.allowed
                ? .success(operation: .executeProduction, mode: configuration.mode, payload: result, audit: report)
                : CanonicalKernelOperationResult(
                    operation: .executeProduction,
                    mode: configuration.mode,
                    payload: result,
                    errors: [.productionExecutionRejected(audit.rejectionReasons)],
                    audit: report
                )
        }
        if configuration.mode == .productionExecute, token?.nodeRole != nil, token?.nodeRole != .testHarness {
            return await kernelFacade.executeProduction(input, token: token)
        }
        let disabled = CanonicalKernelFacade(
            configuration: CanonicalKernelConfiguration(mode: .disabled, productionPolicy: configuration.productionPolicy),
            environment: CanonicalKernelEnvironment(ports: ports)
        )
        return await disabled.executeProduction(input, token: token)
    }

    func runRecordingMetadataCutover(
        configuration cutoverConfiguration: CanonicalSingleDomainCutoverConfiguration = .disabled,
        token: CanonicalCutoverToken?,
        evidence: CanonicalRecordingMetadataCutoverEvidence,
        candidates: [CanonicalRecordingMetadataCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger,
        executor: any CanonicalRecordingMetadataCutoverExecutor
    ) async -> CanonicalCutoverResult {
        await CanonicalRecordingMetadataCutoverRunner().run(
            configuration: cutoverConfiguration,
            token: token,
            evidence: evidence,
            candidates: candidates,
            trigger: trigger,
            nodeRole: .mac,
            executor: executor
        )
    }

    private nonisolated var kernelFacade: CanonicalKernelFacade {
        CanonicalKernelFacade(
            configuration: CanonicalKernelConfiguration(
                mode: configuration.mode,
                productionPolicy: configuration.productionPolicy
            ),
            environment: CanonicalKernelEnvironment(ports: ports)
        )
    }

    private nonisolated func productionInput(from plan: CanonicalDryRunMigrationPlan) -> CanonicalProductionExecutionInput {
        CanonicalProductionExecutionInput(
            operationID: "mac-canonical-shadow-\(plan.dryRunID)",
            domains: [.recordingMetadata, .fileRuntime],
            steps: [],
            rollbackPlan: CanonicalRollbackPlan(
                planID: "mac-canonical-shadow-rollback-\(plan.dryRunID)",
                checkpoints: [
                    CanonicalRollbackCheckpoint(
                        checkpointID: "mac-shadow-file-checkpoint",
                        domain: .fileRuntime
                    )
                ],
                actions: [
                    CanonicalRollbackAction(
                        actionID: "mac-shadow-file-rollback",
                        kind: .fileWriteRollback,
                        domain: .fileRuntime,
                        checkpointID: "mac-shadow-file-checkpoint"
                    ),
                    CanonicalRollbackAction(
                        actionID: "mac-shadow-metadata-rollback",
                        kind: .metadataRollback,
                        domain: .recordingMetadata,
                        checkpointID: "mac-shadow-file-checkpoint"
                    )
                ]
            ),
            dryRunReportID: plan.dryRunID,
            dryRunEquivalence: plan.equivalenceReport,
            readinessReport: plan.readinessReport,
            unresolvedConflictCount: plan.blockers.filter { $0.kind == .unresolvedConflict }.count
        )
    }
}

nonisolated enum MacCanonicalProductionPorts {
    nonisolated static func makeDisabledPortSet(
        chunkSizePolicy: Int = 4 * 1024 * 1024
    ) -> CanonicalProductionPortSet {
        CanonicalProductionPortSet(
            file: MacCanonicalProductionFilePort(),
            transport: MacCanonicalProductionTransportPort(),
            upload: MacCanonicalProductionUploadPort(chunkSizePolicy: chunkSizePolicy),
            apply: MacCanonicalProductionApplyPort()
        )
    }

    nonisolated static func makeFakeInMemoryPortSet(
        rootURL: URL,
        rootToken: CanonicalRootToken = CanonicalRootToken("mac-test-root"),
        chunkSizePolicy: Int = 4 * 1024 * 1024,
        transportResponder: @escaping MacCanonicalProductionTransportPort.FakeResponder = { _ in
            CanonicalTransportResponse(ok: true, status: "ok", body: Data("{}".utf8))
        }
    ) -> CanonicalProductionPortSet {
        CanonicalProductionPortSet(
            file: MacCanonicalProductionFilePort(testRootURL: rootURL, rootToken: rootToken),
            transport: MacCanonicalProductionTransportPort(fakeResponder: transportResponder),
            upload: MacCanonicalProductionUploadPort(testOnlyChunkSizePolicy: chunkSizePolicy),
            apply: MacCanonicalProductionApplyPort(fakeInMemory: true)
        )
    }
}
