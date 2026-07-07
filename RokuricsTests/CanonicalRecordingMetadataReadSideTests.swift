//
//  CanonicalRecordingMetadataReadSideTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/12.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalRecordingMetadataReadSideTests {
    @Test func iPhoneReadSideDefaultsToLegacyAndDoesNotMutateOrUpload() {
        let result = IPhoneRecordingMetadataReadSideSeam().read(
            legacyManifest: Self.studyManifest(title: "Legacy Title"),
            canonicalManifest: Self.manifest(title: "Canonical Title"),
            syncRunID: "iphone-recording-read-default"
        )

        #expect(result.returnedSource == .legacy)
        #expect(result.canonicalCandidateBuilt == false)
        #expect(result.canonicalReadServed == false)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.uploadJobCreated == false)
        #expect(result.storeMutated == false)
        #expect(result.diagnostics.allSatisfy { $0.isRedacted })
    }

    @Test func iPhoneShadowComparesOnlyAndDecisionApplyNoAudioDoNotServeCanonical() {
        let shadowSwitch = CanonicalKernelSwitchConfiguration(
            mode: .canonicalShadow,
            policy: .debugInternal()
        ).resolve()
        let shadow = IPhoneRecordingMetadataReadSideSeam.fromCanonicalKernelSwitch(shadowSwitch).read(
            legacyManifest: Self.studyManifest(title: "Legacy Title"),
            canonicalManifest: Self.manifest(title: "Canonical Title"),
            syncRunID: "iphone-recording-read-shadow"
        )

        #expect(shadow.mode == .parallelCompare)
        #expect(shadow.returnedSource == .legacy)
        #expect(shadow.canonicalCandidateBuilt)
        #expect(shadow.canonicalReadServed == false)
        #expect(shadow.diff?.equivalent == false)

        for mode in [CanonicalKernelSwitchMode.canonicalDecisionOnly, .canonicalApplyNoAudio] {
            let switchResult = CanonicalKernelSwitchConfiguration(
                mode: mode,
                policy: .debugInternal()
            ).resolve()
            let result = IPhoneRecordingMetadataReadSideSeam.fromCanonicalKernelSwitch(switchResult).read(
                legacyManifest: Self.studyManifest(title: "Legacy Title"),
                canonicalManifest: Self.manifest(title: "Canonical Title"),
                syncRunID: "iphone-recording-read-\(mode.rawValue)"
            )
            #expect(result.returnedSource == .legacy)
            #expect(result.canonicalReadServed == false)
            #expect(result.syncOrUploadTriggered == false)
            #expect(result.storeMutated == false)
        }
    }

    @Test func iPhoneFullSyncServesCanonicalOnlyWhenEquivalentAndFallsBackOnDivergence() {
        let fullSync = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()
        let seam = IPhoneRecordingMetadataReadSideSeam.fromCanonicalKernelSwitch(fullSync)
        let equivalentLegacy = Self.studyManifest(title: "Shared Title")
        let equivalent = seam.read(
            legacyManifest: equivalentLegacy,
            canonicalManifest: IPhoneCanonicalReadRuntimeAdapter.makeCanonicalManifest(equivalentLegacy),
            syncRunID: "iphone-recording-read-full-equivalent"
        )
        let divergent = seam.read(
            legacyManifest: Self.studyManifest(title: "Legacy Title"),
            canonicalManifest: IPhoneCanonicalReadRuntimeAdapter.makeCanonicalManifest(Self.studyManifest(title: "Canonical Title")),
            syncRunID: "iphone-recording-read-full-divergent"
        )

        #expect(equivalent.returnedSource == .canonical)
        #expect(equivalent.canonicalReadServed)
        #expect(equivalent.fallback == .none)
        #expect(equivalent.legacyFallbackServed == false)
        #expect(equivalent.syncOrUploadTriggered == false)
        #expect(equivalent.storeMutated == false)
        #expect(divergent.returnedSource == .legacy)
        #expect(divergent.canonicalReadServed == false)
        #expect(divergent.fallback == .guardedGateBlocked)
        #expect(divergent.legacyFallbackServed)
        #expect(divergent.diff?.equivalent == false)
        #expect(divergent.syncOrUploadTriggered == false)
        #expect(divergent.storeMutated == false)
    }

    private static func manifest(title: String) -> CanonicalManifest {
        let metadata = Self.metadata(title: title)
        return CanonicalManifest.make(
            node: CanonicalNode(nodeID: "iphone-test", platform: "iPhone", capabilities: [.recordingMetadata]),
            generatedAt: Date(timeIntervalSince1970: 3_000),
            objects: [
                CanonicalRecordingObject(
                    objectID: metadata.objectID,
                    nodeID: "iphone-test",
                    metadata: metadata,
                    syncState: .synced,
                    transferState: .completed
                )
            ],
            manifestCapabilities: [.recordingMetadata]
        )
    }

    private static func metadata(title: String) -> CanonicalRecordingMetadata {
        CanonicalRecordingMetadata(
            objectID: "recording-01",
            title: title,
            createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1_000)),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2_000)),
            duration: 42,
            filing: CanonicalRecordingMetadata.Filing(type: "course", subject: "math"),
            tags: ["math"]
        )
    }

    private static func studyManifest(title: String) -> StudyLibrarySyncManifest {
        StudyLibrarySyncManifest.make(
            deviceID: "iphone-test",
            generatedAt: Date(timeIntervalSince1970: 3_000),
            items: [
                StudyItemMetadata(
                    kind: .recordingBundle,
                    title: title,
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    updatedAt: Date(timeIntervalSince1970: 2_000),
                    recordingID: "recording-01",
                    duration: 42,
                    audioRelativePath: "audio/recording-01.m4a",
                    transcriptionStatus: "completed",
                    noteStatus: "completed",
                    sourceDescription: "recordingMetadataReadSideTest",
                    modifiedByDeviceID: "iphone-test"
                )
            ],
            folders: [],
            recordings: [
                LocalNetworkSyncRecordingEntry(
                    recordingID: "recording-01",
                    metadataHash: String(Self.metadata(title: title).metadataHash.value.prefix(12)),
                    audioAvailable: false,
                    audioChecksum: nil,
                    audioSize: nil,
                    uploadLedgerState: nil,
                    receiveStatus: nil,
                    processingStatus: nil,
                    updatedAt: Date(timeIntervalSince1970: 2_000),
                    deleted: false,
                    title: title,
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    tombstone: false,
                    audioAvailability: .missing,
                    uploadStatus: nil,
                    transcriptionStatus: "completed",
                    noteStatus: "completed",
                    sourceDeviceID: "iphone-test",
                    artifactRefs: nil,
                    audioLogicalPathToken: nil
                )
            ]
        )
    }
}
