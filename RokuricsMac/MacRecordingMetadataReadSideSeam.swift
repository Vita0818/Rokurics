//
//  MacRecordingMetadataReadSideSeam.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/12.
//

import Foundation

struct MacRecordingMetadataReadSideSeam {
    var configuration: CanonicalReadRuntimeConfiguration

    nonisolated init(configuration: CanonicalReadRuntimeConfiguration = .disabled) {
        self.configuration = configuration
    }

    nonisolated static func fromCanonicalKernelSwitch(
        _ result: CanonicalKernelSwitchResult = CanonicalKernelSwitchConfiguration.runtimeConfigurationFromStoredDefaults().resolve()
    ) -> MacRecordingMetadataReadSideSeam {
        MacRecordingMetadataReadSideSeam(configuration: result.effectiveConfiguration.readRuntimeConfiguration)
    }

    nonisolated func evaluate(
        legacyManifest: StudyLibrarySyncManifest?,
        canonicalManifest: CanonicalManifest?,
        peerCanonicalManifest: CanonicalManifest? = nil,
        uploadCandidates: [CanonicalAudioUploadCutoverCandidate] = [],
        syncRuntimeResult: CanonicalSyncRuntimeResult? = nil,
        trigger: CanonicalSyncPlanTrigger = .manual,
        syncRunID: String? = nil,
        canonicalReadFailureReason: String? = nil
    ) -> CanonicalReadRuntimeResult {
        _ = trigger
        return read(
            legacyManifest: legacyManifest,
            canonicalManifest: canonicalManifest,
            peerCanonicalManifest: peerCanonicalManifest,
            uploadCandidates: uploadCandidates,
            syncRuntimeResult: syncRuntimeResult,
            syncRunID: syncRunID,
            canonicalReadFailureReason: canonicalReadFailureReason
        )
    }

    nonisolated func read(
        legacyManifest: StudyLibrarySyncManifest?,
        canonicalManifest: CanonicalManifest?,
        peerCanonicalManifest: CanonicalManifest? = nil,
        uploadCandidates: [CanonicalAudioUploadCutoverCandidate] = [],
        syncRuntimeResult: CanonicalSyncRuntimeResult? = nil,
        syncRunID: String? = nil,
        canonicalReadFailureReason: String? = nil
    ) -> CanonicalReadRuntimeResult {
        let legacyCanonicalManifest = legacyManifest.map(MacCanonicalReadRuntimeAdapter.makeCanonicalManifest)
        return read(
            legacyCanonicalManifest: legacyCanonicalManifest,
            canonicalManifest: canonicalManifest,
            peerCanonicalManifest: peerCanonicalManifest,
            uploadCandidates: uploadCandidates,
            syncRuntimeResult: syncRuntimeResult,
            syncRunID: syncRunID,
            canonicalReadFailureReason: canonicalReadFailureReason
        )
    }

    nonisolated func read(
        legacyCanonicalManifest: CanonicalManifest?,
        canonicalManifest: CanonicalManifest?,
        peerCanonicalManifest: CanonicalManifest? = nil,
        uploadCandidates: [CanonicalAudioUploadCutoverCandidate] = [],
        syncRuntimeResult: CanonicalSyncRuntimeResult? = nil,
        syncRunID: String? = nil,
        canonicalReadFailureReason: String? = nil
    ) -> CanonicalReadRuntimeResult {
        let legacySnapshot = CanonicalReadSnapshot.build(
            source: .legacy,
            manifest: legacyCanonicalManifest,
            peerManifest: nil,
            uploadCandidates: uploadCandidates,
            syncRuntimeResult: syncRuntimeResult,
            generatedAt: legacyCanonicalManifest?.generatedAt.date ?? Date()
        )
        let canonicalSnapshot = canonicalManifest.map { manifest in
            CanonicalReadSnapshot.build(
                source: .canonical,
                manifest: manifest,
                peerManifest: peerCanonicalManifest,
                uploadCandidates: uploadCandidates,
                syncRuntimeResult: syncRuntimeResult,
                generatedAt: manifest.generatedAt.date
            )
        }
        return CanonicalReadRuntimeProvider(configuration: configuration).read(
            legacySnapshot: legacySnapshot,
            canonicalSnapshot: canonicalSnapshot,
            syncRunID: syncRunID,
            canonicalReadFailureReason: canonicalReadFailureReason
        )
    }
}
