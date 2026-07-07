//
//  IPhoneLibraryMetadataReadSideSeam.swift
//  Rokurics
//
//  Created by Codex on 2026/6/5.
//

import Foundation

struct IPhoneLibraryMetadataReadSideSeam {
    var configuration: CanonicalLibraryMetadataReadSideCutoverConfiguration
    var matrix: CanonicalMigrationDomainMatrix

    init(
        configuration: CanonicalLibraryMetadataReadSideCutoverConfiguration = .disabled,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813()
    ) {
        self.configuration = configuration
        self.matrix = matrix
    }

    func evaluate(
        legacyManifest: StudyLibrarySyncManifest?,
        canonicalManifest: CanonicalManifest?,
        trigger: CanonicalSyncPlanTrigger,
        syncRunID: String?
    ) -> CanonicalLibraryMetadataReadSideCutoverResult {
        let legacySnapshot: CanonicalLibraryMetadataReadSnapshot
        if let legacyManifest {
            let objects = IPhoneCanonicalLibraryAdapter().makeLibraryObjects(from: legacyManifest)
            legacySnapshot = CanonicalLibraryMetadataReadProjection.build(
                source: .legacy,
                objects: objects,
                generatedAt: legacyManifest.generatedAt
            ).snapshot
        } else {
            legacySnapshot = CanonicalLibraryMetadataReadSnapshot(
                source: .legacy,
                failures: [
                    CanonicalLibraryMetadataReadProjectionFailure(
                        kind: .snapshotMissing,
                        reason: "legacyStudyManifestMissing"
                    )
                ]
            )
        }

        let canonicalSnapshot = CanonicalLibraryMetadataReadProjection.build(
            source: .canonical,
            manifest: canonicalManifest,
            generatedAt: canonicalManifest?.generatedAt.date ?? legacyManifest?.generatedAt ?? Date()
        ).snapshot

        return CanonicalLibraryMetadataReadSideCutoverEvaluator.evaluate(
            configuration: configuration,
            legacySnapshot: legacySnapshot,
            canonicalSnapshot: canonicalSnapshot,
            matrix: matrix,
            trigger: trigger,
            nodeRole: .iPhone,
            syncRunID: syncRunID
        )
    }

    func readSource(
        sourceConfiguration: CanonicalLibraryMetadataReadSourceConfiguration = .legacy,
        legacyManifest: StudyLibrarySyncManifest?,
        canonicalManifest: CanonicalManifest?,
        writeSideEvidence: CanonicalLibraryMetadataWriteSideEvidenceLinkage = .missing,
        legacyFallbackAvailable: Bool = true,
        trigger: CanonicalSyncPlanTrigger,
        syncRunID: String?,
        canonicalReadFailureReason: String? = nil,
        unresolvedConflictCount: Int = 0
    ) -> CanonicalLibraryMetadataReadSourceResult {
        let legacySnapshot = makeLegacySnapshot(from: legacyManifest)
        let canonicalSnapshot = CanonicalLibraryMetadataReadProjection.build(
            source: .canonical,
            manifest: canonicalManifest,
            generatedAt: canonicalManifest?.generatedAt.date ?? legacyManifest?.generatedAt ?? Date()
        ).snapshot
        return CanonicalLibraryMetadataReadSourceProvider(
            configuration: sourceConfiguration,
            matrix: matrix
        ).read(
            legacySnapshot: legacySnapshot,
            canonicalSnapshot: canonicalSnapshot,
            writeSideEvidence: writeSideEvidence,
            legacyFallbackAvailable: legacyFallbackAvailable,
            trigger: trigger,
            nodeRole: .iPhone,
            syncRunID: syncRunID,
            canonicalReadFailureReason: canonicalReadFailureReason,
            unresolvedConflictCount: unresolvedConflictCount
        )
    }

    func observeReadSource(
        _ result: CanonicalLibraryMetadataReadSourceResult,
        policy: CanonicalLibraryMetadataObservationPolicy = .disabled,
        observationWindowID: String = "iPhoneLibraryMetadataReadSourceObservation",
        trigger: CanonicalSyncPlanTrigger,
        syncRunID: String?
    ) -> CanonicalLibraryMetadataObservationWindow {
        CanonicalLibraryMetadataObservationWindow(
            observationWindowID: observationWindowID,
            policy: policy,
            matrix: matrix
        ).recordingReadSourceResult(
            result,
            trigger: trigger,
            nodeRole: .iPhone,
            syncRunID: syncRunID
        )
    }

    private func makeLegacySnapshot(
        from legacyManifest: StudyLibrarySyncManifest?
    ) -> CanonicalLibraryMetadataReadSnapshot {
        guard let legacyManifest else {
            return CanonicalLibraryMetadataReadSnapshot(
                source: .legacy,
                failures: [
                    CanonicalLibraryMetadataReadProjectionFailure(
                        kind: .snapshotMissing,
                        reason: "legacyStudyManifestMissing"
                    )
                ]
            )
        }
        let objects = IPhoneCanonicalLibraryAdapter().makeLibraryObjects(from: legacyManifest)
        return CanonicalLibraryMetadataReadProjection.build(
            source: .legacy,
            objects: objects,
            generatedAt: legacyManifest.generatedAt
        ).snapshot
    }
}
