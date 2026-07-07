//
//  CanonicalGeneratedArtifactCanaryTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalGeneratedArtifactCanaryTests {
    @Test func v823MacN1ConfigurationIsExplicitAndDefaultOff() {
        let disabled = CanonicalGeneratedArtifactCanaryConfiguration()
        let n1 = CanonicalGeneratedArtifactCanaryConfiguration.internalN1()

        #expect(disabled.mode == .disabled)
        #expect(disabled.strictN1Enabled == false)
        #expect(n1.mode == .n1)
        #expect(n1.domain == .generatedArtifacts)
        #expect(n1.canaryMaxObjectsPerSyncRun == 1)
        #expect(n1.explicitInternalTestConfiguration)
        #expect(n1.strictN1Enabled)
    }

    @Test func macN1CanaryCommitsExactlyOneSafeCandidateWhenExecutorAndPeerAreExplicitlyPresent() async {
        let candidate = GeneratedArtifactCutoverTestSupport.candidate(kind: .summaryJSON).candidate
        let executor = GeneratedArtifactCutoverTestSupport.FakeExecutor()

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded)
        #expect(result.cutoverResult.canaryAttemptedCount == 1)
        #expect(result.selection.selectedCandidates.count == 1)
        #expect(result.observationReport.status == .committed)
        #expect(result.observationReport.generatedArtifactDownloadOnly)
        #expect(result.observationReport.audioUploadAttempted == false)
        #expect(result.observationReport.uiMutated == false)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1CandidateSelected })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1CommitCompleted })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1ReadSideParallelEquivalent })
        #expect(await executor.committedActionIDs == [candidate.action.actionID])
    }

    @Test func macPeerSnapshotUnavailableBlocksN1AsReportOnly() async {
        let result = await CanonicalGeneratedArtifactN1CanaryRunner().run(
            configuration: .internalN1(),
            policy: Self.policy(),
            token: GeneratedArtifactCutoverTestSupport.token(),
            evidence: GeneratedArtifactCutoverTestSupport.evidence(),
            candidates: [],
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "v823-generated-artifact-mac",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: false,
            peerNode: nil,
            executor: nil
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.gate.failures.contains(.peerSnapshotUnavailable))
        #expect(result.cutoverResult.gate.failures.contains(.commitExecutorUnavailable))
        #expect(result.cutoverResult.canaryAttemptedCount == 0)
        #expect(result.cutoverResult.legacyFallbackUsed)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1MacPeerSnapshotUnavailable })
        #expect(result.observationReport.status == .blocked)
    }

    @Test func macSelectorPrioritizesSummaryJSONBeforeTranscriptMarkdown() {
        let transcript = GeneratedArtifactCutoverTestSupport.candidate(objectID: "recording-b", kind: .transcriptMarkdown).candidate
        let summary = GeneratedArtifactCutoverTestSupport.candidate(objectID: "recording-z", kind: .summaryJSON).candidate

        let selection = CanonicalGeneratedArtifactCanarySelector().select(
            mode: .canary,
            policy: Self.policy(),
            trigger: .periodic,
            evidence: GeneratedArtifactCutoverTestSupport.evidence(),
            peerNode: GeneratedArtifactCutoverTestSupport.macNode(),
            candidates: [transcript, summary]
        )

        #expect(selection.selectedCandidates.count == 1)
        #expect(selection.selectedCandidates.first?.artifactKind == .summaryJSON)
    }

    private static func run(
        candidates: [CanonicalGeneratedArtifactCutoverCandidate],
        executor: (any CanonicalGeneratedArtifactCutoverExecutor)?
    ) async -> CanonicalGeneratedArtifactCanaryResult {
        await CanonicalGeneratedArtifactN1CanaryRunner().run(
            configuration: .internalN1(),
            policy: Self.policy(),
            token: GeneratedArtifactCutoverTestSupport.token(),
            evidence: GeneratedArtifactCutoverTestSupport.evidence(),
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "v823-generated-artifact-mac-canary",
            peerNode: GeneratedArtifactCutoverTestSupport.macNode(),
            executor: executor
        )
    }

    private static func policy() -> CanonicalGeneratedArtifactCanaryPolicy {
        CanonicalGeneratedArtifactCanaryPolicy(
            canaryMaxObjectsPerSyncRun: 1,
            allowsInternalN1Execution: true,
            explicitInternalTestConfiguration: true
        )
    }
}
