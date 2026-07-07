//
//  CanonicalLibraryMetadataProductionRootPilotTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/6.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalLibraryMetadataProductionRootPilotTests {
    @Test func macDefaultBootstrapCannotProductionRootWriteAndExplicitConfigCanConstructGate() throws {
        let disabled = try MacLibraryMetadataProductionCanaryBootstrap().prepare()
        let candidate = MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let gate = Self.gate(candidates: [candidate])

        #expect(disabled.executorInjected == false)
        #expect(disabled.applyPortInjected == false)
        #expect(disabled.blockers == [.disabled])
        #expect(gate.allowed)
        #expect(gate.selectedCandidate?.domain == .folderMetadata)
    }

    @Test func macProductionRootExplicitRequiresOwnerFreezeRollbackAndReadSideZero() {
        let candidate = MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate
        var divergent = Self.productionEvidence()
        divergent.readSideParallelEquivalent = false
        var noRollback = Self.productionEvidence()
        noRollback.rollbackVerified = false
        var notExplicit = Self.configuration()
        notExplicit.explicitInternalDebugConfiguration = false
        let generatedActive = Self.matrixReplacing(.generatedArtifacts) { policy in
            policy.activePilot = true
            policy.activePilotExplicit = true
            policy.staticOnly = false
            policy.blockedForRealMigration = false
        }

        #expect(Self.gate(configuration: notExplicit, candidates: [candidate]).blockers.contains(.missingExplicitDebugInternalConfiguration))
        #expect(Self.gate(token: Self.token(ownerApproved: false), candidates: [candidate]).blockers.contains(.missingOwnerApproval))
        #expect(Self.gate(evidence: divergent, candidates: [candidate]).blockers.contains(.readSideDivergenceNonZero))
        #expect(Self.gate(evidence: noRollback, candidates: [candidate]).blockers.contains(.rollbackEvidenceMissing))
        #expect(Self.gate(matrix: generatedActive, candidates: [candidate]).blockers.contains(.landingFreezeNotGreen))
    }

    @Test func macProductionRootExplicitExecutesOneSafeCandidateInFakeRoot() async throws {
        let rootURL = MacLibraryMetadataCutoverTestSupport.makeScratchRoot("MacV831ProductionRoot")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pair = MacLibraryMetadataCutoverTestSupport.folderCandidate()
        let bootstrap = try MacLibraryMetadataProductionCanaryBootstrap(
            configuration: Self.configuration()
        ).prepare(
            productionRootURL: rootURL,
            evidence: Self.productionEvidence()
        )
        let port = try #require(bootstrap.applyPort)
        try await port.setRootBoundLibraryMetadataPayload(candidate: pair.candidate, metadataBytes: pair.bytes)

        let result = await Self.run(
            configuration: bootstrap.configuration,
            evidence: bootstrap.evidence,
            candidates: [pair.candidate],
            executor: bootstrap.executor
        )
        let bytes = try await port.rootBoundLibraryMetadataBytes(
            objectID: pair.candidate.objectID,
            objectKind: .folder,
            domain: .folderMetadata
        )

        #expect(result.succeeded)
        #expect(result.productionRootGate?.allowed == true)
        #expect(result.productionRootSafetyProof?.rootContainmentVerified == true)
        #expect(result.cutoverResult?.commits.count == 1)
        #expect(result.cutoverResult?.duplicateLegacySuppressedActionIDs == [pair.candidate.action.actionID])
        #expect(result.observationReport.uiMutated == false)
        #expect(result.observationReport.resourceMoved == false)
        #expect(bytes == pair.bytes)
        #expect(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("receive.json").path) == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataProductionRootReadSideEquivalent })
    }

    @Test func macRequestVerifierBoundaryAndRouteAllowlistRemainUnchanged() {
        let verifier = RequestVerifier(pairedDeviceProvider: { _ in nil })
        let route = MacCanonicalProductionTransportPort().existingRoutePath(for: .applyMetadata)
        let matrix = CanonicalMigrationDomainMatrix.defaultV813()

        #expect(route == "/sync/apply-metadata")
        let verification = verifier.verify(
            method: "POST",
            path: "/sync/apply-metadata",
            headers: [:],
            body: Data()
        )
        switch verification {
        case .rejected:
            break
        case .accepted:
            Issue.record("unsigned apply-metadata request unexpectedly bypassed RequestVerifier")
        }
        #expect(matrix.policy(for: .generatedArtifacts)?.staticOnly == true)
        #expect(matrix.policy(for: .tombstoneConflict)?.staticOnly == true)
        #expect(matrix.policy(for: .audioUpload)?.staticOnly == true)
        #expect(matrix.policies.allSatisfy { $0.readPathLegacy })
        #expect(matrix.policies.allSatisfy { !$0.runtimeSwitchEnabled })
    }

    @Test func macPostconditionFailureRollsBackAndPreservesFallbackWithoutUiReadSwitch() async throws {
        let rootURL = MacLibraryMetadataCutoverTestSupport.makeScratchRoot("MacV831PostconditionRollback")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pair = MacLibraryMetadataCutoverTestSupport.folderCandidate()
        let bootstrap = try MacLibraryMetadataProductionCanaryBootstrap(
            configuration: Self.configuration()
        ).prepare(
            productionRootURL: rootURL,
            evidence: Self.productionEvidence()
        )
        let port = try #require(bootstrap.applyPort)
        try await port.setRootBoundLibraryMetadataPayload(candidate: pair.candidate, metadataBytes: pair.bytes)
        await port.injectRootBoundPostconditionFailure(objectID: pair.candidate.objectID)

        let result = await Self.run(
            configuration: bootstrap.configuration,
            evidence: bootstrap.evidence,
            candidates: [pair.candidate],
            executor: bootstrap.executor
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult?.legacyFallbackUsed == true)
        #expect(result.cutoverResult?.duplicateLegacySuppressedActionIDs.isEmpty == true)
        #expect(result.observationReport.legacyFallbackPreserved)
        #expect(result.observationReport.uiMutated == false)
        #expect(result.observationReport.resourceMoved == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataProductionRootLegacyFallbackUsed })
    }

    @Test func macRootContainmentAndCheckpointFailuresBlockBeforeWrite() {
        let candidate = MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate
        var testRootEvidence = Self.productionEvidence()
        testRootEvidence.applyPortMode = .testRootBound
        var noCheckpoint = Self.productionEvidence()
        noCheckpoint.rollbackCheckpointAvailable = false

        #expect(Self.gate(evidence: testRootEvidence, candidates: [candidate]).blockers.contains(.productionRootContainmentUnverified))
        #expect(Self.gate(evidence: noCheckpoint, candidates: [candidate]).blockers.contains(.rollbackEvidenceMissing))
    }

    private static func configuration() -> CanonicalLibraryMetadataProductionCanaryConfiguration {
        .explicitProductionRootN1Execute(allowProductionRootWrites: true)
    }

    private static func productionEvidence() -> CanonicalLibraryMetadataCutoverEvidence {
        var evidence = MacLibraryMetadataCutoverTestSupport.evidence()
        evidence.applyPortMode = .productionRootBound
        return evidence
    }

    private static func token(ownerApproved: Bool = true) -> CanonicalCutoverToken {
        CanonicalCutoverToken(
            tokenID: "mac-v831-library-metadata-production-root",
            syncRunID: "mac-v831-production-root-sync",
            ownerApproved: ownerApproved
        )
    }

    private static func gate(
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration? = nil,
        token: CanonicalCutoverToken? = nil,
        evidence: CanonicalLibraryMetadataCutoverEvidence? = nil,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813(),
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        executorAvailable: Bool = true
    ) -> CanonicalLibraryMetadataProductionRootGateResult {
        CanonicalLibraryMetadataProductionRootGate().evaluate(
            configuration: configuration ?? Self.configuration(),
            token: token ?? Self.token(),
            evidence: evidence ?? Self.productionEvidence(),
            matrix: matrix,
            candidates: candidates,
            trigger: .manual,
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executorAvailable: executorAvailable
        )
    }

    private static func run(
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        executor: (any CanonicalLibraryMetadataCutoverExecutor)?
    ) async -> CanonicalLibraryMetadataProductionCanaryInjectionResult {
        await CanonicalLibraryMetadataProductionCanaryInjection().evaluateOrRun(
            configuration: configuration,
            token: Self.token(),
            evidence: evidence,
            candidates: candidates,
            trigger: .manual,
            nodeRole: .mac,
            syncRunID: "v831-mac-production-root",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: executor
        )
    }

    private static func matrixReplacing(
        _ domain: CanonicalMigrationDomain,
        mutate: (inout CanonicalMigrationDomainPolicy) -> Void
    ) -> CanonicalMigrationDomainMatrix {
        var matrix = CanonicalMigrationDomainMatrix.defaultV813()
        matrix.policies = matrix.policies.map { existing in
            var copy = existing
            if copy.domain == domain {
                mutate(&copy)
            }
            return copy
        }
        return matrix
    }
}
