//
//  CanonicalProductionSnapshotTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalProductionSnapshotTests {
    @Test func macSnapshotAdapterBuildsReadOnlyRuntimeNodeState() {
        let unsupported = CanonicalProductionUnsupportedFact(
            objectID: "legacy-folder-unsupported",
            domain: .inventory,
            reason: "legacyShapeUnsupported"
        )
        let legacy = CanonicalLegacyActionSnapshot(actionIDsByDomain: [
            .recordingMetadata: ["legacyWouldUploadMetadataButCanonicalNoOp:recording-01"]
        ])
        let snapshot = CanonicalProductionTestFixtures.snapshot(
            recordings: [CanonicalProductionTestFixtures.recording(audio: true)],
            legacyActions: legacy,
            unsupportedFacts: [unsupported]
        )

        #expect(snapshot.manifest.objects.count == 1)
        #expect(snapshot.runtimeNodeState.inventoryCoverage.recordingCoverage == 1)
        #expect(snapshot.runtimeNodeState.inventoryCoverage.audioCoverage == 1)
        #expect(snapshot.runtimeNodeState.transferProjection.jobs.isEmpty)
        #expect(snapshot.unsupportedFacts.contains(unsupported))
        #expect(snapshot.diagnostics.contains { $0.kind == .canonicalProductionSnapshotBuilt && $0.dryRun })
        #expect(snapshot.runtimeNodeState.retirementReadiness.status(for: .transport) == .blocked)
    }

    @Test func snapshotDiagnosticsUseHashPrefixAndDoNotExposeFullManifestHash() {
        let snapshot = CanonicalProductionTestFixtures.snapshot(recordings: [CanonicalProductionTestFixtures.recording(audio: true)])
        let event = snapshot.diagnostics.first { $0.kind == .canonicalProductionSnapshotBuilt }

        #expect(event?.hashPrefix?.count == 12)
        #expect(event?.hashPrefix != snapshot.manifest.manifestHash.value)
        #expect(event?.reason?.contains("/Users/") == false)
    }
}
