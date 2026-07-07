//
//  CanonicalGeneratedArtifactCutoverTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/4.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalGeneratedArtifactCutoverTests {
    @Test func appSeamDefaultsDisabledAndCanaryBudgetZero() {
        let config = CanonicalGeneratedArtifactCutoverAppSeamConfiguration()

        #expect(config.isEnabled == false)
        #expect(config.effectiveMode == .disabled)
        #expect(config.policy.canaryPolicy.canaryMaxObjectsPerSyncRun == 0)
        #expect(config.policy.canaryPolicy.allowsInternalN1Execution == false)
        #expect(config.policy.canaryPolicy.stagePolicy.requestedStage == .disabled)
    }

    @Test func generatedArtifactKindsAreV89Only() {
        #expect(CanonicalProjectionContract.generatedArtifactKinds == [
            .transcriptJSON,
            .transcriptMarkdown,
            .noteMarkdown,
            .noteJSON,
            .summaryJSON
        ])
        #expect(CanonicalProjectionContract.generatedArtifactKinds.contains(.audio) == false)
        #expect(CanonicalProjectionContract.generatedArtifactKinds.contains(.metadata) == false)
        #expect(CanonicalProjectionContract.generatedArtifactKinds.contains(.receiveRecord) == false)
    }

    @Test func canaryN1RequiresExplicitInternalConfiguration() {
        let candidate = GeneratedArtifactCutoverTestSupport.candidate().candidate
        let gate = CanonicalGeneratedArtifactCutoverRunner().evaluateGate(
            mode: .canary,
            policy: CanonicalGeneratedArtifactCanaryPolicy(canaryMaxObjectsPerSyncRun: 1),
            token: GeneratedArtifactCutoverTestSupport.token(),
            evidence: GeneratedArtifactCutoverTestSupport.evidence(),
            candidates: [candidate],
            peerNode: GeneratedArtifactCutoverTestSupport.macNode(),
            trigger: .periodic
        )

        #expect(gate.allowed == false)
        #expect(gate.failures.contains(.missingInternalCanaryConfiguration))
    }

    @Test func noCommitExecutorStagesOnlyRedactedSummaryAndPreservesLegacyFallback() throws {
        let rootURL = GeneratedArtifactCutoverTestSupport.makeScratchRoot("IPhoneGeneratedArtifactNoCommit")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let candidate = GeneratedArtifactCutoverTestSupport.candidate()
        let executor = IPhoneGeneratedArtifactNoCommitExecutor(stagingRootURL: rootURL)

        let result = executor.stageGeneratedArtifactNoCommit(
            CanonicalGeneratedArtifactNoCommitCandidate(cutoverCandidate: candidate.candidate)
        )

        #expect(result.staged)
        #expect(result.wroteOnlyStagingRoot)
        #expect(result.productionCommitSuppressed)
        #expect(result.legacyDuplicateSuppressed == false)
        #expect(result.wouldRequestRoute == "/sync/artifact-request")
        #expect(result.cleanupEvidence?.status == .removed)
        #expect(result.payloadHashPrefix?.count == 12)
        #expect(result.payloadByteCount > 0)
        #expect(FileManager.default.fileExists(atPath: rootURL.path) == false)
    }

    @Test func rootBoundApplyCommitAndRollbackRestorePreviousBytes() async throws {
        let rootURL = GeneratedArtifactCutoverTestSupport.makeScratchRoot("IPhoneGeneratedArtifactRootBound")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let candidate = GeneratedArtifactCutoverTestSupport.candidate(kind: .transcriptMarkdown)
        let previousBytes = Data("previous-v89-artifact".utf8)
        let logicalPath = CanonicalRootBoundGeneratedArtifactTarget.defaultLogicalPathToken(
            objectID: candidate.candidate.objectID,
            kind: .transcriptMarkdown
        )
        let previousURL = rootURL.appendingPathComponent(logicalPath)
        try FileManager.default.createDirectory(at: previousURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try previousBytes.write(to: previousURL)

        let applyPort = try IPhoneGeneratedArtifactRealApplyPort(testRootURL: rootURL)
        try await GeneratedArtifactCutoverTestSupport.seedPayload(candidate, into: applyPort)
        let executor = IPhoneGeneratedArtifactCutoverExecutor(
            applyPort: applyPort,
            peerNode: GeneratedArtifactCutoverTestSupport.macNode()
        )

        let result = await GeneratedArtifactCutoverTestSupport.run(candidates: [candidate.candidate], executor: executor)
        let committedBytes = try await applyPort.rootBoundArtifactBytes(
            objectID: candidate.candidate.objectID,
            artifactID: candidate.candidate.artifactID ?? "",
            kind: .transcriptMarkdown
        )
        let rollback = await executor.rollbackGeneratedArtifact(candidate.candidate, reason: .postconditionMismatch)
        let restoredBytes = try await applyPort.rootBoundArtifactBytes(
            objectID: candidate.candidate.objectID,
            artifactID: candidate.candidate.artifactID ?? "",
            kind: .transcriptMarkdown
        )

        #expect(result.canarySucceeded)
        #expect(result.commits.first?.sideEffects.map(\.kind) == [.generatedArtifactApply])
        #expect(committedBytes == candidate.bytes)
        #expect(rollback.succeeded)
        #expect(restoredBytes == previousBytes)
    }

    @Test func productionRootApplyPortIsDisabledByDefault() async throws {
        let rootURL = GeneratedArtifactCutoverTestSupport.makeScratchRoot("IPhoneGeneratedArtifactProductionDisabled")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let candidate = GeneratedArtifactCutoverTestSupport.candidate()
        let applyPort = try IPhoneGeneratedArtifactRealApplyPort(productionRootURL: rootURL)
        try await GeneratedArtifactCutoverTestSupport.seedPayload(candidate, into: applyPort)
        let executor = IPhoneGeneratedArtifactCutoverExecutor(
            applyPort: applyPort,
            peerNode: GeneratedArtifactCutoverTestSupport.macNode()
        )

        let commit = await executor.commitGeneratedArtifact(candidate.candidate)

        #expect(applyPort.isDryRunOnly)
        #expect(applyPort.applyPortMode == .productionRootDisabled)
        #expect(commit.committed == false)
        #expect(commit.failureKind == .applyFailureBeforeCommit)
        #expect(try await applyPort.rootBoundArtifactBytes(
            objectID: candidate.candidate.objectID,
            artifactID: candidate.candidate.artifactID ?? "",
            kind: candidate.candidate.artifactKind ?? .transcriptJSON
        ) == nil)
    }

    @Test func canaryCommitSuppressesOnlyMatchingLegacyArtifactAfterSuccess() async {
        let candidate = GeneratedArtifactCutoverTestSupport.candidate(kind: .noteJSON)
        let executor = GeneratedArtifactCutoverTestSupport.FakeExecutor()

        let result = await GeneratedArtifactCutoverTestSupport.run(candidates: [candidate.candidate], executor: executor)
        let suppressed = CanonicalGeneratedArtifactLegacyDuplicateSuppression.suppressedLegacyActionIDs(
            after: result,
            legacyActions: [
                CanonicalGeneratedArtifactLegacyActionIdentity(
                    actionID: "legacy-match",
                    objectID: candidate.candidate.objectID,
                    artifactID: candidate.candidate.artifactID,
                    artifactKind: .noteJSON
                ),
                CanonicalGeneratedArtifactLegacyActionIdentity(
                    actionID: "legacy-other-kind",
                    objectID: candidate.candidate.objectID,
                    artifactID: candidate.candidate.artifactID,
                    artifactKind: .summaryJSON
                )
            ]
        )

        #expect(result.canarySucceeded)
        #expect(result.duplicateLegacySuppressedActionIDs == [candidate.candidate.action.actionID])
        #expect(suppressed == ["legacy-match"])
        #expect(await executor.committedActionIDs == [candidate.candidate.action.actionID])
    }

    @Test func failureRollsBackAndPreservesLegacyFallback() async {
        let candidate = GeneratedArtifactCutoverTestSupport.candidate()
        let executor = GeneratedArtifactCutoverTestSupport.FakeExecutor(.postconditionMismatch)

        let result = await GeneratedArtifactCutoverTestSupport.run(candidates: [candidate.candidate], executor: executor)
        let suppressed = CanonicalGeneratedArtifactLegacyDuplicateSuppression.suppressedLegacyActionIDs(
            after: result,
            legacyActions: [
                CanonicalGeneratedArtifactLegacyActionIdentity(
                    actionID: "legacy-match",
                    objectID: candidate.candidate.objectID,
                    artifactID: candidate.candidate.artifactID,
                    artifactKind: candidate.candidate.artifactKind ?? .transcriptJSON
                )
            ]
        )

        #expect(result.canarySucceeded == false)
        #expect(result.rollbackResults.first?.succeeded == true)
        #expect(result.legacyFallbackUsed)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(suppressed.isEmpty)
        #expect(await executor.rolledBackActionIDs == [candidate.candidate.action.actionID])
    }

    @Test func readSideProjectionIsDiagnosticsOnly() async throws {
        let candidate = GeneratedArtifactCutoverTestSupport.candidate(kind: .summaryJSON)
        let result = await GeneratedArtifactCutoverTestSupport.run(
            candidates: [candidate.candidate],
            executor: GeneratedArtifactCutoverTestSupport.FakeExecutor()
        )
        let projection = try #require(result.readSideProjection)

        #expect(projection.equivalent)
        #expect(projection.mutatedUI == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactUIProjectionParallelReadStarted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactUIProjectionParallelReadEquivalent })
    }
}

enum GeneratedArtifactCutoverTestSupport {
    static func macNode() -> CanonicalNode {
        CanonicalNode(
            nodeID: "mac-01",
            platform: "Mac",
            capabilities: [.recordingMetadata, .transcriptArtifact, .noteArtifact, .summaryArtifact]
        )
    }

    static func token() -> CanonicalCutoverToken {
        CanonicalCutoverToken(tokenID: "generated-artifact-token", syncRunID: "sync-run-v89", ownerApproved: true)
    }

    static func evidence() -> CanonicalGeneratedArtifactCutoverEvidence {
        CanonicalGeneratedArtifactCutoverEvidence.passing(
            rollbackPlan: CanonicalRollbackPlan(
                planID: "generated-artifact-rollback-plan",
                checkpoints: [
                    CanonicalRollbackCheckpoint(
                        checkpointID: "generated-artifact-checkpoint",
                        domain: .generatedArtifacts,
                        objectID: "recording-01",
                        artifactID: "artifact-transcriptJSON-recording-01"
                    )
                ],
                actions: [
                    CanonicalRollbackAction(
                        actionID: "generated-artifact-rollback",
                        kind: .generatedArtifactRollback,
                        domain: .generatedArtifacts,
                        checkpointID: "generated-artifact-checkpoint"
                    )
                ]
            )
        )
    }

    static func run(
        candidates: [CanonicalGeneratedArtifactCutoverCandidate],
        executor: any CanonicalGeneratedArtifactCutoverExecutor
    ) async -> CanonicalGeneratedArtifactCutoverResult {
        await CanonicalGeneratedArtifactCutoverRunner().run(
            mode: .canary,
            policy: CanonicalGeneratedArtifactCanaryPolicy(
                canaryMaxObjectsPerSyncRun: 1,
                allowsInternalN1Execution: true
            ),
            token: token(),
            evidence: evidence(),
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .iPhone,
            peerNode: macNode(),
            executor: executor
        )
    }

    static func candidate(
        objectID: String = "recording-01",
        kind: CanonicalArtifact.Kind = .transcriptJSON
    ) -> (candidate: CanonicalGeneratedArtifactCutoverCandidate, bytes: Data) {
        let bytes = Data("v89-\(kind.rawValue)-payload".utf8)
        let artifactID = "artifact-\(kind.rawValue)-\(objectID)"
        let artifact = CanonicalArtifact(
            artifactID: artifactID,
            objectID: objectID,
            kind: kind,
            availability: .available,
            contentHash: CanonicalTransportEnvelope.hash(bytes),
            byteSize: Int64(bytes.count),
            logicalName: "\(kind.rawValue).json",
            logicalPathToken: CanonicalRootBoundGeneratedArtifactTarget.defaultLogicalPathToken(objectID: objectID, kind: kind),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2_000)),
            observedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2_010)),
            producedBy: producer(for: kind),
            producedByNodeID: "mac-01"
        )
        let local = recording(objectID: objectID, nodeID: "iphone-01", artifacts: [])
        let peer = recording(objectID: objectID, nodeID: "mac-01", artifacts: [artifact])
        let action = CanonicalApplyAction(
            kind: .generatedArtifactDownloadApply,
            source: .peer,
            target: CanonicalApplyTarget(objectID: objectID, artifactID: artifactID, artifactKind: kind),
            bridgeHint: .legacyArtifactRequestApply,
            reason: "peerAuthoritativeGeneratedArtifact"
        )
        return (
            CanonicalGeneratedArtifactCutoverCandidate(
                action: action,
                localObject: local,
                peerObject: peer,
                rollbackCheckpointID: "checkpoint-\(objectID)-\(kind.rawValue)"
            ),
            bytes
        )
    }

    static func seedPayload(
        _ pair: (candidate: CanonicalGeneratedArtifactCutoverCandidate, bytes: Data),
        into applyPort: IPhoneGeneratedArtifactRealApplyPort
    ) async throws {
        try await applyPort.setRootBoundGeneratedArtifactPayload(
            objectID: pair.candidate.objectID,
            artifactID: pair.candidate.artifactID ?? "",
            kind: pair.candidate.artifactKind ?? .transcriptJSON,
            artifactBytes: pair.bytes,
            expectedContentHash: CanonicalTransportEnvelope.hash(pair.bytes),
            expectedByteSize: Int64(pair.bytes.count),
            actionID: pair.candidate.action.actionID
        )
    }

    static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private static func recording(
        objectID: String,
        nodeID: String,
        artifacts: [CanonicalArtifact]
    ) -> CanonicalRecordingObject {
        CanonicalRecordingObject(
            objectID: objectID,
            nodeID: nodeID,
            metadata: CanonicalRecordingMetadata(
                objectID: objectID,
                title: "Generated Artifact Test",
                createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1_000)),
                modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1_100)),
                duration: 30
            ),
            artifacts: artifacts
        )
    }

    private static func producer(for kind: CanonicalArtifact.Kind) -> CanonicalArtifactProducer {
        switch kind {
        case .transcriptJSON, .transcriptMarkdown:
            return .transcription
        case .noteMarkdown, .noteJSON, .summaryJSON:
            return .noteGeneration
        case .audio, .metadata, .receiveRecord:
            return .unknown
        }
    }

    actor FakeExecutor: CanonicalGeneratedArtifactCutoverExecutor {
        private let failure: CanonicalGeneratedArtifactCutoverFailure?
        private(set) var committedActionIDs: [String] = []
        private(set) var rolledBackActionIDs: [String] = []

        init(_ failure: CanonicalGeneratedArtifactCutoverFailure? = nil) {
            self.failure = failure
        }

        func commitGeneratedArtifact(
            _ candidate: CanonicalGeneratedArtifactCutoverCandidate
        ) async -> CanonicalGeneratedArtifactProductionCommitResult {
            if let failure {
                return .failure(candidate: candidate, kind: failure, partialCommit: true, reason: "injectedGeneratedArtifactFailure")
            }
            committedActionIDs.append(candidate.action.actionID)
            return .success(
                candidate: candidate,
                sideEffects: [
                    CanonicalProductionSideEffect(
                        kind: .generatedArtifactApply,
                        domain: .generatedArtifacts,
                        objectID: candidate.objectID,
                        artifactID: candidate.artifactID,
                        byteSize: candidate.expectedByteSize,
                        hash: candidate.expectedContentHash,
                        summary: "testGeneratedArtifactApply"
                    )
                ]
            )
        }

        func rollbackGeneratedArtifact(
            _ candidate: CanonicalGeneratedArtifactCutoverCandidate,
            reason: CanonicalGeneratedArtifactCutoverFailure
        ) async -> CanonicalGeneratedArtifactRollbackExecutionResult {
            rolledBackActionIDs.append(candidate.action.actionID)
            return CanonicalGeneratedArtifactRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: true,
                reason: "testGeneratedArtifactRollback"
            )
        }
    }
}
