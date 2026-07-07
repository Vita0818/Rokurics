//
//  CanonicalGeneratedArtifactReadSideTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalGeneratedArtifactReadSideTests {
    @Test func readProjectionExcludesContentAndFlagsUnsafePathToken() {
        let artifact = Self.artifact(logicalPathToken: "../unsafe/transcript.json")
        let snapshot = CanonicalGeneratedArtifactReadProjection.snapshot(
            source: .canonical,
            facts: [
                CanonicalGeneratedArtifactReadProjectionArtifactFact(
                    artifact: artifact,
                    localAvailability: true,
                    producerSummary: "transcription",
                    unsafePathTokenObserved: true
                )
            ]
        )

        #expect(snapshot.itemCount == 1)
        #expect(snapshot.contentIncludedCount == 0)
        #expect(snapshot.contentExcludedCount == 1)
        #expect(snapshot.items.first?.logicalTokenSummary == nil)
        #expect(snapshot.failures.map(\.kind).contains(.unsafePathToken))
        #expect(snapshot.diagnosticsSummary.contains("../") == false)
    }

    @Test func equivalentDiffIsCleanAndAudioConfusionIsFatal() {
        let legacy = Self.snapshot(source: .legacy)
        let canonical = Self.snapshot(source: .canonical)
        let clean = CanonicalGeneratedArtifactReadSideParallelDiff.compare(
            legacy: legacy,
            canonical: canonical
        )

        #expect(clean.equivalent)
        #expect(clean.divergenceCount == 0)

        let audio = CanonicalGeneratedArtifactReadProjection.snapshot(
            source: .legacy,
            facts: [
                CanonicalGeneratedArtifactReadProjectionArtifactFact(
                    artifact: Self.artifact(kind: .audio),
                    localAvailability: true
                )
            ]
        )
        let blocked = CanonicalGeneratedArtifactReadSideParallelDiff.compare(
            legacy: audio,
            canonical: CanonicalGeneratedArtifactReadProjection.snapshot(source: .canonical, facts: [])
        )

        #expect(blocked.equivalent == false)
        #expect(blocked.hasFatalBlocker)
        #expect(blocked.blockers.contains(.audioConfusionRisk))
        #expect(blocked.divergences.map(\.kind).contains(.audioConfusionRisk))
    }

    @Test func observationAndRetirementAreReportOnlyByDefault() {
        let window = CanonicalGeneratedArtifactObservationWindow()
            .recording(CanonicalGeneratedArtifactObservationEvent(kind: .readSideEquivalent))
        let observationGate = CanonicalGeneratedArtifactObservationGate.evaluate(window: window)
        let retirement = CanonicalGeneratedArtifactRetirementCandidateGate.evaluate(
            observationGate: observationGate
        )

        #expect(observationGate.status == .disabled)
        #expect(observationGate.observationComplete == false)
        #expect(retirement.ready == false)
        #expect(retirement.retirementExecutionPerformed == false)
        #expect(retirement.legacyDeleted == false)
        #expect(retirement.legacyDisabled == false)
        #expect(retirement.manualAuditRequired)
    }

    @Test func templateReportAndMatrixRequireLibraryMetadataObservationBeforeNextPilotCandidate() {
        let template = CanonicalGeneratedArtifactTemplateReport.currentV821Audit()
        let blocked = CanonicalMigrationDomainMatrix.v821GeneratedArtifactsNextPilotCandidate(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: false,
            templateReport: template
        ).validate()
        let allowed = CanonicalMigrationDomainMatrix.v821GeneratedArtifactsNextPilotCandidate(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
            templateReport: template
        ).validate()

        #expect(template.readiness == .readyForNextPilotN0)
        #expect(blocked.blockers.contains(.generatedArtifactsNextPilotBeforeLibraryMetadataObservation))
        #expect(allowed.blockers.contains(.generatedArtifactsNextPilotBeforeLibraryMetadataObservation) == false)
        #expect(allowed.activePilotDomain == .libraryMetadata)
        #expect(CanonicalMigrationGlobalConfigValidator().validate(
            CanonicalMigrationDomainMatrix.v821GeneratedArtifactsNextPilotCandidate(
                libraryMetadataObservationCompleteOrRetirementCandidateReady: true
            )
        ).violations.isEmpty)
    }

    @Test func iPhoneReadSideSeamDefaultsOffAndDoesNotMutate() {
        let result = IPhoneGeneratedArtifactReadSideSeam().evaluate(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            trigger: .periodic,
            syncRunID: "generated-artifact-read-disabled"
        )

        #expect(result.diffReport == nil)
        #expect(result.noMutationAsserted)
        #expect(result.storeMutated == false)
        #expect(result.uiMutated == false)
        #expect(result.artifactDownloaded == false)
        #expect(result.artifactApplied == false)
        #expect(result.uploadJobCreated == false)
        #expect(result.receiveJSONMutated == false)
        #expect(result.transcriptionOrNoteGenerationTriggered == false)
    }

    @Test func iPhoneEnabledReadSideParallelProducesDiagnosticsWithoutSideEffects() {
        let result = IPhoneGeneratedArtifactReadSideSeam(
            configuration: .enabled()
        ).evaluate(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            trigger: .periodic,
            syncRunID: "generated-artifact-read-enabled"
        )

        #expect(result.diffReport?.equivalent == true)
        #expect(result.noMutationAsserted)
        #expect(result.diagnostics.map(\.kind).contains(.canonicalGeneratedArtifactReadSideParallelEquivalent))
        #expect(result.diagnostics.map(\.kind).contains(.canonicalGeneratedArtifactReadSideNoMutationAsserted))
    }

    private static func snapshot(
        source: CanonicalGeneratedArtifactReadProjectionSource
    ) -> CanonicalGeneratedArtifactReadSnapshot {
        let artifact = Self.artifact()
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

    private static func artifact(
        kind: CanonicalArtifact.Kind = .transcriptJSON,
        logicalPathToken: String = "transcripts/recording-1.json"
    ) -> CanonicalArtifact {
        CanonicalProjectionContract.makeArtifact(
            objectID: "recording-1",
            kind: kind,
            availability: .available,
            contentHash: CanonicalHash("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"),
            byteSize: 128,
            logicalPathToken: logicalPathToken,
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1)),
            observedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2)),
            producedByNodeID: "mac-node",
            platform: "Mac"
        )
    }
}
