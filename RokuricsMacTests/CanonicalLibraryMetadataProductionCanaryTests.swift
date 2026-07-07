//
//  CanonicalLibraryMetadataProductionCanaryTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalLibraryMetadataProductionCanaryTests {
    @Test func macBootstrapDefaultsOffAndExplicitTestRootInjectsExecutor() throws {
        let disabled = try MacLibraryMetadataProductionCanaryBootstrap().prepare()
        let rootURL = MacLibraryMetadataCutoverTestSupport.makeScratchRoot("MacV818ProductionCanaryBootstrap")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let injected = try MacLibraryMetadataProductionCanaryBootstrap(
            configuration: .explicitTestRootN1Execute()
        ).prepare(
            testRootURL: rootURL,
            evidence: MacLibraryMetadataCutoverTestSupport.evidence()
        )

        #expect(disabled.executorInjected == false)
        #expect(disabled.applyPortInjected == false)
        #expect(disabled.blockers == [.disabled])
        #expect(injected.executorInjected)
        #expect(injected.applyPortInjected)
        #expect(injected.evidence.applyPortMode == .testRootBound)
        #expect(injected.evidence.testRootUsed)
    }

    @Test func macExplicitN1CanExecuteOnlyWithPeerSnapshotEvidence() async {
        let candidate = MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = MacV818LibraryMetadataFakeExecutor()

        let result = await Self.run(
            configuration: .explicitTestRootN1Execute(),
            candidates: [candidate],
            peerSnapshotAvailable: true,
            executor: executor
        )

        #expect(result.succeeded)
        #expect(result.executed)
        #expect(result.observationReport.status == .executedSucceeded)
        #expect(result.cutoverResult?.duplicateLegacySuppressedActionIDs == [candidate.action.actionID])
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryExecutionCompleted })
        #expect(await executor.committedActionIDs == [candidate.action.actionID])
    }

    @Test func macRealCanaryBlocksWhenPeerSnapshotUnavailable() async {
        let candidate = MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = MacV818LibraryMetadataFakeExecutor()

        let result = await Self.run(
            configuration: .explicitTestRootN1Execute(),
            candidates: [candidate],
            peerSnapshotAvailable: false,
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(result.executed == false)
        #expect(result.blockers.contains(.peerSnapshotUnavailable))
        #expect(result.observationReport.legacyFallbackPreserved)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryBlocked })
        #expect(await executor.committedActionIDs.isEmpty)
    }

    @Test func macProductionRootExplicitAllowFalseDoesNotInjectEvenWhenRootURLIsProvided() async throws {
        let rootURL = MacLibraryMetadataCutoverTestSupport.makeScratchRoot("MacV818ProductionRootDenied")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let configuration = CanonicalLibraryMetadataProductionCanaryConfiguration
            .explicitProductionRootN1Execute(allowProductionRootWrites: false)
        let bootstrap = try MacLibraryMetadataProductionCanaryBootstrap(
            configuration: configuration
        ).prepare(
            productionRootURL: rootURL,
            evidence: MacLibraryMetadataCutoverTestSupport.evidence()
        )

        let result = await Self.run(
            configuration: bootstrap.configuration,
            evidence: bootstrap.evidence,
            candidates: [MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            peerSnapshotAvailable: true,
            executor: bootstrap.executor
        )

        #expect(bootstrap.executorInjected == false)
        #expect(bootstrap.applyPortInjected == false)
        #expect(bootstrap.evidence.applyPortMode == MacLibraryMetadataCutoverTestSupport.evidence().applyPortMode)
        #expect(bootstrap.blockers.contains(.productionRootWritesDisabled))
        #expect(result.executed == false)
        #expect(result.blockers.contains(.productionRootWritesDisabled))
        #expect(result.blockers.contains(.productionRootGuardMissing))
    }

    @Test func macAllowProductionRootWritesTrueInjectsProductionRootBoundExecutorInV831() async throws {
        let rootURL = MacLibraryMetadataCutoverTestSupport.makeScratchRoot("MacV830ProductionRootAllowTrue")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pair = MacLibraryMetadataCutoverTestSupport.folderCandidate()
        let configuration = CanonicalLibraryMetadataProductionCanaryConfiguration
            .explicitProductionRootN1Execute(allowProductionRootWrites: true)
        let bootstrap = try MacLibraryMetadataProductionCanaryBootstrap(
            configuration: configuration
        ).prepare(
            productionRootURL: rootURL,
            evidence: MacLibraryMetadataCutoverTestSupport.evidence()
        )
        try await bootstrap.applyPort?.setRootBoundLibraryMetadataPayload(candidate: pair.candidate, metadataBytes: pair.bytes)

        let result = await Self.run(
            configuration: bootstrap.configuration,
            evidence: bootstrap.evidence,
            candidates: [pair.candidate],
            peerSnapshotAvailable: true,
            executor: bootstrap.executor
        )

        #expect(bootstrap.executorInjected)
        #expect(bootstrap.applyPortInjected)
        #expect(bootstrap.evidence.applyPortMode == .productionRootBound)
        #expect(result.succeeded)
        #expect(result.productionRootGate?.allowed == true)
        #expect(result.productionRootSafetyProof?.redacted == true)
    }

    private static func run(
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration,
        evidence: CanonicalLibraryMetadataCutoverEvidence = MacLibraryMetadataCutoverTestSupport.evidence(),
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        peerSnapshotAvailable: Bool,
        executor: (any CanonicalLibraryMetadataCutoverExecutor)?
    ) async -> CanonicalLibraryMetadataProductionCanaryInjectionResult {
        await CanonicalLibraryMetadataProductionCanaryInjection().evaluateOrRun(
            configuration: configuration,
            token: MacLibraryMetadataCutoverTestSupport.token(),
            evidence: evidence,
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "v818-library-metadata-mac-production-canary",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: peerSnapshotAvailable,
            executor: executor
        )
    }
}

private actor MacV818LibraryMetadataFakeExecutor: CanonicalLibraryMetadataCutoverExecutor {
    private(set) var committedActionIDs: [String] = []

    func commitLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate
    ) async -> CanonicalLibraryMetadataProductionCommitResult {
        committedActionIDs.append(candidate.action.actionID)
        return .success(
            candidate: candidate,
            payloadByteCount: 64,
            sideEffects: [
                CanonicalProductionSideEffect(
                    kind: .metadataApply,
                    domain: candidate.domain.productionDomain,
                    objectID: candidate.objectID,
                    byteSize: 64,
                    hash: candidate.expectedMetadataHash,
                    summary: "macV818LibraryMetadataApply"
                )
            ]
        )
    }

    func rollbackLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate,
        reason: CanonicalLibraryMetadataCutoverFailure
    ) async -> CanonicalLibraryMetadataRollbackExecutionResult {
        CanonicalLibraryMetadataRollbackExecutionResult(
            checkpointID: candidate.effectiveRollbackCheckpointID,
            succeeded: true,
            reason: "macV818Rollback"
        )
    }
}
