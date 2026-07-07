//
//  CanonicalReadRuntimeTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalReadRuntimeTests {
    @Test func defaultParallelAndCandidateModesReturnLegacy() {
        let legacy = Self.snapshot(source: .legacy)
        let canonical = Self.snapshot(source: .canonical)

        let disabled = CanonicalReadRuntimeProvider().read(
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            syncRunID: "read-default"
        )
        #expect(disabled.mode == .disabled)
        #expect(disabled.returnedSource == .legacy)
        #expect(disabled.canonicalReadServed == false)
        #expect(disabled.canonicalCandidateBuilt == false)
        #expect(disabled.fallback == .legacyDefault)

        let parallel = CanonicalReadRuntimeProvider(
            configuration: CanonicalReadRuntimeConfiguration(mode: .parallelCompare)
        ).read(legacySnapshot: legacy, canonicalSnapshot: canonical, syncRunID: "read-parallel")
        #expect(parallel.returnedSource == .legacy)
        #expect(parallel.canonicalCandidateBuilt)
        #expect(parallel.diff?.equivalent == true)
        #expect(parallel.diagnostics.contains { $0.kind == .canonicalReadRuntimeDiffEquivalent })

        let candidate = CanonicalReadRuntimeProvider(
            configuration: CanonicalReadRuntimeConfiguration(mode: .canonicalReadCandidate)
        ).read(legacySnapshot: legacy, canonicalSnapshot: canonical, syncRunID: "read-candidate")
        #expect(candidate.returnedSource == .legacy)
        #expect(candidate.canonicalCandidateBuilt)
        #expect(candidate.canonicalReadServed == false)
        #expect(candidate.fallback == .canonicalCandidateNotServed)
    }

    @Test func guardedServesCanonicalOnlyWithEvidenceAndZeroDivergence() {
        let result = CanonicalReadRuntimeProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            syncRunID: "read-guarded"
        )

        #expect(result.gateResult?.allowed == true)
        #expect(result.returnedSource == .canonical)
        #expect(result.canonicalReadServed)
        #expect(result.legacyFallbackServed == false)
        #expect(result.fallback == .none)
        #expect(result.diff?.equivalenceReport.domainsCompared.count == CanonicalReadDomain.allCases.count)
        #expect(result.readSnapshot.recordingMetadata.records.count == 1)
        #expect(result.readSnapshot.artifactMetadata.snapshot.itemCount == 1)
        #expect(result.readSnapshot.uploadState.records.first?.audioAvailable == true)
        #expect(result.readSnapshot.syncStatus.syncOrUploadTriggeredByRead == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataReadServedCanonical })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataReadDiffEquivalent })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactReadServedCanonical })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactReadDiffEquivalent })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactReadContentNotLogged })
    }

    @Test func divergenceAndUnsupportedObjectsFallBackToLegacy() {
        let legacy = Self.snapshot(source: .legacy)
        let divergent = Self.snapshot(source: .canonical, title: "Changed")
        let divergentResult = CanonicalReadRuntimeProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(legacySnapshot: legacy, canonicalSnapshot: divergent, syncRunID: "read-divergent")

        #expect(divergentResult.returnedSource == .legacy)
        #expect(divergentResult.canonicalReadServed == false)
        #expect(divergentResult.legacyFallbackServed)
        #expect(divergentResult.gateResult?.blockers.contains(.divergencePresent) == true)
        #expect(divergentResult.diff?.divergences.contains { $0.kind == .titleTagsFolderMismatch } == true)
        #expect(divergentResult.diagnostics.contains { $0.kind == .canonicalReadRuntimeDiffDivergent })

        var unsupported = Self.snapshot(source: .canonical)
        unsupported.recordingMetadata = CanonicalRecordingReadProjection(
            source: .canonical,
            failures: [
                CanonicalReadProjectionFailure(
                    kind: .unsupportedObject,
                    domain: .recordingMetadata,
                    objectID: "recording-unsupported",
                    reason: "unsupportedLegacyObject"
                )
            ]
        )
        let unsupportedResult = CanonicalReadRuntimeProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(legacySnapshot: legacy, canonicalSnapshot: unsupported, syncRunID: "read-unsupported")

        #expect(unsupportedResult.returnedSource == .legacy)
        #expect(unsupportedResult.diff?.divergences.contains { $0.kind == .unsupportedObject } == true)
        #expect(unsupportedResult.gateResult?.blockers.contains(.divergencePresent) == true)
    }

    @Test func readsHaveNoSyncUploadStoreOrProductionSideEffectsAndStayRedacted() {
        let fullHash = Self.fullHash
        var leaky = Self.snapshot(source: .canonical)
        leaky.redaction = CanonicalReadSnapshotRedaction(
            excludesAbsolutePaths: false,
            excludesFullHashes: true,
            excludesSecrets: true,
            excludesFullGeneratedContent: true,
            excludesRequestResponseBodies: true
        )
        let result = CanonicalReadRuntimeProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: leaky,
            syncRunID: "read-redaction",
            canonicalReadFailureReason: "/Users/vita/private/full-response.json"
        )
        let diagnosticsText = result.diagnostics.map(\.diagnosticsSummary).joined(separator: "\n")

        #expect(result.returnedSource == .legacy)
        #expect(result.storeMutated == false)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.uploadJobCreated == false)
        #expect(result.resourceMoved == false)
        #expect(result.productionDataWritten == false)
        #expect(result.diff?.divergences.contains { $0.kind == .pathContentLeakRisk } == true)
        #expect(diagnosticsText.contains("/Users") == false)
        #expect(diagnosticsText.contains(fullHash) == false)
        let diagnosticsAreRedacted = result.diagnostics.allSatisfy { diagnostic in
            diagnostic.isRedacted
        }
        #expect(diagnosticsAreRedacted)
    }

    @Test func iPhoneReadAdapterDefaultsLegacyAndExplicitGuardedCanServeCanonical() {
        let manifest = Self.studyManifest(title: "Adapter Lecture")
        let canonical = IPhoneCanonicalReadRuntimeAdapter.makeCanonicalManifest(manifest)

        let defaultRead = IPhoneCanonicalReadRuntimeAdapter().read(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            syncRunID: "iphone-read-default"
        )
        #expect(defaultRead.returnedSource == .legacy)
        #expect(defaultRead.canonicalReadServed == false)
        #expect(defaultRead.storeMutated == false)
        #expect(defaultRead.syncOrUploadTriggered == false)

        let guarded = IPhoneCanonicalReadRuntimeAdapter(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            syncRunID: "iphone-read-guarded"
        )
        #expect(guarded.returnedSource == .canonical)
        #expect(guarded.canonicalReadServed)
        #expect(guarded.readSnapshot.recordingMetadata.records.first?.title == "Adapter Lecture")
        #expect(guarded.readSnapshot.libraryMetadata.snapshot.contentExcludedCount == 0)
        #expect(guarded.readSnapshot.uploadState.records.first?.pathIncluded == false)
        #expect(guarded.uploadJobCreated == false)
    }

    @Test func iPhoneReadAdapterInvokesRecordingMetadataReadSideSeam() {
        let manifest = Self.studyManifest(title: "Adapter Seam Lecture")
        let canonical = IPhoneCanonicalReadRuntimeAdapter.makeCanonicalManifest(manifest)
        let spy = IPhoneRecordingReadSideSeamSpy(configuration: .explicitGuardedCanonicalRead())

        let result = IPhoneCanonicalReadRuntimeAdapter(
            configuration: .explicitGuardedCanonicalRead(),
            recordingMetadataReadSideSeam: spy
        ).read(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            syncRunID: "iphone-adapter-recording-seam"
        )

        #expect(spy.readCallCount == 1)
        #expect(spy.lastSyncRunID == "iphone-adapter-recording-seam")
        #expect(result.returnedSource == .canonical)
        #expect(result.canonicalReadServed)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.uploadJobCreated == false)
        #expect(result.storeMutated == false)
    }

    @Test func iPhoneReadAdapterFallsBackForGateFailureWithoutMutatingStore() {
        let manifest = Self.studyManifest(title: "Adapter Lecture")
        let canonical = IPhoneCanonicalReadRuntimeAdapter.makeCanonicalManifest(
            Self.studyManifest(title: "Different")
        )
        let result = IPhoneCanonicalReadRuntimeAdapter(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            syncRunID: "iphone-read-fallback"
        )

        #expect(result.returnedSource == .legacy)
        #expect(result.legacyFallbackServed)
        #expect((result.diff?.divergenceCount ?? 0) > 0)
        #expect(result.storeMutated == false)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.uploadJobCreated == false)
    }

    @MainActor
    @Test func iPhoneStoreMasterSwitchReadConfigurationRefreshesOverrideAndFallback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalReadRuntimeStoreSwitch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root)
        try await store.applySyncManifest(Self.studyManifest(title: "Switch Store Lecture"), localDeviceID: "iphone-local")

        let oldKernel = CanonicalKernelSwitchConfiguration(mode: .oldKernel).resolve()
        let oldResult = store.setCanonicalReadRuntimeConfiguration(
            oldKernel.effectiveConfiguration.readRuntimeConfiguration
        )
        #expect(oldResult.mode == .disabled)
        #expect(oldResult.returnedSource == .legacy)
        #expect(store.canonicalReadRuntimeConfigurationOverrideIsSet == false)

        let shadow = CanonicalKernelSwitchConfiguration(
            mode: .canonicalShadow,
            policy: .debugInternal()
        ).resolve()
        let shadowResult = store.setCanonicalReadRuntimeConfiguration(
            shadow.effectiveConfiguration.readRuntimeConfiguration
        )
        #expect(shadowResult.mode == .parallelCompare)
        #expect(shadowResult.returnedSource == .legacy)
        #expect(shadowResult.canonicalReadServed == false)
        #expect(shadowResult.canonicalCandidateBuilt)

        for mode in [CanonicalKernelSwitchMode.canonicalDecisionOnly, .canonicalApplyNoAudio] {
            let result = CanonicalKernelSwitchConfiguration(
                mode: mode,
                policy: .debugInternal()
            ).resolve()
            let readResult = store.setCanonicalReadRuntimeConfiguration(
                result.effectiveConfiguration.readRuntimeConfiguration
            )
            #expect(readResult.mode == .disabled)
            #expect(readResult.returnedSource == .legacy)
            #expect(readResult.canonicalReadServed == false)
            #expect(store.canonicalReadRuntimeConfigurationOverrideIsSet == false)
        }

        let fullSync = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()
        let fullResult = store.setCanonicalReadRuntimeConfiguration(
            fullSync.effectiveConfiguration.readRuntimeConfiguration
        )
        #expect(fullResult.mode == .guardedCanonicalReadWithLegacyFallback)
        #expect(fullResult.returnedSource == .canonical)
        #expect(fullResult.canonicalReadServed)
        #expect(store.canonicalReadRuntimeConfigurationOverrideIsSet)
        #expect(fullResult.syncOrUploadTriggered == false)
        #expect(fullResult.uploadJobCreated == false)
        #expect(fullResult.storeMutated == false)

        let switchedBack = store.setCanonicalReadRuntimeConfiguration(nil)
        #expect(switchedBack.mode == .disabled)
        #expect(switchedBack.returnedSource == .legacy)
        #expect(store.canonicalReadRuntimeConfigurationOverrideIsSet == false)
    }

    @MainActor
    @Test func iPhoneCoordinatorAppliesMasterSwitchReadConfigurationToStoreOnInit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalReadRuntimeCoordinator-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root)
        try await store.applySyncManifest(Self.studyManifest(title: "Coordinator Store Lecture"), localDeviceID: "iphone-local")
        let fullSync = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()

        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: IPhoneReadRuntimeFakeConnectionStore(snapshot: Self.secureMacSnapshot()),
            studyLibraryStore: store,
            statusStore: DeviceConnectionStatusStore(rootURL: root),
            syncStateStore: StudyLibrarySyncStateStore(rootURL: root),
            diagnosticsStore: ConnectionDiagnosticsStore(rootURL: root),
            canonicalKernelSwitchResultProvider: { fullSync }
        )

        #expect(coordinator.syncSummary.pendingLocalChanges == 0)
        #expect(store.canonicalReadRuntimeReturnedSource == .canonical)
        #expect(store.canonicalReadRuntimeResult?.syncOrUploadTriggered == false)
        #expect(store.canonicalReadRuntimeResult?.uploadJobCreated == false)
        #expect(store.canonicalReadRuntimeResult?.storeMutated == false)
    }

    @MainActor
    @Test func iPhoneStudyLibraryStoreUsesLegacyByDefaultAndCanonicalOnlyWhenGuarded() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalReadRuntimeStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root)
        try await store.applySyncManifest(Self.studyManifest(title: "Store Lecture"), localDeviceID: "iphone-local")
        _ = store.configureCanonicalReadRuntime(
            configuration: .disabled,
            canonicalManifest: nil,
            syncRunID: "store-read-default"
        )

        #expect(store.effectiveStudyItems.first?.title == "Store Lecture")
        #expect(store.canonicalReadRuntimeReturnedSource == .legacy)

        let canonical = IPhoneCanonicalReadRuntimeAdapter.makeCanonicalManifest(
            store.makeSyncManifest(
                deviceID: "iphone-local",
                generatedAt: Date(timeIntervalSince1970: 3_000)
            )
        )
        let result = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(),
            canonicalManifest: canonical,
            syncRunID: "store-read-guarded"
        )

        #expect(result.returnedSource == .canonical)
        #expect(store.canonicalReadRuntimeReturnedSource == .canonical)
        #expect(store.effectiveStudyItems.first?.title == "Store Lecture")
        #expect(store.allStudyItems.first?.title == "Store Lecture")
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.storeMutated == false)
        #expect(result.uploadJobCreated == false)
    }

    @MainActor
    @Test func iPhoneOldKernelEffectiveReadUsesLegacyWithoutCanonicalProjectionCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalReadRuntimeOldKernelCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root)
        try await store.applySyncManifest(Self.studyManifest(title: "Old Kernel Store Lecture"), localDeviceID: "iphone-local")

        let oldKernel = CanonicalKernelSwitchConfiguration(mode: .oldKernel).resolve()
        let result = store.setCanonicalReadRuntimeConfiguration(oldKernel.effectiveConfiguration.readRuntimeConfiguration)
        let beforeAccess = store.canonicalReadEffectiveCacheMetrics
        let items = store.effectiveStudyItems
        let folders = store.effectiveStudyFolders
        let afterAccess = store.canonicalReadEffectiveCacheMetrics

        #expect(result.mode == .disabled)
        #expect(result.returnedSource == .legacy)
        #expect(items.first?.title == "Old Kernel Store Lecture")
        #expect(folders == store.allStudyFolders)
        #expect(afterAccess.projectionRebuildCount == beforeAccess.projectionRebuildCount)
        #expect(afterAccess.treeRebuildCount == beforeAccess.treeRebuildCount)
        #expect(afterAccess.cacheHitCount == beforeAccess.cacheHitCount)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.uploadJobCreated == false)
        #expect(result.storeMutated == false)
    }

    @MainActor
    @Test func iPhoneCanonicalEffectiveReadCacheRebuildsOnceForRepeatedAccessAndInvalidatesDeterministically() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalReadRuntimeEffectiveCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root)
        try await store.applySyncManifest(Self.studyManifest(title: "Cached Store Lecture"), localDeviceID: "iphone-local")
        let canonical = IPhoneCanonicalReadRuntimeAdapter.makeCanonicalManifest(
            store.makeSyncManifest(deviceID: "iphone-local", generatedAt: Date(timeIntervalSince1970: 3_000))
        )
        let beforeConfigure = store.canonicalReadEffectiveCacheMetrics

        let result = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(),
            canonicalManifest: canonical,
            syncRunID: "iphone-effective-cache"
        )
        let afterConfigure = store.canonicalReadEffectiveCacheMetrics
        let backingItems = store.allStudyItems
        let firstItems = store.effectiveStudyItems
        let firstFolders = store.effectiveStudyFolders
        let secondItems = store.effectiveStudyItems
        let secondFolders = store.effectiveStudyFolders
        let afterRepeatedAccess = store.canonicalReadEffectiveCacheMetrics

        #expect(result.returnedSource == .canonical)
        #expect(result.canonicalReadServed)
        #expect(afterConfigure.projectionRebuildCount == beforeConfigure.projectionRebuildCount + 1)
        #expect(afterConfigure.itemProjectionBuildCount == beforeConfigure.itemProjectionBuildCount + 1)
        #expect(afterConfigure.folderProjectionBuildCount == beforeConfigure.folderProjectionBuildCount + 1)
        #expect(firstItems == secondItems)
        #expect(firstFolders == secondFolders)
        #expect(firstItems.first?.title == "Cached Store Lecture")
        #expect(afterRepeatedAccess.projectionRebuildCount == afterConfigure.projectionRebuildCount)
        #expect(afterRepeatedAccess.itemProjectionBuildCount == afterConfigure.itemProjectionBuildCount)
        #expect(afterRepeatedAccess.folderProjectionBuildCount == afterConfigure.folderProjectionBuildCount)
        #expect(afterRepeatedAccess.cacheHitCount >= 3)
        #expect(afterRepeatedAccess.repeatedAccessCount >= 2)
        #expect(store.allStudyItems == backingItems)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.uploadJobCreated == false)
        #expect(result.storeMutated == false)

        var sameContentNewGeneratedAt = canonical
        sameContentNewGeneratedAt.generatedAt = CanonicalTimestamp(Date(timeIntervalSince1970: 4_000))
        _ = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(),
            canonicalManifest: sameContentNewGeneratedAt,
            syncRunID: "iphone-effective-cache-generated-at-only"
        )
        let afterGeneratedAtOnly = store.canonicalReadEffectiveCacheMetrics
        #expect(afterGeneratedAtOnly.projectionRebuildCount == afterRepeatedAccess.projectionRebuildCount)
        #expect(afterGeneratedAtOnly.cacheInvalidationCount == afterRepeatedAccess.cacheInvalidationCount)

        let changedContentCanonical = IPhoneCanonicalReadRuntimeAdapter.makeCanonicalManifest(
            Self.studyManifest(title: "Cached Store Lecture Content Changed")
        )
        _ = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(allowDivergentGuardedReadForTests: true),
            canonicalManifest: changedContentCanonical,
            syncRunID: "iphone-effective-cache-content-change"
        )
        let afterResultChange = store.canonicalReadEffectiveCacheMetrics
        #expect(afterResultChange.projectionRebuildCount > afterGeneratedAtOnly.projectionRebuildCount)
        #expect(afterResultChange.cacheInvalidationCount > afterGeneratedAtOnly.cacheInvalidationCount)

        _ = store.setCanonicalReadRuntimeConfiguration(.disabled)
        let afterConfigChange = store.canonicalReadEffectiveCacheMetrics
        #expect(afterConfigChange.cacheInvalidationCount >= afterResultChange.cacheInvalidationCount)
        #expect(afterConfigChange.fallbackLegacyCount >= 1)

        _ = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(),
            canonicalManifest: canonical,
            syncRunID: "iphone-effective-cache-refresh"
        )
        let beforeRefresh = store.canonicalReadEffectiveCacheMetrics
        store.refresh()
        let afterRefresh = store.canonicalReadEffectiveCacheMetrics
        #expect(afterRefresh.projectionRebuildCount > beforeRefresh.projectionRebuildCount)
        #expect(afterRefresh.cacheInvalidationCount > beforeRefresh.cacheInvalidationCount)

        let diagnosticKinds = Set(store.canonicalReadEffectiveCacheDiagnosticEvents.map(\.kind))
        let diagnosticText = store.canonicalReadEffectiveCacheDiagnosticEvents.map(\.diagnosticsSummary).joined(separator: "\n")
        #expect(diagnosticKinds.contains(.canonicalReadEffectiveCacheHit))
        #expect(diagnosticKinds.contains(.canonicalReadEffectiveCacheMiss))
        #expect(diagnosticKinds.contains(.canonicalReadEffectiveCacheInvalidated))
        #expect(diagnosticKinds.contains(.canonicalReadEffectiveCacheRebuilt))
        #expect(diagnosticKinds.contains(.canonicalReadEffectiveRepeatedAccessAvoidedRebuild))
        #expect(diagnosticKinds.contains(.canonicalReadEffectiveRebuildDurationMs))
        #expect(diagnosticKinds.contains(.canonicalReadEffectiveFallbackLegacy))
        let cacheDiagnosticsRedacted = store.canonicalReadEffectiveCacheDiagnosticEvents.allSatisfy(\.isRedacted)
        #expect(cacheDiagnosticsRedacted)
        #expect(diagnosticText.contains("/Users") == false)
        #expect(diagnosticText.contains(Self.fullHash) == false)
        let fileDiagnostics = store.canonicalFileRuntimeDiagnosticRecords
        let fileDiagnosticText = fileDiagnostics.compactMap(\.redactedDetail).joined(separator: "\n")
        #expect(fileDiagnostics.contains { $0.kind == .readProjectionRebuildDurationMs && $0.domain == .file })
        #expect(fileDiagnosticText.contains("cacheKeyPrefix="))
        #expect(fileDiagnosticText.contains("reason="))
        #expect(fileDiagnosticText.contains("/Users") == false)
        #expect(fileDiagnosticText.contains(Self.fullHash) == false)
    }

    @MainActor
    @Test func iPhoneStudyLibraryStoreFallsBackToLegacyOnDivergentCanonicalRead() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalReadRuntimeStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root)
        try await store.applySyncManifest(Self.studyManifest(title: "Legacy Store Lecture"), localDeviceID: "iphone-local")

        let divergent = IPhoneCanonicalReadRuntimeAdapter.makeCanonicalManifest(Self.studyManifest(title: "Canonical Divergent"))
        let result = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(),
            canonicalManifest: divergent,
            syncRunID: "store-read-divergent"
        )

        #expect(result.returnedSource == .legacy)
        #expect(store.canonicalReadRuntimeReturnedSource == .legacy)
        #expect(store.effectiveStudyItems.first?.title == "Legacy Store Lecture")
        #expect((result.diff?.divergenceCount ?? 0) > 0)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.storeMutated == false)
    }

    private static let fullHash = String(repeating: "a", count: 64)

    private static func snapshot(
        source: CanonicalReadProjectionSource,
        title: String = "Lecture"
    ) -> CanonicalReadSnapshot {
        CanonicalReadSnapshot.build(
            source: source,
            manifest: canonicalManifest(title: title),
            uploadCandidates: [uploadCandidate()],
            generatedAt: Date(timeIntervalSince1970: 3_000)
        )
    }

    private static func canonicalManifest(title: String = "Lecture") -> CanonicalManifest {
        let objectID = "recording-01"
        let metadata = CanonicalRecordingMetadata(
            objectID: objectID,
            title: title,
            createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1_000)),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2_000)),
            duration: 42,
            tags: ["math"]
        )
        let audio = CanonicalArtifact(
            artifactID: CanonicalProjectionContract.artifactID(objectID: objectID, kind: .audio),
            objectID: objectID,
            kind: .audio,
            availability: .available,
            contentHash: CanonicalHash(fullHash),
            byteSize: 42,
            logicalName: nil,
            logicalPathToken: nil,
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2_100)),
            producedBy: .audioCapture,
            producedByNodeID: "iphone-test"
        )
        let note = CanonicalArtifact(
            artifactID: CanonicalProjectionContract.artifactID(objectID: objectID, kind: .noteJSON),
            objectID: objectID,
            kind: .noteJSON,
            availability: .available,
            contentHash: CanonicalHash(String(repeating: "b", count: 64)),
            byteSize: 8,
            logicalName: "note.json",
            logicalPathToken: "generated/recording-01/note.json",
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2_200)),
            producedBy: .noteGeneration,
            producedByNodeID: "mac-test"
        )
        let recording = CanonicalRecordingObject(
            objectID: objectID,
            nodeID: "iphone-test",
            metadata: metadata,
            artifacts: [audio, note],
            syncState: .synced,
            transferState: .completed
        )
        return CanonicalManifest.make(
            node: CanonicalNode(nodeID: "iphone-test", platform: "iPhone", capabilities: [.recordingMetadata, .audioArtifact, .noteArtifact]),
            generatedAt: Date(timeIntervalSince1970: 3_000),
            objects: [recording],
            manifestCapabilities: [.recordingMetadata, .audioArtifact, .noteArtifact]
        )
    }

    private static func uploadCandidate() -> CanonicalAudioUploadCutoverCandidate {
        CanonicalAudioUploadCutoverCandidate(
            objectID: "recording-01",
            localTruth: .available(hash: CanonicalHash(fullHash), byteSize: 42),
            peerTruth: CanonicalAudioUploadPeerTruth(state: .metadataOnly),
            trigger: .ordinarySync,
            actionKind: .audioUploadCanaryCandidate,
            reason: "peerMetadataOnlyAudioMissing",
            evidenceStatus: .complete
        )
    }

    private static func secureMacSnapshot() -> SecureMacConnectionSnapshot {
        SecureMacConnectionSnapshot(
            macHost: "127.0.0.1",
            macPort: 8787,
            macFingerprint: String(repeating: "a", count: 64),
            macName: "Rokurics Mac",
            macModel: "Mac",
            deviceID: "mac-read-runtime",
            sharedSecretBase64URL: "c3luYy1zZWNyZXQ",
            pairedAt: "2026-06-12T00:00:00Z"
        )
    }

    private static func studyManifest(
        title: String,
        generatedAt: Date = Date(timeIntervalSince1970: 3_000)
    ) -> StudyLibrarySyncManifest {
        StudyLibrarySyncManifest.make(
            deviceID: "iphone-test",
            generatedAt: generatedAt,
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
                    sourceDescription: "canonicalReadRuntimeTest",
                    modifiedByDeviceID: "iphone-test"
                )
            ],
            folders: [],
            recordings: [
                LocalNetworkSyncRecordingEntry(
                    recordingID: "recording-01",
                    metadataHash: String(fullHash.prefix(12)),
                    audioAvailable: true,
                    audioChecksum: fullHash,
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

@MainActor
private final class IPhoneReadRuntimeFakeConnectionStore: SecureMacConnectionSnapshotProviding {
    var snapshot: SecureMacConnectionSnapshot

    init(snapshot: SecureMacConnectionSnapshot) {
        self.snapshot = snapshot
    }
}

private final class IPhoneRecordingReadSideSeamSpy: IPhoneRecordingMetadataReadSideSeamReading, @unchecked Sendable {
    private let configuration: CanonicalReadRuntimeConfiguration
    private(set) var readCallCount = 0
    private(set) var lastSyncRunID: String?

    init(configuration: CanonicalReadRuntimeConfiguration) {
        self.configuration = configuration
    }

    func read(
        legacyCanonicalManifest: CanonicalManifest?,
        canonicalManifest: CanonicalManifest?,
        peerCanonicalManifest: CanonicalManifest?,
        uploadCandidates: [CanonicalAudioUploadCutoverCandidate],
        syncRuntimeResult: CanonicalSyncRuntimeResult?,
        syncRunID: String?,
        canonicalReadFailureReason: String?
    ) -> CanonicalReadRuntimeResult {
        readCallCount += 1
        lastSyncRunID = syncRunID
        return IPhoneRecordingMetadataReadSideSeam(configuration: configuration).read(
            legacyCanonicalManifest: legacyCanonicalManifest,
            canonicalManifest: canonicalManifest,
            peerCanonicalManifest: peerCanonicalManifest,
            uploadCandidates: uploadCandidates,
            syncRuntimeResult: syncRuntimeResult,
            syncRunID: syncRunID,
            canonicalReadFailureReason: canonicalReadFailureReason
        )
    }
}
