//
//  CanonicalGeneratedArtifactReadCutoverTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalGeneratedArtifactReadCutoverTests {
    @Test func readSourceDefaultsLegacyAndParallelCompareReturnsLegacy() {
        let legacy = Self.snapshot(source: .legacy)
        let canonical = Self.snapshot(source: .canonical)

        let defaultResult = CanonicalGeneratedArtifactReadSourceProvider().read(
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            writeSideEvidence: .missing,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-default"
        )
        #expect(defaultResult.mode == .legacy)
        #expect(defaultResult.returnedSource == .legacy)
        #expect(defaultResult.legacyReadReturned)
        #expect(defaultResult.canonicalReadServed == false)
        #expect(defaultResult.canonicalCandidateBuilt == false)
        #expect(defaultResult.fallback == .legacyDefault)

        let parallel = CanonicalGeneratedArtifactReadSourceProvider(
            configuration: CanonicalGeneratedArtifactReadSourceConfiguration(mode: .parallelCompare)
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-parallel"
        )
        #expect(parallel.returnedSource == .legacy)
        #expect(parallel.diffReport?.equivalent == true)
        #expect(parallel.canonicalCandidateBuilt)
        #expect(parallel.canonicalReadServed == false)
        #expect(parallel.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactReadOutputEquivalent })
    }

    @Test func canonicalCandidateBuildsButDoesNotServeUIByDefault() {
        let result = CanonicalGeneratedArtifactReadSourceProvider(
            configuration: CanonicalGeneratedArtifactReadSourceConfiguration(mode: .canonicalCandidate)
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-candidate"
        )

        #expect(result.canonicalCandidateBuilt)
        #expect(result.returnedSource == .legacy)
        #expect(result.canonicalReadServed == false)
        #expect(result.storeMutated == false)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.artifactDownloaded == false)
        #expect(result.artifactApplied == false)
        #expect(result.generatedArtifactFileWritten == false)
        #expect(result.uploadJobCreated == false)
    }

    @Test func guardedCanonicalReadBlocksWithoutConfigEvidenceOrCleanDiff() {
        let legacy = Self.snapshot(source: .legacy)
        let canonical = Self.snapshot(source: .canonical)

        let missingConfig = CanonicalGeneratedArtifactReadSourceProvider(
            configuration: CanonicalGeneratedArtifactReadSourceConfiguration(mode: .guardedCanonicalRead)
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-missing-config"
        )
        #expect(missingConfig.gateResult?.state == .blockedByDefaultConfig)
        #expect(missingConfig.fallback == .gateBlocked)
        #expect(missingConfig.returnedSource == .legacy)

        let missingEvidence = CanonicalGeneratedArtifactReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            writeSideEvidence: .missing,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-missing-evidence"
        )
        #expect(missingEvidence.gateResult?.state == .blockedByWriteSideEvidence)
        #expect(missingEvidence.fallback == .gateBlocked)

        let divergent = CanonicalGeneratedArtifactReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: Self.snapshot(source: .canonical, byteSize: 512),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-divergent"
        )
        #expect(divergent.gateResult?.state == .blockedByDivergence)
        #expect(divergent.fallback == .divergenceDetected)
        #expect(divergent.fatalForFutureStage)
        #expect(divergent.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactReadOutputDivergent })
    }

    @Test func gateBlocksUnsupportedUnsafeContentParentAudioFallbackAndOtherActiveDomain() {
        let legacy = Self.snapshot(source: .legacy)

        let unsupported = Self.failureSnapshot(source: .canonical, kind: .unsupportedArtifactKind)
        let unsupportedResult = Self.guarded(canonical: unsupported)
        #expect(unsupportedResult.gateResult?.state == .blockedByUnsupportedArtifact)
        #expect(unsupportedResult.fallback == .unsupportedArtifact)

        let unsafe = Self.failureSnapshot(source: .canonical, kind: .unsafePathToken, reason: "../unsafe/note.md")
        let unsafeResult = Self.guarded(canonical: unsafe)
        #expect(unsafeResult.gateResult?.state == .blockedByUnsafePath)
        #expect(unsafeResult.fallback == .unsafePathToken)
        #expect(unsafeResult.diagnostics.map(\.diagnosticsSummary).joined().contains("../") == false)

        let content = Self.failureSnapshot(source: .canonical, kind: .contentLeakRisk, reason: "full transcript excluded")
        let contentResult = Self.guarded(canonical: content)
        #expect(contentResult.gateResult?.state == .blockedByContentLeakRisk)
        #expect(contentResult.fallback == .contentLeakRisk)

        let parent = CanonicalGeneratedArtifactReadProjection.snapshot(
            source: .canonical,
            facts: [
                CanonicalGeneratedArtifactReadProjectionArtifactFact(
                    artifact: Self.artifact(),
                    parentTombstoned: true,
                    localAvailability: true,
                    peerAuthoritativeAvailability: true,
                    producerSummary: "transcription"
                )
            ]
        )
        let parentResult = Self.guarded(canonical: parent)
        #expect(parentResult.gateResult?.state == .blockedByParentTombstone)
        #expect(parentResult.fallback == .parentTombstone)

        let audio = CanonicalGeneratedArtifactReadProjection.snapshot(
            source: .canonical,
            facts: [
                CanonicalGeneratedArtifactReadProjectionArtifactFact(
                    artifact: Self.artifact(kind: .audio),
                    localAvailability: true
                )
            ]
        )
        let audioResult = Self.guarded(canonical: audio)
        #expect(audioResult.gateResult?.state == .blockedByAudioConfusion)
        #expect(audioResult.fallback == .audioConfusionRisk)

        let fallbackMissing = CanonicalGeneratedArtifactReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            legacyFallbackAvailable: false,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-fallback-missing"
        )
        #expect(fallbackMissing.gateResult?.state == .blockedByFallbackMissing)

        let otherDomain = CanonicalGeneratedArtifactReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead(),
            matrix: Self.matrixWithOtherActivePilot
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-other-domain"
        )
        #expect(otherDomain.gateResult?.state == .blockedByOtherActiveDomain)
    }

    @Test func guardedCanonicalReadServesCanonicalMetadataAvailabilityOnlyWhenAllEvidencePasses() {
        let result = CanonicalGeneratedArtifactReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-allowed"
        )

        #expect(result.gateResult?.state == .allowed)
        #expect(result.canonicalReadServed)
        #expect(result.returnedSource == .canonical)
        #expect(result.fallback == .none)
        #expect(result.fallbackCount == 0)
        #expect(result.readSource.metadataAvailabilityOnly)
        #expect(result.readSource.coversTranscriptArtifactMetadata)
        #expect(result.readSource.coversNoteArtifactMetadata)
        #expect(result.readSource.coversSummaryArtifactMetadata)
        #expect(result.readSource.excludesFullTranscriptContent)
        #expect(result.readSource.excludesFullNoteContent)
        #expect(result.readSource.excludesFullSummaryContent)
        #expect(result.readSource.excludesProviderResponse)
        #expect(result.readSource.excludesAudioBytes)
        #expect(result.storeMutated == false)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.artifactDownloaded == false)
        #expect(result.artifactApplied == false)
        #expect(result.generatedArtifactFileWritten == false)
        #expect(result.uploadJobCreated == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactGuardedCanonicalReadServed })
    }

    @Test func guardedReadFallsBackWhenCanonicalMissingOrReadFails() {
        let missing = CanonicalGeneratedArtifactReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: nil,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-canonical-missing"
        )
        #expect(missing.returnedSource == .legacy)
        #expect(missing.fallback == .canonicalProjectionMissing)

        let failed = CanonicalGeneratedArtifactReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-exception",
            canonicalReadFailureReason: "canonicalReadException"
        )
        #expect(failed.returnedSource == .legacy)
        #expect(failed.fallback == .canonicalReadException)
        #expect(failed.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactGuardedCanonicalReadFallback })
    }

    @Test func observationWindowAndRetirementCandidateRemainReportOnly() {
        let readResult = CanonicalGeneratedArtifactReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-observation"
        )
        let window = CanonicalGeneratedArtifactObservationWindow(
            policy: .explicitInternalTest(
                allowObservationCompletion: true,
                requireWriteSideEvidence: true,
                requireReadSideCanonicalServedEvidence: true
            )
        )
            .recordingWriteSide(Self.cleanWriteSideEvidence)
            .recording(CanonicalGeneratedArtifactObservationEvent(kind: .legacyFallbackObserved))
            .recordingReadSource(readResult)
        let gate = CanonicalGeneratedArtifactObservationGate.evaluate(window: window)
        #expect(gate.observationComplete)
        #expect(window.summary.writeSideCanonicalCommitCount == 1)
        #expect(window.summary.readSideCanonicalServedCount == 1)

        let retirement = CanonicalGeneratedArtifactRetirementCandidateGate.evaluate(
            writeSideCanarySuccessEvidence: true,
            readSideCanonicalReadEvidence: true,
            observationGate: gate,
            fallbackAvailable: true,
            manualAuditRequired: true,
            diffReport: readResult.diffReport
        )
        #expect(retirement.status == .ready)
        #expect(retirement.ready)
        #expect(retirement.retirementExecutionPerformed == false)
        #expect(retirement.legacyDeleted == false)
        #expect(retirement.legacyDisabled == false)
        #expect(retirement.manualAuditRequired)
    }

    @Test func iPhoneSeamDefaultLegacyAndExplicitGuardedReadReturnsCanonicalOutput() {
        let defaultRead = IPhoneGeneratedArtifactReadSideSeam().readSource(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            trigger: .periodic,
            syncRunID: "ga-iphone-default"
        )
        #expect(defaultRead.returnedSource == .legacy)
        #expect(defaultRead.canonicalReadServed == false)

        let guarded = IPhoneGeneratedArtifactReadSideSeam().readSource(
            sourceConfiguration: .explicitGuardedCanonicalRead(),
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            syncRunID: "ga-iphone-guarded"
        )
        #expect(guarded.returnedSource == .canonical)
        #expect(guarded.canonicalReadServed)
        #expect(guarded.readSource.snapshot.contentIncludedCount == 0)
        #expect(guarded.readSource.excludesFullTranscriptContent)
        #expect(guarded.artifactDownloaded == false)
        #expect(guarded.artifactApplied == false)
        #expect(guarded.generatedArtifactFileWritten == false)
        #expect(guarded.uploadJobCreated == false)
    }

    private static func guarded(
        canonical: CanonicalGeneratedArtifactReadSnapshot
    ) -> CanonicalGeneratedArtifactReadSourceResult {
        CanonicalGeneratedArtifactReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: canonical,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "ga-read-blocker"
        )
    }

    private static var cleanWriteSideEvidence: CanonicalGeneratedArtifactWriteSideEvidenceLinkage {
        CanonicalGeneratedArtifactWriteSideEvidenceLinkage(
            canaryStageStatus: .passed,
            latestSuccessfulStage: .allEligible,
            successfulCommitCount: 3,
            rollbackFailureCount: 0,
            legacyFallbackCount: 1,
            duplicateSuppressionCount: 3,
            unresolvedConflictCount: 0,
            unsupportedArtifactCount: 0,
            contentLeakRiskCount: 0,
            unsafePathTokenCount: 0,
            parentTombstoneBlockCount: 0,
            audioConfusionRiskCount: 0,
            readSideDivergenceCount: 0,
            writeSideDomainCutoverComplete: true
        )
    }

    private static var matrixWithOtherActivePilot: CanonicalMigrationDomainMatrix {
        var policies = CanonicalMigrationDomainMatrix.v824GeneratedArtifactsStagedCanary(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        ).policies
        policies.append(
            CanonicalMigrationDomainPolicy(
                domain: .audioUpload,
                activePilot: true,
                activePilotExplicit: true,
                staticOnly: false,
                blockedForRealMigration: false
            )
        )
        return CanonicalMigrationDomainMatrix(
            policies: policies,
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        )
    }

    private static func snapshot(
        source: CanonicalGeneratedArtifactReadProjectionSource,
        byteSize: Int64 = 128
    ) -> CanonicalGeneratedArtifactReadSnapshot {
        let artifact = Self.artifact(byteSize: byteSize)
        return CanonicalGeneratedArtifactReadProjection.snapshot(
            source: source,
            facts: [
                CanonicalGeneratedArtifactReadProjectionArtifactFact(
                    artifact: artifact,
                    localAvailability: true,
                    peerAuthoritativeAvailability: true,
                    producerSummary: artifact.producedBy?.rawValue
                )
            ]
        )
    }

    private static func failureSnapshot(
        source: CanonicalGeneratedArtifactReadProjectionSource,
        kind: CanonicalGeneratedArtifactReadProjectionFailureKind,
        reason: String = "blocked"
    ) -> CanonicalGeneratedArtifactReadSnapshot {
        CanonicalGeneratedArtifactReadProjection.snapshot(
            source: source,
            facts: [],
            failures: [
                CanonicalGeneratedArtifactReadProjectionFailure(
                    kind: kind,
                    source: source,
                    objectID: "recording-1",
                    artifactID: "transcriptJSON:recording-1",
                    artifactKind: .transcriptJSON,
                    reason: reason
                )
            ]
        )
    }

    private static func artifact(
        kind: CanonicalArtifact.Kind = .transcriptJSON,
        byteSize: Int64 = 128
    ) -> CanonicalArtifact {
        CanonicalProjectionContract.makeArtifact(
            objectID: "recording-1",
            kind: kind,
            availability: .available,
            contentHash: CanonicalHash("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"),
            byteSize: byteSize,
            logicalPathToken: "transcripts/recording-1.json",
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1)),
            observedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2)),
            producedByNodeID: "mac-node",
            platform: "Mac"
        )
    }
}
