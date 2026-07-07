//
//  CanonicalIPhoneMigrationFacade.swift
//  Rokurics
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated struct CanonicalIPhoneMigrationFacadeConfiguration: Sendable {
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

    nonisolated static func dryRun() -> CanonicalIPhoneMigrationFacadeConfiguration {
        CanonicalIPhoneMigrationFacadeConfiguration(mode: .dryRun)
    }

    nonisolated static func testProductionExecute(
        policy: CanonicalProductionExecutionPolicy = CanonicalProductionExecutionPolicy()
    ) -> CanonicalIPhoneMigrationFacadeConfiguration {
        CanonicalIPhoneMigrationFacadeConfiguration(
            mode: .productionExecute,
            productionPolicy: policy,
            allowTestHarnessProductionExecution: true
        )
    }
}

nonisolated struct CanonicalIPhoneMigrationShadowPreparation: Sendable {
    var dryRunPlan: CanonicalDryRunMigrationPlan
    var migrationGate: CanonicalProductionMigrationGateReport
    var equivalenceReport: CanonicalDryRunEquivalenceReport
    var productionInput: CanonicalProductionExecutionInput
}

nonisolated struct CanonicalIPhoneMigrationFacade: Sendable {
    var configuration: CanonicalIPhoneMigrationFacadeConfiguration
    var ports: CanonicalProductionPortSet
    var snapshotAdapter: IPhoneCanonicalProductionSnapshotAdapter

    nonisolated init(
        configuration: CanonicalIPhoneMigrationFacadeConfiguration = CanonicalIPhoneMigrationFacadeConfiguration(),
        ports: CanonicalProductionPortSet = IPhoneCanonicalProductionPorts.makeDisabledPortSet(),
        snapshotAdapter: IPhoneCanonicalProductionSnapshotAdapter = IPhoneCanonicalProductionSnapshotAdapter()
    ) {
        self.configuration = configuration
        self.ports = ports
        self.snapshotAdapter = snapshotAdapter
    }

    nonisolated func makeSnapshot(_ input: IPhoneCanonicalProductionSnapshotInput) -> CanonicalProductionSnapshot {
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
    ) -> CanonicalIPhoneMigrationShadowPreparation? {
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
        return CanonicalIPhoneMigrationShadowPreparation(
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
            nodeRole: .iPhone,
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
            operationID: "iphone-canonical-shadow-\(plan.dryRunID)",
            domains: [.recordingMetadata, .fileRuntime],
            steps: [],
            rollbackPlan: CanonicalRollbackPlan(
                planID: "iphone-canonical-shadow-rollback-\(plan.dryRunID)",
                checkpoints: [
                    CanonicalRollbackCheckpoint(
                        checkpointID: "iphone-shadow-file-checkpoint",
                        domain: .fileRuntime
                    )
                ],
                actions: [
                    CanonicalRollbackAction(
                        actionID: "iphone-shadow-file-rollback",
                        kind: .fileWriteRollback,
                        domain: .fileRuntime,
                        checkpointID: "iphone-shadow-file-checkpoint"
                    ),
                    CanonicalRollbackAction(
                        actionID: "iphone-shadow-metadata-rollback",
                        kind: .metadataRollback,
                        domain: .recordingMetadata,
                        checkpointID: "iphone-shadow-file-checkpoint"
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

nonisolated enum IPhoneCanonicalProductionPorts {
    nonisolated static func makeDisabledPortSet(
        chunkSizePolicy: Int = 4 * 1024 * 1024
    ) -> CanonicalProductionPortSet {
        CanonicalProductionPortSet(
            file: IPhoneCanonicalProductionFilePort(),
            transport: IPhoneCanonicalProductionTransportPort(),
            upload: IPhoneCanonicalProductionUploadPort(chunkSizePolicy: chunkSizePolicy),
            apply: IPhoneCanonicalProductionApplyPort()
        )
    }

    nonisolated static func makeFakeInMemoryPortSet(
        rootURL: URL,
        rootToken: CanonicalRootToken = CanonicalRootToken("iphone-test-root"),
        chunkSizePolicy: Int = 4 * 1024 * 1024,
        transportResponder: @escaping IPhoneCanonicalProductionTransportPort.FakeResponder = { _ in
            CanonicalTransportResponse(ok: true, status: "ok", body: Data("{}".utf8))
        }
    ) -> CanonicalProductionPortSet {
        CanonicalProductionPortSet(
            file: IPhoneCanonicalProductionFilePort(testRootURL: rootURL, rootToken: rootToken),
            transport: IPhoneCanonicalProductionTransportPort(fakeResponder: transportResponder),
            upload: IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: chunkSizePolicy),
            apply: IPhoneCanonicalProductionApplyPort(fakeInMemory: true)
        )
    }
}
