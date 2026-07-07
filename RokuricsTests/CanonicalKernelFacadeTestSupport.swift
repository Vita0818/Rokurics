//
//  CanonicalKernelFacadeTestSupport.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
@testable import Rokurics

enum CanonicalKernelFacadeTestSupport {
    static let dryRunReportID = "dry-run-equivalent-report-01"

    static func equivalentDryRunReport() -> CanonicalDryRunEquivalenceReport {
        let reports = CanonicalLegacyEquivalenceDomain.allCases.map {
            CanonicalLegacyEquivalenceDomainReport(domain: $0, status: .equivalent)
        }
        return CanonicalDryRunEquivalenceReport(
            legacyEquivalence: CanonicalLegacyEquivalenceReport(domainReports: reports)
        )
    }

    static func readyReadinessReport() -> CanonicalDryRunReadinessReport {
        CanonicalDryRunReadinessReport(
            states: [.eligibleForRuntimeSwitch],
            portReadiness: CanonicalProductionPortReadiness(
                declaredPorts: Dictionary(uniqueKeysWithValues: CanonicalProductionPortKind.allCases.map { ($0, true) }),
                missingPorts: [],
                dryRunOnly: false
            ),
            blockers: [],
            eligibleForRuntimeSwitch: true,
            retired: false
        )
    }

    static func rollbackPlan() -> CanonicalRollbackPlan {
        CanonicalRollbackPlan(
            planID: "rollback-plan-01",
            checkpoints: [
                CanonicalRollbackCheckpoint(checkpointID: "checkpoint-file", domain: .fileRuntime, objectID: "recording-01")
            ],
            actions: [
                CanonicalRollbackAction(actionID: "rollback-metadata", kind: .metadataRollback, domain: .recordingMetadata, checkpointID: "checkpoint-file"),
                CanonicalRollbackAction(actionID: "rollback-file", kind: .fileWriteRollback, domain: .fileRuntime, checkpointID: "checkpoint-file")
            ]
        )
    }

    static func token(approved: Bool = true, rollbackPlanID: String? = "rollback-plan-01", dryRunReportID: String? = dryRunReportID) -> CanonicalProductionExecutionToken {
        CanonicalProductionExecutionToken(
            mode: .productionExecute,
            domainAllowlist: [.recordingMetadata, .fileRuntime],
            nodeRole: .testHarness,
            syncRunID: "sync-run-01",
            dryRunEquivalentReportID: dryRunReportID,
            rollbackPlanID: rollbackPlanID,
            ownerApproved: approved
        )
    }

    static func fileIntent() -> CanonicalFileWriteIntent {
        let bytes = Data("metadata".utf8)
        return CanonicalFileWriteIntent(
            reference: CanonicalFileReference(
                rootToken: CanonicalRootToken("test-root"),
                logicalPathToken: "metadata/recording-01.json"
            ),
            bytes: bytes,
            purpose: .metadataBlob,
            expectedContentHash: InMemoryCanonicalFileStore.hash(bytes, policy: .sha256),
            expectedByteSize: Int64(bytes.count),
            conflictPolicy: .idempotentIfSameContent
        )
    }

    static func productionFacade(requiredPorts: [CanonicalProductionPortKind] = [.file]) -> CanonicalKernelFacade {
        let file = CanonicalTestProductionFilePort()
        return CanonicalKernelFacade(
            configuration: CanonicalKernelConfiguration(
                mode: .productionExecute,
                productionPolicy: CanonicalProductionExecutionPolicy(
                    requiredDomains: [.recordingMetadata, .fileRuntime],
                    requiredPorts: requiredPorts,
                    requireOwnerApproval: true,
                    requireRollbackPlan: true,
                    requireDryRunEquivalence: true,
                    requireMigrationGateUnblocked: true
                )
            ),
            environment: CanonicalKernelEnvironment(
                ports: CanonicalProductionPortSet(file: file)
            )
        )
    }

    static func productionInput(steps: [CanonicalProductionExecutionStep]? = nil) -> CanonicalProductionExecutionInput {
        CanonicalProductionExecutionInput(
            operationID: "production-test",
            domains: [.recordingMetadata, .fileRuntime],
            steps: steps ?? [
                CanonicalProductionExecutionStep(
                    stepID: "write-metadata",
                    kind: .fileWrite,
                    domain: .recordingMetadata,
                    fileIntent: fileIntent()
                )
            ],
            rollbackPlan: rollbackPlan(),
            dryRunReportID: dryRunReportID,
            dryRunEquivalence: equivalentDryRunReport(),
            readinessReport: readyReadinessReport()
        )
    }
}

actor CanonicalTestProductionFilePort: CanonicalProductionFilePort {
    let isDryRunOnly = false
    let capabilities: [CanonicalProductionCapability] = [.rootBoundFileAccess, .rootBoundRead, .rootBoundWrite, .atomicWriteExecution, .hashSizeVerification, .rollbackCheckpoint]
    private let store = InMemoryCanonicalFileStore(rootBindings: [CanonicalRootToken("test-root"): "test/root"])

    func metadataSnapshot(objectID: String) async throws -> Data? {
        nil
    }

    func artifactDescriptor(for artifact: CanonicalArtifact) async throws -> CanonicalProductionArtifactDescriptor {
        CanonicalProductionArtifactDescriptor(artifact: artifact)
    }

    func validateRead(reference: CanonicalFileReference) async throws -> CanonicalProductionReadProjection {
        _ = try await store.resolve(reference)
        return CanonicalProductionReadProjection(reference: reference, wouldReadBytes: true, dryRun: false)
    }

    func resolveLogicalToken(_ token: String, rootToken: CanonicalRootToken) async throws -> CanonicalPathResolutionResult {
        try await store.resolve(CanonicalFileReference(rootToken: rootToken, logicalPathToken: token))
    }

    func verifyContainment(_ reference: CanonicalFileReference) async throws -> Bool {
        try await store.resolve(reference).isInsideRoot
    }

    func projectWrite(_ intent: CanonicalFileWriteIntent) async throws -> CanonicalProductionWriteIntentProjection {
        CanonicalProductionWriteIntentProjection(
            reference: intent.reference,
            purpose: intent.purpose,
            wouldWrite: true,
            suppressedBecauseDryRun: false,
            noPhysicalDelete: true,
            byteSize: Int64(intent.bytes.count),
            contentHash: InMemoryCanonicalFileStore.hash(intent.bytes, policy: intent.hashPolicy),
            disposition: .created,
            reason: "testProductionProjection"
        )
    }

    func readMetadata(_ request: CanonicalProductionMetadataReadRequest) async throws -> CanonicalProductionFileReadResult {
        let read = try await store.read(CanonicalFileReadRequest(reference: request.reference))
        return CanonicalProductionFileReadResult(
            bytes: read.bytes,
            purpose: read.purpose,
            evidence: evidence(reference: request.reference, resolution: read.resolution, expectedHash: nil, actualHash: read.contentHash, expectedByteSize: nil, actualByteSize: read.byteSize),
            metadataBlob: read.metadataBlob,
            tombstoned: read.tombstoned
        )
    }

    func writeMetadata(_ intent: CanonicalFileWriteIntent, rollbackCheckpoint: CanonicalRollbackCheckpoint?) async throws -> CanonicalProductionFileWriteResult {
        let write = try await store.write(intent)
        return CanonicalProductionFileWriteResult(
            disposition: write.disposition,
            purpose: write.purpose,
            evidence: evidence(
                reference: intent.reference,
                resolution: write.resolution,
                expectedHash: intent.expectedContentHash,
                actualHash: write.contentHash,
                expectedByteSize: intent.expectedByteSize,
                actualByteSize: write.byteSize
            ),
            rollbackCheckpointID: rollbackCheckpoint?.checkpointID,
            tombstoned: write.tombstoned
        )
    }

    func readArtifact(_ request: CanonicalProductionArtifactReadRequest) async throws -> CanonicalProductionFileReadResult {
        let read = try await store.read(CanonicalFileReadRequest(reference: request.reference))
        return CanonicalProductionFileReadResult(
            bytes: read.bytes,
            purpose: read.purpose,
            evidence: evidence(reference: request.reference, resolution: read.resolution, expectedHash: request.expectedContentHash, actualHash: read.contentHash, expectedByteSize: request.expectedByteSize, actualByteSize: read.byteSize),
            metadataBlob: read.metadataBlob,
            tombstoned: read.tombstoned
        )
    }

    func writeArtifactAtomic(_ intent: CanonicalFileWriteIntent, rollbackCheckpoint: CanonicalRollbackCheckpoint?) async throws -> CanonicalProductionFileWriteResult {
        try await writeMetadata(intent, rollbackCheckpoint: rollbackCheckpoint)
    }

    func computeHash(_ request: CanonicalProductionHashRequest) async throws -> CanonicalProductionHashResult {
        let read = try await store.read(CanonicalFileReadRequest(reference: request.reference))
        let hash = read.contentHash ?? CanonicalHash.sha256String("")
        let verification = evidence(reference: request.reference, resolution: read.resolution, expectedHash: hash, actualHash: hash, expectedByteSize: request.expectedByteSize, actualByteSize: read.byteSize, streaming: request.requireStreaming)
        return CanonicalProductionHashResult(contentHash: hash, byteSize: read.byteSize, computedStreaming: request.requireStreaming, evidence: verification)
    }

    func rollbackWrite(_ request: CanonicalProductionFileRollbackRequest) async throws -> CanonicalRollbackResult {
        CanonicalRollbackResult(planID: request.checkpointID, succeeded: true, completedActionIDs: [request.checkpointID])
    }

    private func evidence(
        reference: CanonicalFileReference,
        resolution: CanonicalPathResolutionResult,
        expectedHash: CanonicalHash?,
        actualHash: CanonicalHash?,
        expectedByteSize: Int64?,
        actualByteSize: Int64?,
        streaming: Bool = false
    ) -> CanonicalProductionFileVerificationEvidence {
        CanonicalProductionFileVerificationEvidence(
            reference: reference,
            resolution: resolution,
            expectedHash: expectedHash,
            actualHash: actualHash,
            expectedByteSize: expectedByteSize,
            actualByteSize: actualByteSize,
            computedStreaming: streaming
        )
    }
}

struct CanonicalTestProductionTransportPort: CanonicalProductionTransportPort {
    let isDryRunOnly = false
    let realNetworkExecutionEnabled = true
    let routeCapabilities = CanonicalTransportRoute.allCases.map {
        CanonicalProductionTransportRouteCapability(route: $0, dryRunOnly: false)
    }

    func buildEnvelopeDryRun(source: CanonicalNode, destination: CanonicalNode, route: CanonicalTransportRoute, body: Data) async throws -> CanonicalProductionTransportEnvelopeDryRun {
        CanonicalProductionTransportEnvelopeDryRun(route: route, sourceNodeID: source.nodeID, destinationNodeID: destination.nodeID, bodyHash: CanonicalTransportEnvelope.hash(body), reason: "testDryRun")
    }

    func decodeResponseDryRun(_ response: CanonicalTransportResponse) async throws -> CanonicalTransportResponse {
        response
    }

    func buildSignedRequest(_ request: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionSignedRequest {
        CanonicalProductionSignedRequest(buildRequest: request, signature: "fake-signature", signerDescription: "testSigner")
    }

    func sendRequest(_ request: CanonicalProductionSignedRequest) async throws -> CanonicalProductionTransportExchangeResult {
        CanonicalProductionTransportExchangeResult(
            request: request,
            response: CanonicalTransportResponse(ok: true, status: "ok", body: Data("{}".utf8)),
            responseVerified: true,
            usedExistingRoute: true,
            sideEffect: CanonicalProductionSideEffect(kind: .networkRequest, domain: .transportRuntime, route: request.buildRequest.route, summary: "testNetworkRequest")
        )
    }
}

actor CanonicalTestProductionUploadPort: CanonicalProductionUploadPort {
    let isDryRunOnly = false
    let resumableSessionSupported = true
    let chunkSizePolicy = 4
    private var confirmedBytes: Int64 = 0
    private var sessionID = CanonicalUploadSessionID("session-01")

    func projectUploadDryRun(object: CanonicalRecordingObject, artifact: CanonicalArtifact) async throws -> CanonicalProductionUploadTrace {
        CanonicalProductionUploadTrace(objectID: object.objectID, artifactID: artifact.artifactID, totalBytes: artifact.byteSize, totalHash: artifact.contentHash, chunkSize: chunkSizePolicy, reason: "testDryRun")
    }

    func startResumableUpload(_ request: CanonicalUploadStartRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        confirmedBytes = 0
        sessionID = CanonicalUploadSessionID("session-\(request.objectID)")
        return status(totalBytes: request.totalBytes, hash: request.totalHash, completed: false)
    }

    func resumeUpload(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        status(totalBytes: nil, hash: request.totalHash, completed: false)
    }

    func uploadChunk(_ chunk: CanonicalUploadChunk, now: Date) async throws -> CanonicalUploadSessionStatus {
        confirmedBytes += Int64(chunk.bytes.count)
        return status(totalBytes: nil, hash: chunk.totalHash, completed: false)
    }

    func finalizeUpload(_ request: CanonicalUploadFinalizeRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        confirmedBytes = request.totalBytes
        return status(totalBytes: request.totalBytes, hash: request.totalHash, completed: true)
    }

    func writeUploadLedger(_ snapshot: CanonicalProductionUploadLedgerSnapshot) async throws -> CanonicalProductionUploadLedgerSnapshot {
        snapshot
    }

    private func status(totalBytes: Int64?, hash: CanonicalHash, completed: Bool) -> CanonicalUploadSessionStatus {
        CanonicalUploadSessionStatus(
            ok: true,
            disposition: completed ? .finalized : .acceptedNew,
            phase: completed ? .completed : .active,
            sessionID: sessionID,
            confirmedBytes: confirmedBytes,
            nextOffset: confirmedBytes,
            chunkSize: chunkSizePolicy,
            completed: completed,
            finalFile: nil,
            checksum: completed ? hash : nil,
            fileSize: completed ? totalBytes : nil,
            retry: nil,
            error: nil
        )
    }
}

struct CanonicalTestProductionApplyPort: CanonicalProductionApplyPort {
    let isDryRunOnly = false
    let metadataApplySupported = true
    let generatedArtifactApplySupported = true
    let tombstoneApplySupported = true
    let conflictRecordSupported = true

    func projectApplyDryRun(_ action: CanonicalApplyAction) async throws -> CanonicalProductionApplyTrace {
        CanonicalProductionApplyTrace(action: action, wouldCallApplySyncManifest: false, reason: "testDryRun")
    }

    func applyMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        result(request: request, status: .applied, kind: .metadataApply)
    }

    func sendMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        result(request: request, status: .sent, kind: .metadataApply)
    }

    func applyGeneratedArtifact(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        result(request: request, status: .applied, kind: .generatedArtifactApply)
    }

    func recordConflict(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        result(request: request, status: .conflictRecorded, kind: .conflictRecord)
    }

    private func result(
        request: CanonicalProductionApplyExecutionRequest,
        status: CanonicalApplyExecutionStatus,
        kind: CanonicalProductionSideEffectKind
    ) -> CanonicalProductionApplyResult {
        CanonicalProductionApplyResult(
            actionID: request.action.actionID,
            status: status,
            precondition: CanonicalProductionApplyPrecondition(actionID: request.action.actionID, target: request.action.target, accepted: true),
            postcondition: CanonicalProductionApplyPostcondition(actionID: request.action.actionID, target: request.action.target, accepted: true),
            sideEffect: CanonicalProductionSideEffect(kind: kind, domain: .apply, objectID: request.action.target.objectID, summary: kind.rawValue),
            rollbackCheckpointID: request.rollbackCheckpointID
        )
    }
}
