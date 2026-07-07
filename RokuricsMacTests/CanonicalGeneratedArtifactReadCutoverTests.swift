//
//  CanonicalGeneratedArtifactReadCutoverTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalGeneratedArtifactReadCutoverTests {
    @Test func macReadSourceDefaultsLegacyAndGuardedReadRequiresExplicitConfig() {
        let legacy = Self.snapshot(source: .legacy)
        let canonical = Self.snapshot(source: .canonical)

        let defaultRead = MacGeneratedArtifactReadSideSeam().readSource(
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            trigger: .periodic,
            syncRunID: "mac-ga-read-default"
        )
        #expect(defaultRead.returnedSource == .legacy)
        #expect(defaultRead.canonicalReadServed == false)
        #expect(defaultRead.inventoryResponseMutated == false)
        #expect(defaultRead.receiveJSONMutated == false)

        let blocked = MacGeneratedArtifactReadSideSeam().readSource(
            sourceConfiguration: CanonicalGeneratedArtifactReadSourceConfiguration(mode: .guardedCanonicalRead),
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            syncRunID: "mac-ga-read-missing-config"
        )
        #expect(blocked.returnedSource == .legacy)
        #expect(blocked.gateResult?.state == .blockedByDefaultConfig)
        #expect(blocked.fallback == .gateBlocked)
    }

    @Test func macExplicitGuardedReadServesCanonicalMetadataAvailabilityOnlyAndDoesNotMutateInventory() {
        let result = MacGeneratedArtifactReadSideSeam().readSource(
            sourceConfiguration: .explicitGuardedCanonicalRead(),
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            syncRunID: "mac-ga-read-guarded"
        )

        #expect(result.gateResult?.state == .allowed)
        #expect(result.canonicalReadServed)
        #expect(result.returnedSource == .canonical)
        #expect(result.readSource.snapshot.itemCount == 1)
        #expect(result.readSource.snapshot.contentIncludedCount == 0)
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
        #expect(result.inventoryResponseMutated == false)
        #expect(result.receiveJSONMutated == false)
        #expect(result.transcriptionOrNoteGenerationTriggered == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactGuardedCanonicalReadServed })
    }

    @Test func macGuardedReadFallsBackForEvidenceDivergenceCanonicalMissingAndReadException() {
        let legacy = Self.snapshot(source: .legacy)
        let canonical = Self.snapshot(source: .canonical)

        let missingEvidence = MacGeneratedArtifactReadSideSeam().readSource(
            sourceConfiguration: .explicitGuardedCanonicalRead(),
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            writeSideEvidence: .missing,
            trigger: .periodic,
            syncRunID: "mac-ga-read-missing-evidence"
        )
        #expect(missingEvidence.returnedSource == .legacy)
        #expect(missingEvidence.gateResult?.state == .blockedByWriteSideEvidence)

        let divergent = MacGeneratedArtifactReadSideSeam().readSource(
            sourceConfiguration: .explicitGuardedCanonicalRead(),
            legacySnapshot: legacy,
            canonicalSnapshot: Self.snapshot(source: .canonical, logicalToken: "notes/changed.md"),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            syncRunID: "mac-ga-read-divergent"
        )
        #expect(divergent.gateResult?.state == .blockedByDivergence)
        #expect(divergent.fallback == .divergenceDetected)

        let missingCanonical = MacGeneratedArtifactReadSideSeam().readSource(
            sourceConfiguration: .explicitGuardedCanonicalRead(),
            legacySnapshot: legacy,
            canonicalSnapshot: nil,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            syncRunID: "mac-ga-read-missing-canonical"
        )
        #expect(missingCanonical.returnedSource == .legacy)
        #expect(missingCanonical.fallback == .canonicalProjectionMissing)

        let failed = MacGeneratedArtifactReadSideSeam().readSource(
            sourceConfiguration: .explicitGuardedCanonicalRead(),
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            syncRunID: "mac-ga-read-exception",
            canonicalReadFailureReason: "canonicalReadException"
        )
        #expect(failed.returnedSource == .legacy)
        #expect(failed.fallback == .canonicalReadException)
        #expect(failed.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactGuardedCanonicalReadFallback })
    }

    @Test func macRetirementCandidateRemainsReportOnly() {
        let window = CanonicalGeneratedArtifactObservationWindow(
            policy: .explicitInternalTest(
                allowObservationCompletion: true,
                requireWriteSideEvidence: true,
                requireReadSideCanonicalServedEvidence: true
            )
        )
            .recordingWriteSide(Self.cleanWriteSideEvidence)
            .recording(CanonicalGeneratedArtifactObservationEvent(kind: .legacyFallbackObserved))
            .recording(CanonicalGeneratedArtifactObservationEvent(kind: .readSideEquivalent))
            .recording(CanonicalGeneratedArtifactObservationEvent(kind: .readSideCanonicalServed))
        let gate = CanonicalGeneratedArtifactObservationGate.evaluate(window: window)
        let report = CanonicalGeneratedArtifactRetirementCandidateGate.evaluate(
            writeSideCanarySuccessEvidence: true,
            readSideCanonicalReadEvidence: true,
            observationGate: gate,
            fallbackAvailable: true,
            manualAuditRequired: true
        )

        #expect(gate.observationComplete)
        #expect(report.ready)
        #expect(report.retirementExecutionPerformed == false)
        #expect(report.legacyDeleted == false)
        #expect(report.legacyDisabled == false)
        #expect(report.manualAuditRequired)
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

    private static func snapshot(
        source: CanonicalGeneratedArtifactReadProjectionSource,
        logicalToken: String = "notes/recording-1.md"
    ) -> CanonicalGeneratedArtifactReadSnapshot {
        let artifact = CanonicalProjectionContract.makeArtifact(
            objectID: "recording-1",
            kind: .noteMarkdown,
            availability: .available,
            contentHash: CanonicalHash("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"),
            byteSize: 64,
            logicalPathToken: logicalToken,
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1)),
            observedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2)),
            producedByNodeID: "mac-node",
            platform: "Mac"
        )
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
}
