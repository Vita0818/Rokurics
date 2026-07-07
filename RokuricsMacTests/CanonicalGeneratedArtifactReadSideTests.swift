//
//  CanonicalGeneratedArtifactReadSideTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalGeneratedArtifactReadSideTests {
    @Test func macReadSideSeamDefaultsOffAndDoesNotMutate() {
        let result = MacGeneratedArtifactReadSideSeam().evaluate(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            trigger: .periodic,
            syncRunID: "mac-generated-artifact-disabled"
        )

        #expect(result.diffReport == nil)
        #expect(result.noMutationAsserted)
        #expect(result.artifactDownloaded == false)
        #expect(result.artifactApplied == false)
        #expect(result.inventoryResponseMutated == false)
    }

    @Test func macReadSideParallelEquivalentProducesDiagnosticsOnly() {
        let result = MacGeneratedArtifactReadSideSeam(
            configuration: .enabled()
        ).evaluate(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            trigger: .periodic,
            syncRunID: "mac-generated-artifact-enabled"
        )

        #expect(result.diffReport?.equivalent == true)
        #expect(result.noMutationAsserted)
        #expect(result.diagnostics.map(\.kind).contains(.canonicalGeneratedArtifactReadSideParallelEquivalent))
        #expect(result.diagnostics.map(\.kind).contains(.canonicalGeneratedArtifactReadSideContentExcluded))
    }

    @Test func unsupportedSummaryMarkdownBlocksGeneratedArtifactReadSideCandidate() {
        let legacy = CanonicalGeneratedArtifactReadProjection.snapshot(
            source: .legacy,
            facts: [],
            failures: [
                CanonicalGeneratedArtifactReadProjectionFailure(
                    kind: .unsupportedArtifactKind,
                    source: .legacy,
                    objectID: "recording-1",
                    artifactID: "summaryMarkdown:recording-1",
                    artifactKind: nil,
                    reason: "legacyArtifactKind=summaryMarkdown"
                )
            ]
        )
        let report = CanonicalGeneratedArtifactReadSideParallelDiff.compare(
            legacy: legacy,
            canonical: CanonicalGeneratedArtifactReadProjection.snapshot(source: .canonical, facts: [])
        )

        #expect(report.equivalent == false)
        #expect(report.hasFatalBlocker)
        #expect(report.blockers.contains(.unsupportedArtifactKind))
        #expect(report.divergences.map(\.kind).contains(.unsupportedArtifactKind))
    }

    private static func snapshot(
        source: CanonicalGeneratedArtifactReadProjectionSource
    ) -> CanonicalGeneratedArtifactReadSnapshot {
        let artifact = CanonicalProjectionContract.makeArtifact(
            objectID: "recording-1",
            kind: .noteMarkdown,
            availability: .available,
            contentHash: CanonicalHash("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"),
            byteSize: 64,
            logicalPathToken: "notes/recording-1.md",
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
                    producerSummary: artifact.producedBy?.rawValue
                )
            ]
        )
    }
}
