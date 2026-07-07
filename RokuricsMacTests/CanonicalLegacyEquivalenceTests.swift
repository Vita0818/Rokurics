//
//  CanonicalLegacyEquivalenceTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalLegacyEquivalenceTests {
    @Test func missingProductionPortPreventsEquivalentStatus() {
        let report = CanonicalDryRunMigrationPlanner.equivalenceReport(
            syncPlan: CanonicalSyncPlan(),
            applyPlan: CanonicalApplyPlan(trigger: .manual),
            libraryPlan: CanonicalLibrarySyncPlan(),
            localLegacyActions: .empty,
            portReadiness: CanonicalProductionPortSet().readiness()
        )

        #expect(report.status(for: .recordingMetadata) == .blocked)
        #expect(report.status(for: .recordingAudio) == .blocked)
        #expect(report.hasBlockingDivergence)
        #expect(report.divergences.contains { $0.reason.contains("productionPortMissing") })
    }

    @Test func divergenceRedactsSensitivePathsAndOnlyKeepsHashPrefix() {
        let divergence = CanonicalLegacyDivergence(
            domain: .generatedArtifacts,
            status: .canonicalOnly,
            severity: .blocking,
            reason: "/Users/vita/private/full/path/transcript.md",
            canonicalActionIDs: ["/Users/vita/private/full/path/transcript.md"],
            legacyActionIDs: ["legacy"],
            hash: CanonicalHash(String(repeating: "f", count: 64))
        )

        #expect(divergence.reason.contains("/Users/") == false)
        #expect(divergence.canonicalActionIDs.first?.contains("/Users/") == false)
        #expect(divergence.hashPrefix == String(repeating: "f", count: 12))
        #expect(divergence.isBlocking)
    }

    @Test func equivalentReportSeparatesEquivalentAndDivergentDomains() {
        let reports = [
            CanonicalLegacyEquivalenceDomainReport(domain: .recordingMetadata, status: .equivalent),
            CanonicalLegacyEquivalenceDomainReport(
                domain: .recordingAudio,
                status: .canonicalMoreAggressive,
                canonicalActionIDs: ["recordingAudioUpload:recording-01"],
                divergences: [
                    CanonicalLegacyDivergence(
                        domain: .recordingAudio,
                        status: .canonicalMoreAggressive,
                        severity: .blocking,
                        reason: "canonicalWouldUploadWhereLegacyNoOp"
                    )
                ]
            )
        ]
        let dryRun = CanonicalDryRunEquivalenceReport(
            legacyEquivalence: CanonicalLegacyEquivalenceReport(domainReports: reports)
        )

        #expect(dryRun.equivalentDomains == [.recordingMetadata])
        #expect(dryRun.divergentDomains == [.recordingAudio])
        #expect(dryRun.legacyEquivalence.allEquivalent == false)
    }
}
