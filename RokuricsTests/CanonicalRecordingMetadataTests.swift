//
//  CanonicalRecordingMetadataTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalRecordingMetadataTests {
    @Test func businessMetadataHashContractExcludesNonBusinessState() {
        let base = Self.metadata(title: "Lecture")
        let changedReadFacts = Self.metadata(title: "Lecture", createdAt: 1_111, modifiedAt: 9_999, duration: 900)
        let titleChanged = Self.metadata(title: "Renamed Lecture")
        let withAudio = Self.object(
            metadata: base,
            artifacts: [Self.audioArtifact(hash: "a"), Self.noteArtifact(hash: "b")],
            receivedAt: 7_000,
            observedAt: 8_000
        )
        let withDifferentAudioAndGeneratedContent = Self.object(
            metadata: base,
            artifacts: [Self.audioArtifact(hash: "c"), Self.noteArtifact(hash: "d")],
            receivedAt: 9_000,
            observedAt: 10_000
        )

        #expect(CanonicalRecordingMetadataHashSchema.version == "canonical-recording-business-metadata-v1")
        #expect(CanonicalRecordingMetadataHashSchema.v1.excludedFields.contains("uploadProgress"))
        #expect(CanonicalRecordingMetadataHashSchema.v1.excludedFields.contains("receivedAt"))
        #expect(CanonicalRecordingMetadataHashSchema.v1.excludedFields.contains("observedAt"))
        #expect(CanonicalRecordingMetadataHashSchema.v1.excludedFields.contains("localPath"))
        #expect(CanonicalRecordingMetadataHashSchema.v1.excludedFields.contains("noteContent"))
        #expect(CanonicalRecordingMetadataBusinessFields(metadata: base).metadataHash == base.metadataHash)
        #expect(base.metadataHash == changedReadFacts.metadataHash)
        #expect(base.metadataHash != titleChanged.metadataHash)
        #expect(withAudio.metadataHash == withDifferentAudioAndGeneratedContent.metadataHash)
    }

    @Test func iPhoneAdapterStableHashIgnoresUploadProgressAndPaths() {
        let adapter = IPhoneCanonicalRecordingAdapter()
        let base = Self.legacyRecording(title: "Adapter Lecture")
        let changedUploadAndPaths = Self.legacyRecording(
            title: "Adapter Lecture",
            relativeAudioPath: "different/audio.m4a",
            relativeMetadataPath: "different/metadata.json",
            uploadStatus: "uploading",
            uploadProgressFraction: 0.75,
            uploadProgressConfirmedBytes: 75,
            uploadProgressTotalBytes: 100
        )
        let renamed = Self.legacyRecording(title: "Adapter Renamed")

        #expect(adapter.makeObject(metadata: base).metadataHash == adapter.makeObject(metadata: changedUploadAndPaths).metadataHash)
        #expect(adapter.makeObject(metadata: base).metadataHash != adapter.makeObject(metadata: renamed).metadataHash)
    }

    @Test func modifiedAtPolicyUsesBusinessClockAndDefersEqualTimestampTie() {
        let policy = CanonicalRecordingMetadataModifiedAtPolicy.current
        let localNewer = policy.decide(.init(
            local: Self.metadata(title: "Local", modifiedAt: 3_000),
            peer: Self.metadata(title: "Peer", modifiedAt: 2_000)
        ))
        let peerNewer = policy.decide(.init(
            local: Self.metadata(title: "Local", modifiedAt: 2_000),
            peer: Self.metadata(title: "Peer", modifiedAt: 3_000)
        ))
        let tieA = policy.decide(.init(
            local: Self.metadata(title: "A", modifiedAt: 2_000),
            peer: Self.metadata(title: "B", modifiedAt: 2_000)
        ))
        let tieB = policy.decide(.init(
            local: Self.metadata(title: "A", modifiedAt: 2_000),
            peer: Self.metadata(title: "B", modifiedAt: 2_000)
        ))
        let missingModifiedAt = policy.decide(.init(
            local: Self.metadata(title: "A"),
            peer: Self.metadata(title: "B"),
            businessModifiedAtAvailable: false
        ))

        #expect(localNewer.action == .sendLocal)
        #expect(localNewer.lwwApplied)
        #expect(peerNewer.action == .applyPeer)
        #expect(peerNewer.lwwApplied)
        #expect(tieA.action == .deferTie)
        #expect(tieA == tieB)
        #expect(missingModifiedAt.action == .legacyFallback)
        #expect(missingModifiedAt.reason == "businessModifiedAtUnavailable")
    }

    @Test func recordingMetadataDecisionModesFollowMasterSwitch() {
        let old = CanonicalKernelSwitchConfiguration.oldKernel.resolve()
        #expect(old.effectiveConfiguration.syncRuntimeConfiguration.mode == .disabled)
        #expect(old.effectiveConfiguration.applyRuntimeConfiguration.mode == .disabled)
        #expect(old.effectiveConfiguration.readRuntimeConfiguration.mode == .disabled)

        let decisionOnly = CanonicalKernelSwitchConfiguration(
            mode: .canonicalDecisionOnly,
            policy: .debugInternal()
        ).resolve()
        #expect(decisionOnly.effectiveConfiguration.syncRuntimeConfiguration.mode == .canonicalPlanPrimaryWithLegacyFallback)
        #expect(decisionOnly.effectiveConfiguration.applyRuntimeConfiguration.mode == .disabled)
        #expect(decisionOnly.effectiveConfiguration.readRuntimeConfiguration.mode == .disabled)

        let applyNoAudio = CanonicalKernelSwitchConfiguration(
            mode: .canonicalApplyNoAudio,
            policy: .debugInternal()
        ).resolve()
        #expect(applyNoAudio.effectiveConfiguration.syncRuntimeConfiguration.mode == .canonicalPlanPrimaryWithLegacyFallback)
        #expect(applyNoAudio.effectiveConfiguration.applyRuntimeConfiguration.mode == .productionRootApplyWithLegacyFallback)
        #expect(applyNoAudio.effectiveConfiguration.applyRuntimeConfiguration.policy.enabledDomains.contains(.recordingMetadata))
        #expect(applyNoAudio.effectiveConfiguration.audioUploadRuntimeConfiguration.mode == .disabled)

        let fullSync = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()
        #expect(fullSync.effectiveConfiguration.syncRuntimeConfiguration.mode == .canonicalPlanPrimaryWithLegacyFallback)
        #expect(fullSync.effectiveConfiguration.applyRuntimeConfiguration.policy.enabledDomains.contains(.recordingMetadata))
        #expect(fullSync.effectiveConfiguration.readRuntimeConfiguration.mode == .guardedCanonicalReadWithLegacyFallback)
    }

    @Test func recordingMetadataRuntimeDiagnosticsUseDomainSpecificNamesAndStayRedacted() {
        let result = CanonicalSyncRuntimeResult.make(
            mode: .canonicalPlanPrimaryWithLegacyFallback,
            gateResult: CanonicalSyncPlanAuthorityGateResult(state: .allowed, blockers: [], mode: .canonicalPlanPrimaryWithLegacyFallback),
            syncRunID: "recording-metadata-diagnostics",
            extraDiagnostics: [
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalSyncRuntimeMetadataHashEqual,
                    syncRunID: "recording-metadata-diagnostics",
                    mode: .canonicalPlanPrimaryWithLegacyFallback,
                    objectID: "recording-01",
                    actionKind: "recordingMetadata",
                    hash: CanonicalHash(String(repeating: "a", count: 64)),
                    detail: "legacyHashMismatch"
                ),
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalSyncRuntimeModifiedAtLWWApplied,
                    syncRunID: "recording-metadata-diagnostics",
                    mode: .canonicalPlanPrimaryWithLegacyFallback,
                    objectID: "recording-01",
                    actionKind: "recordingMetadata",
                    hash: CanonicalHash(String(repeating: "b", count: 64)),
                    detail: "businessModifiedAt"
                )
            ]
        )
        let diagnostics = result.diagnostics

        #expect(diagnostics.contains { $0.kind == .canonicalRecordingMetadataDecisionEvaluated })
        #expect(diagnostics.contains { $0.kind == .canonicalRecordingMetadataDecisionUsed })
        #expect(diagnostics.contains { $0.kind == .canonicalRecordingMetadataHashEqual })
        #expect(diagnostics.contains { $0.kind == .canonicalRecordingMetadataLWWApplied })
        #expect(diagnostics.contains { $0.kind == .canonicalRecordingMetadataHashChanged })
        #expect(diagnostics.allSatisfy { $0.isRedacted })
        #expect(diagnostics.map { $0.summary() }.joined().contains(String(repeating: "a", count: 64)) == false)
    }

    @Test func recordingMetadataReadDiagnosticsUseDomainSpecificNames() {
        let snapshot = CanonicalReadSnapshot.build(
            source: .legacy,
            manifest: Self.manifest(title: "Read Lecture"),
            generatedAt: Date(timeIntervalSince1970: 3_000)
        )
        let canonical = CanonicalReadSnapshot.build(
            source: .canonical,
            manifest: Self.manifest(title: "Read Lecture"),
            generatedAt: Date(timeIntervalSince1970: 3_000)
        )
        let result = CanonicalReadRuntimeProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(legacySnapshot: snapshot, canonicalSnapshot: canonical, syncRunID: "read-recording-metadata")

        #expect(result.returnedSource == .canonical)
        #expect(result.diagnostics.contains { $0.kind == .canonicalRecordingMetadataReadModeEvaluated })
        #expect(result.diagnostics.contains { $0.kind == .canonicalRecordingMetadataReadServedCanonical })
        #expect(result.diagnostics.contains { $0.kind == .canonicalRecordingMetadataReadDiffEquivalent })
        #expect(result.diagnostics.allSatisfy { $0.isRedacted })
    }

    @MainActor
    @Test func iPhoneStoreCanonicalReadOverlayUpdatesExistingRecordingMetadataWithoutMutation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalRecordingMetadataStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root)
        try await store.applySyncManifest(Self.studyManifest(title: "Legacy Title"), localDeviceID: "iphone-local")
        let canonical = IPhoneCanonicalReadRuntimeAdapter.makeCanonicalManifest(Self.studyManifest(title: "Canonical Title"))
        let result = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(allowDivergentGuardedReadForTests: true),
            canonicalManifest: canonical,
            syncRunID: "iphone-recording-metadata-read"
        )

        #expect(result.returnedSource == .canonical)
        #expect(store.effectiveStudyItems.first?.title == "Canonical Title")
        #expect(store.allStudyItems.first?.title == "Legacy Title")
        #expect(result.storeMutated == false)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.uploadJobCreated == false)
    }

    @Test func recordingMetadataScorecardIsCodeCompleteButNeedsDeviceEvidence() {
        let scorecard = CanonicalRecordingMetadataDomainReadinessScorecard.v851P2_1()

        #expect(scorecard.domain == .recordingMetadata)
        #expect(scorecard.writeExecutorReady)
        #expect(scorecard.decisionRuntimeReady)
        #expect(scorecard.applyRuntimeReady)
        #expect(scorecard.readRuntimeReady)
        #expect(scorecard.legacyFallbackReady)
        #expect(scorecard.switchBackProofReady)
        #expect(scorecard.diagnosticsRedacted)
        #expect(scorecard.codeComplete)
        #expect(scorecard.realDeviceEvidencePresent == false)
        #expect(scorecard.readyForManualSwitchTrial == false)
        #expect(scorecard.readyToRetireLegacyReportOnly == false)
        #expect(scorecard.blockers == [.realDeviceEvidenceMissing])
    }

    @Test func recordingMetadataSwitchBackAndCrashHarnessRemainLegacyReadable() throws {
        var harness = CanonicalLegacySwitchBackHarness(seedLegacyRecords: false)
        let legacyWrite = harness.legacyWrite(domain: .recordingMetadata, value: "legacy-recording-metadata")
        let canonicalRead = try #require(harness.canonicalRead(domain: .recordingMetadata))
        #expect(canonicalRead.value == legacyWrite.value)

        let canonicalWrite = harness.canonicalWrite(domain: .recordingMetadata, value: "canonical-recording-metadata")
        let legacyRead = try #require(harness.legacyRead(domain: .recordingMetadata))
        #expect(legacyRead.value == canonicalWrite.value)

        harness.switchMode(.oldKernel)
        _ = harness.legacyWrite(domain: .recordingMetadata, value: "legacy-modified-recording-metadata")
        harness.switchMode(.canonicalFullSync)
        let canonicalAgain = try #require(harness.canonicalRead(domain: .recordingMetadata))
        #expect(canonicalAgain.value == "legacy-modified-recording-metadata")

        for crashPoint in CanonicalLegacyCrashPoint.allCases {
            var crashHarness = CanonicalLegacySwitchBackHarness()
            let oldKernelRestart = crashHarness.simulateCrashAndRestart(
                domain: .recordingMetadata,
                crashPoint: crashPoint,
                restartMode: .oldKernel
            )
            #expect(oldKernelRestart.oldKernelCanRead)
            #expect(oldKernelRestart.canonicalFullSyncCanRead)
            #expect(oldKernelRestart.physicalDeleteCount == 0)

            var canonicalRestartHarness = CanonicalLegacySwitchBackHarness()
            let canonicalRestart = canonicalRestartHarness.simulateCrashAndRestart(
                domain: .recordingMetadata,
                crashPoint: crashPoint,
                restartMode: .canonicalFullSync
            )
            #expect(canonicalRestart.oldKernelCanRead)
            #expect(canonicalRestart.canonicalFullSyncCanRead)
            #expect(canonicalRestart.physicalDeleteCount == 0)
        }
    }

    private static func metadata(
        title: String,
        createdAt: TimeInterval = 1_000,
        modifiedAt: TimeInterval = 2_000,
        duration: TimeInterval = 42
    ) -> CanonicalRecordingMetadata {
        CanonicalRecordingMetadata(
            objectID: "recording-01",
            title: title,
            createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: createdAt)),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: modifiedAt)),
            duration: duration,
            filing: CanonicalRecordingMetadata.Filing(type: "course", subject: "math"),
            tags: ["math"]
        )
    }

    private static func object(
        metadata: CanonicalRecordingMetadata,
        artifacts: [CanonicalArtifact],
        receivedAt: TimeInterval,
        observedAt: TimeInterval
    ) -> CanonicalRecordingObject {
        CanonicalRecordingObject(
            objectID: metadata.objectID,
            nodeID: "iphone-test",
            metadata: metadata,
            artifacts: artifacts,
            syncState: .synced,
            transferState: .completed,
            processingState: CanonicalProcessingState(transcription: .completed, note: .completed),
            receivedAt: CanonicalTimestamp(Date(timeIntervalSince1970: receivedAt)),
            observedAt: CanonicalTimestamp(Date(timeIntervalSince1970: observedAt))
        )
    }

    private static func audioArtifact(hash: Character) -> CanonicalArtifact {
        CanonicalArtifact(
            artifactID: "audio-recording-01-\(hash)",
            objectID: "recording-01",
            kind: .audio,
            availability: .available,
            contentHash: CanonicalHash(String(repeating: String(hash), count: 64)),
            byteSize: 42,
            logicalName: "audio.m4a",
            logicalPathToken: "audio/recording-01.m4a",
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2_100)),
            producedBy: .audioCapture,
            producedByNodeID: "iphone-test"
        )
    }

    private static func noteArtifact(hash: Character) -> CanonicalArtifact {
        CanonicalArtifact(
            artifactID: "note-recording-01-\(hash)",
            objectID: "recording-01",
            kind: .noteJSON,
            availability: .available,
            contentHash: CanonicalHash(String(repeating: String(hash), count: 64)),
            byteSize: 8,
            logicalName: "note.json",
            logicalPathToken: "generated/recording-01/note.json",
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2_200)),
            producedBy: .noteGeneration,
            producedByNodeID: "mac-test"
        )
    }

    private static func manifest(title: String) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(nodeID: "iphone-test", platform: "iPhone", capabilities: [.recordingMetadata]),
            generatedAt: Date(timeIntervalSince1970: 3_000),
            objects: [
                CanonicalRecordingObject(
                    objectID: "recording-01",
                    nodeID: "iphone-test",
                    metadata: Self.metadata(title: title),
                    syncState: .synced,
                    transferState: .completed
                )
            ],
            manifestCapabilities: [.recordingMetadata]
        )
    }

    private static func legacyRecording(
        title: String,
        relativeAudioPath: String = "audio/recording-01.m4a",
        relativeMetadataPath: String = "metadata/recording-01.json",
        uploadStatus: String = "pending",
        uploadProgressFraction: Double? = nil,
        uploadProgressConfirmedBytes: Int64? = nil,
        uploadProgressTotalBytes: Int64? = nil
    ) -> RecordingMetadata {
        RecordingMetadata(
            id: "recording-01",
            title: title,
            fileName: "recording-01.m4a",
            relativeAudioPath: relativeAudioPath,
            relativeMetadataPath: relativeMetadataPath,
            createdAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_042),
            duration: 42,
            format: "m4a",
            codec: "aac",
            sampleRate: 44_100,
            channels: 1,
            bitrate: 128_000,
            fileSize: 42,
            uploadStatus: uploadStatus,
            transcriptionStatus: "completed",
            noteStatus: "completed",
            tags: ["math"],
            studyFiling: StudyFilingPath(type: "course", subject: "math"),
            uploadProgressFraction: uploadProgressFraction,
            uploadProgressConfirmedBytes: uploadProgressConfirmedBytes,
            uploadProgressTotalBytes: uploadProgressTotalBytes,
            uploadPhase: uploadProgressFraction == nil ? nil : "uploading",
            uploadProgressDescription: uploadProgressFraction == nil ? nil : "uploading"
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
                    sourceDescription: "canonicalRecordingMetadataTest",
                    modifiedByDeviceID: "iphone-test"
                )
            ],
            folders: [],
            recordings: [
                LocalNetworkSyncRecordingEntry(
                    recordingID: "recording-01",
                    metadataHash: String(Self.metadata(title: title).metadataHash.value.prefix(12)),
                    audioAvailable: true,
                    audioChecksum: String(repeating: "a", count: 64),
                    audioSize: 42,
                    uploadLedgerState: nil,
                    receiveStatus: nil,
                    processingStatus: nil,
                    updatedAt: Date(timeIntervalSince1970: 2_000),
                    deleted: false,
                    title: title,
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    tombstone: false,
                    audioAvailability: .local,
                    uploadStatus: "uploaded",
                    transcriptionStatus: "completed",
                    noteStatus: "completed",
                    sourceDeviceID: "iphone-test",
                    artifactRefs: nil,
                    audioLogicalPathToken: "audio/recording-01.m4a"
                )
            ]
        )
    }
}
