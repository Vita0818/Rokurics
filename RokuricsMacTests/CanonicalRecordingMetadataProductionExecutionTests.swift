//
//  CanonicalRecordingMetadataProductionExecutionTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/3.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalRecordingMetadataProductionExecutionTests {
    @Test func macFacadeDefaultCutoverIsDisabledAndDoesNotCommit() async {
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor()
        let result = await CanonicalMacMigrationFacade().runRecordingMetadataCutover(
            token: RecordingMetadataCutoverTestSupport.token(),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [RecordingMetadataCutoverTestSupport.candidate()],
            trigger: .periodic,
            executor: executor
        )

        #expect(result.gate.failures.contains(.disabled))
        #expect(executor.committedObjectIDs.isEmpty)
    }

    @Test func guardedCommitExecutesOnlyRecordingMetadataApplyThroughFakeExecutor() async {
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor()
        let result = await CanonicalMacMigrationFacade().runRecordingMetadataCutover(
            configuration: CanonicalSingleDomainCutoverConfiguration(mode: .guardedExecuteCommit),
            token: RecordingMetadataCutoverTestSupport.token(),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [RecordingMetadataCutoverTestSupport.candidate()],
            trigger: .periodic,
            executor: executor
        )

        #expect(result.gate.allowed)
        #expect(result.commits.first?.committed == true)
        #expect(result.commits.first?.sideEffect?.kind == .metadataApply)
        #expect(executor.committedObjectIDs == ["recording-01"])
    }

    @Test func sendCandidateUsesExistingApplyMetadataRouteAndNoUploadSideEffects() async throws {
        let candidate = RecordingMetadataCutoverTestSupport.candidate(kind: .recordingMetadataSend)
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            candidates: [candidate]
        )
        let commit = try #require(result.commits.first)

        #expect(MacCanonicalProductionTransportPort().existingRoutePath(for: .applyMetadata) == "/sync/apply-metadata")
        #expect(commit.routePath == "/sync/apply-metadata")
        #expect(commit.sideEffect?.route == .applyMetadata)
        #expect(result.commits.allSatisfy { $0.sideEffect?.kind != .uploadSessionStart })
        #expect(result.commits.allSatisfy { $0.sideEffect?.kind != .uploadChunkSend })
        #expect(result.commits.allSatisfy { $0.sideEffect?.kind != .uploadFinalize })
    }

    @Test func kernelRoutesRecordingMetadataSendToSendMetadataNotApplyMetadata() async throws {
        let apply = TrackingRecordingMetadataApplyPort()
        let action = RecordingMetadataCutoverTestSupport.candidate(kind: .recordingMetadataSend).action
        let input = CanonicalProductionExecutionInput(
            operationID: "recording-metadata-send",
            domains: [.recordingMetadata],
            steps: [
                CanonicalProductionExecutionStep(
                    stepID: "recording-metadata-send-step",
                    kind: .metadataApply,
                    domain: .recordingMetadata,
                    applyAction: action
                )
            ],
            rollbackPlan: RecordingMetadataCutoverTestSupport.rollbackPlan(),
            dryRunReportID: CanonicalKernelFacadeTestSupport.dryRunReportID,
            dryRunEquivalence: CanonicalKernelFacadeTestSupport.equivalentDryRunReport(),
            readinessReport: CanonicalKernelFacadeTestSupport.readyReadinessReport()
        )
        let token = CanonicalProductionExecutionToken(
            mode: .productionExecute,
            domainAllowlist: [.recordingMetadata],
            nodeRole: .testHarness,
            syncRunID: "sync-run-01",
            dryRunEquivalentReportID: CanonicalKernelFacadeTestSupport.dryRunReportID,
            rollbackPlanID: "recording-metadata-rollback-plan",
            ownerApproved: true
        )
        let facade = CanonicalKernelFacade(
            configuration: CanonicalKernelConfiguration(
                mode: .productionExecute,
                productionPolicy: CanonicalProductionExecutionPolicy(
                    requiredDomains: [.recordingMetadata],
                    requiredPorts: [.apply]
                )
            ),
            environment: CanonicalKernelEnvironment(ports: CanonicalProductionPortSet(apply: apply))
        )

        let result = await facade.executeProduction(input, token: token)

        #expect(result.payload?.succeeded == true)
        #expect(await apply.sendCount == 1)
        #expect(await apply.applyCount == 0)
    }

    @Test func nonRecordingMetadataActionIsUnsupportedAndDoesNotWriteGeneratedArtifacts() async {
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor()
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            candidates: [
                RecordingMetadataCutoverTestSupport.candidate(kind: .generatedArtifactDownloadApply)
            ],
            executor: executor
        )

        #expect(result.gate.failures.contains(.unsupportedAction))
        #expect(result.commits.isEmpty)
        #expect(executor.committedObjectIDs.isEmpty)
    }
}

private actor TrackingRecordingMetadataApplyPort: CanonicalProductionApplyPort {
    let isDryRunOnly = false
    let metadataApplySupported = true
    let generatedArtifactApplySupported = false
    let tombstoneApplySupported = false
    let conflictRecordSupported = false

    private(set) var applyCount = 0
    private(set) var sendCount = 0

    func projectApplyDryRun(_ action: CanonicalApplyAction) async throws -> CanonicalProductionApplyTrace {
        CanonicalProductionApplyTrace(action: action, wouldCallApplySyncManifest: false, reason: "trackingDryRun")
    }

    func applyMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        applyCount += 1
        return result(request: request, status: .applied)
    }

    func sendMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        sendCount += 1
        return result(request: request, status: .sent)
    }

    func applyGeneratedArtifact(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        throw CanonicalProductionPortError.unsupportedObject("generatedArtifactCutoverDenied")
    }

    func recordConflict(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        throw CanonicalProductionPortError.unsupportedObject("conflictCutoverDenied")
    }

    private func result(
        request: CanonicalProductionApplyExecutionRequest,
        status: CanonicalApplyExecutionStatus
    ) -> CanonicalProductionApplyResult {
        CanonicalProductionApplyResult(
            actionID: request.action.actionID,
            status: status,
            precondition: CanonicalProductionApplyPrecondition(actionID: request.action.actionID, target: request.action.target, accepted: true),
            postcondition: CanonicalProductionApplyPostcondition(actionID: request.action.actionID, target: request.action.target, accepted: true),
            sideEffect: CanonicalProductionSideEffect(kind: .metadataApply, domain: .recordingMetadata, objectID: request.action.target.objectID, summary: status.rawValue),
            rollbackCheckpointID: request.rollbackCheckpointID
        )
    }
}
