//
//  CanonicalRollbackPlanTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/2.
//

import Testing
@testable import Rokurics

struct CanonicalRollbackPlanTests {
    @Test func rollbackPlanCoversRequiredProductionDomains() {
        let plan = CanonicalRollbackPlan(
            planID: "rollback-all",
            checkpoints: [
                CanonicalRollbackCheckpoint(checkpointID: "metadata", domain: .recordingMetadata),
                CanonicalRollbackCheckpoint(checkpointID: "artifact", domain: .generatedArtifacts),
                CanonicalRollbackCheckpoint(checkpointID: "upload", domain: .uploadRuntime),
                CanonicalRollbackCheckpoint(checkpointID: "file", domain: .fileRuntime)
            ],
            actions: [
                CanonicalRollbackAction(actionID: "metadata", kind: .metadataRollback, domain: .recordingMetadata),
                CanonicalRollbackAction(actionID: "artifact", kind: .generatedArtifactRollback, domain: .generatedArtifacts),
                CanonicalRollbackAction(actionID: "tombstone", kind: .tombstoneRollback, domain: .tombstones),
                CanonicalRollbackAction(actionID: "upload", kind: .uploadSessionCancel, domain: .uploadRuntime),
                CanonicalRollbackAction(actionID: "transport", kind: .transportNoOpRollback, domain: .transportRuntime),
                CanonicalRollbackAction(actionID: "conflict", kind: .conflictLedgerNoOp, domain: .conflicts),
                CanonicalRollbackAction(actionID: "file", kind: .fileWriteRollback, domain: .fileRuntime)
            ]
        )

        #expect(plan.coversAll([.recordingMetadata, .generatedArtifacts, .tombstones, .uploadRuntime, .transportRuntime, .conflicts, .fileRuntime]))
    }

    @Test func rollbackAuditReportsMissingDomains() {
        let audit = CanonicalRollbackAudit(
            plan: CanonicalKernelFacadeTestSupport.rollbackPlan(),
            requiredDomains: [.recordingMetadata, .fileRuntime, .uploadRuntime]
        )

        #expect(audit.rollbackRequiredForProduction)
        #expect(audit.missingDomains == [.uploadRuntime])
    }

    @Test func rollbackResultCanOnlyReportContractOutcome() {
        let result = CanonicalRollbackResult(planID: "rollback-plan", succeeded: false, failures: [
            CanonicalRollbackFailure(actionID: "upload", reason: "/Users/example/secret/path")
        ])

        #expect(result.succeeded == false)
        #expect(result.failures.first?.reason.contains("/Users/") == false)
    }
}
