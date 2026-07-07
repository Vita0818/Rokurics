//
//  CanonicalReadRuntimeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalReadRuntimeTests {
    @Test func sharedRuntimeDefaultParallelCandidateAndGuardedModes() {
        let legacy = Self.snapshot(source: .legacy)
        let canonical = Self.snapshot(source: .canonical)

        let disabled = CanonicalReadRuntimeProvider().read(
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            syncRunID: "mac-read-default"
        )
        #expect(disabled.returnedSource == .legacy)
        #expect(disabled.canonicalCandidateBuilt == false)
        #expect(disabled.fallback == .legacyDefault)

        let parallel = CanonicalReadRuntimeProvider(
            configuration: CanonicalReadRuntimeConfiguration(mode: .parallelCompare)
        ).read(legacySnapshot: legacy, canonicalSnapshot: canonical, syncRunID: "mac-read-parallel")
        #expect(parallel.returnedSource == .legacy)
        #expect(parallel.diff?.equivalent == true)
        #expect(parallel.canonicalReadServed == false)

        let candidate = CanonicalReadRuntimeProvider(
            configuration: CanonicalReadRuntimeConfiguration(mode: .canonicalReadCandidate)
        ).read(legacySnapshot: legacy, canonicalSnapshot: canonical, syncRunID: "mac-read-candidate")
        #expect(candidate.returnedSource == .legacy)
        #expect(candidate.canonicalCandidateBuilt)
        #expect(candidate.fallback == .canonicalCandidateNotServed)

        let guarded = CanonicalReadRuntimeProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(legacySnapshot: legacy, canonicalSnapshot: canonical, syncRunID: "mac-read-guarded")
        #expect(guarded.returnedSource == .canonical)
        #expect(guarded.canonicalReadServed)
        #expect(guarded.diff?.equivalenceReport.domainsCompared.count == CanonicalReadDomain.allCases.count)
        #expect(guarded.readSnapshot.artifactMetadata.snapshot.contentIncludedCount == 0)
        #expect(guarded.readSnapshot.uploadState.records.first?.pathIncluded == false)
        #expect(guarded.diagnostics.contains { $0.kind == .canonicalLibraryMetadataReadServedCanonical })
        #expect(guarded.diagnostics.contains { $0.kind == .canonicalLibraryMetadataReadDiffEquivalent })
        #expect(guarded.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactReadServedCanonical })
        #expect(guarded.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactReadDiffEquivalent })
        #expect(guarded.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactReadContentNotLogged })
    }

    @Test func guardedRuntimeFallsBackForDivergenceUnsupportedAndLeakRisk() {
        let legacy = Self.snapshot(source: .legacy)
        let divergent = CanonicalReadRuntimeProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: Self.snapshot(source: .canonical, title: "Changed"),
            syncRunID: "mac-read-divergent"
        )
        #expect(divergent.returnedSource == .legacy)
        #expect(divergent.gateResult?.blockers.contains(.divergencePresent) == true)
        #expect(divergent.diff?.divergences.contains { $0.kind == .titleTagsFolderMismatch } == true)

        var unsupported = Self.snapshot(source: .canonical)
        unsupported.recordingMetadata = CanonicalRecordingReadProjection(
            source: .canonical,
            failures: [
                CanonicalReadProjectionFailure(
                    kind: .unsupportedObject,
                    domain: .recordingMetadata,
                    objectID: "recording-unsupported",
                    reason: "unsupportedObject"
                )
            ]
        )
        let unsupportedResult = CanonicalReadRuntimeProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(legacySnapshot: legacy, canonicalSnapshot: unsupported, syncRunID: "mac-read-unsupported")
        #expect(unsupportedResult.returnedSource == .legacy)
        #expect(unsupportedResult.diff?.divergences.contains { $0.kind == .unsupportedObject } == true)

        var leaky = Self.snapshot(source: .canonical)
        leaky.redaction = CanonicalReadSnapshotRedaction(
            excludesAbsolutePaths: false,
            excludesFullHashes: true,
            excludesSecrets: true,
            excludesFullGeneratedContent: true,
            excludesRequestResponseBodies: true
        )
        let leakResult = CanonicalReadRuntimeProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: leaky,
            syncRunID: "mac-read-leak",
            canonicalReadFailureReason: "/Users/vita/private/receive.json"
        )
        let diagnosticsText = leakResult.diagnostics.map(\.diagnosticsSummary).joined(separator: "\n")
        #expect(leakResult.returnedSource == .legacy)
        #expect(leakResult.diff?.divergences.contains { $0.kind == .pathContentLeakRisk } == true)
        #expect(diagnosticsText.contains("/Users") == false)
        #expect(diagnosticsText.contains(Self.fullHash) == false)
        let diagnosticsAreRedacted = leakResult.diagnostics.allSatisfy { diagnostic in
            diagnostic.isRedacted
        }
        #expect(diagnosticsAreRedacted)
    }

    @Test func macReadAdapterDefaultAndExplicitGuardedModesDoNotMutateReceiveOrInbox() {
        let manifest = Self.studyManifest(title: "Mac Adapter Lecture")
        let canonical = MacCanonicalReadRuntimeAdapter.makeCanonicalManifest(manifest)

        let defaultRead = MacCanonicalReadRuntimeAdapter().read(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            syncRunID: "mac-adapter-default"
        )
        #expect(defaultRead.returnedSource == .legacy)
        #expect(defaultRead.canonicalReadServed == false)
        #expect(defaultRead.storeMutated == false)
        #expect(defaultRead.syncOrUploadTriggered == false)
        #expect(defaultRead.uploadJobCreated == false)

        let guarded = MacCanonicalReadRuntimeAdapter(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            syncRunID: "mac-adapter-guarded"
        )
        #expect(guarded.returnedSource == .canonical)
        #expect(guarded.canonicalReadServed)
        #expect(guarded.readSnapshot.recordingMetadata.records.first?.title == "Mac Adapter Lecture")
        #expect(guarded.readSnapshot.artifactMetadata.snapshot.contentIncludedCount == 0)
        #expect(guarded.readSnapshot.uploadState.records.first?.createdUploadJob == false)
        #expect(guarded.storeMutated == false)
        #expect(guarded.syncOrUploadTriggered == false)
        #expect(guarded.productionDataWritten == false)
    }

    @Test func macReadAdapterInvokesRecordingMetadataReadSideSeam() {
        let manifest = Self.studyManifest(title: "Mac Adapter Seam Lecture")
        let canonical = MacCanonicalReadRuntimeAdapter.makeCanonicalManifest(manifest)
        let spy = MacRecordingReadSideSeamSpy(configuration: .explicitGuardedCanonicalRead())

        let result = MacCanonicalReadRuntimeAdapter(
            configuration: .explicitGuardedCanonicalRead(),
            recordingMetadataReadSideSeam: spy
        ).read(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            syncRunID: "mac-adapter-recording-seam"
        )

        #expect(spy.readCallCount == 1)
        #expect(spy.lastSyncRunID == "mac-adapter-recording-seam")
        #expect(result.returnedSource == .canonical)
        #expect(result.canonicalReadServed)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.uploadJobCreated == false)
        #expect(result.storeMutated == false)
    }

    @Test func macReadAdapterFallbackPreservesLegacyAndNoUploadJob() {
        let manifest = Self.studyManifest(title: "Mac Adapter Lecture")
        let canonical = MacCanonicalReadRuntimeAdapter.makeCanonicalManifest(
            Self.studyManifest(title: "Different")
        )

        let result = MacCanonicalReadRuntimeAdapter(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            syncRunID: "mac-adapter-fallback"
        )
        #expect(result.returnedSource == .legacy)
        #expect(result.legacyFallbackServed)
        #expect((result.diff?.divergenceCount ?? 0) > 0)
        #expect(result.storeMutated == false)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.uploadJobCreated == false)
        #expect(result.resourceMoved == false)
    }

    @MainActor
    @Test func macStoreMasterSwitchReadConfigurationRefreshesOverrideAndFallback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalReadRuntimeMacStoreSwitch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root, listenForInboxChanges: false)
        try await store.applySyncManifest(Self.studyManifest(title: "Mac Switch Store Lecture"), localDeviceID: "mac-local")

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
    @Test func macReceiverAppliesMasterSwitchReadConfigurationToStoreOnInit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalReadRuntimeMacReceiver-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root, listenForInboxChanges: false)
        try await store.applySyncManifest(Self.studyManifest(title: "Mac Receiver Store Lecture"), localDeviceID: "mac-local")
        let fullSync = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()

        let service = SecureReceiverService(
            studyLibraryStore: store,
            canonicalKernelSwitchResultProvider: { fullSync },
            loadIdentityOnInit: false,
            preferredIPAddressProvider: { nil }
        )

        #expect(service.canonicalReadRuntimeConfiguration.mode == .guardedCanonicalReadWithLegacyFallback)
        #expect(store.canonicalReadRuntimeReturnedSource == .canonical)
        #expect(store.canonicalReadRuntimeResult?.syncOrUploadTriggered == false)
        #expect(store.canonicalReadRuntimeResult?.uploadJobCreated == false)
        #expect(store.canonicalReadRuntimeResult?.storeMutated == false)
    }

    @MainActor
    @Test func macStudyLibraryStoreUsesLegacyByDefaultAndCanonicalOnlyWhenGuarded() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalReadRuntimeMacStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root, listenForInboxChanges: false)
        try await store.applySyncManifest(Self.studyManifest(title: "Mac Store Lecture"), localDeviceID: "mac-local")
        _ = store.configureCanonicalReadRuntime(
            configuration: .disabled,
            canonicalManifest: nil,
            syncRunID: "mac-store-read-default"
        )

        #expect(store.effectiveStudyItems.first?.title == "Mac Store Lecture")
        #expect(store.canonicalReadRuntimeReturnedSource == .legacy)

        let canonical = MacCanonicalReadRuntimeAdapter.makeCanonicalManifest(
            store.makeSyncManifest(
                deviceID: "mac-local",
                generatedAt: Date(timeIntervalSince1970: 3_000)
            )
        )
        let result = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(),
            canonicalManifest: canonical,
            syncRunID: "mac-store-read-guarded"
        )

        #expect(result.returnedSource == .canonical)
        #expect(store.canonicalReadRuntimeReturnedSource == .canonical)
        #expect(store.effectiveStudyItems.first?.title == "Mac Store Lecture")
        #expect(store.effectiveStudyTree.count == store.tree().count)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.storeMutated == false)
        #expect(result.uploadJobCreated == false)
    }

    @MainActor
    @Test func macOldKernelEffectiveReadUsesLegacyCachedTreeWithoutCanonicalProjectionCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalReadRuntimeMacOldKernelCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root, listenForInboxChanges: false)
        try await store.applySyncManifest(Self.studyManifest(title: "Mac Old Kernel Store Lecture"), localDeviceID: "mac-local")
        let legacyTreeCount = store.studyTree.count

        let oldKernel = CanonicalKernelSwitchConfiguration(mode: .oldKernel).resolve()
        let result = store.setCanonicalReadRuntimeConfiguration(oldKernel.effectiveConfiguration.readRuntimeConfiguration)
        let beforeAccess = store.canonicalReadEffectiveCacheMetrics
        let items = store.effectiveStudyItems
        let folders = store.effectiveStudyFolders
        let tree = store.effectiveStudyTree
        let defaultTree = store.tree()
        let afterAccess = store.canonicalReadEffectiveCacheMetrics

        #expect(result.mode == .disabled)
        #expect(result.returnedSource == .legacy)
        #expect(items.first?.title == "Mac Old Kernel Store Lecture")
        #expect(folders == store.allStudyFolders)
        #expect(tree.count == legacyTreeCount)
        #expect(defaultTree.count == legacyTreeCount)
        #expect(afterAccess.projectionRebuildCount == beforeAccess.projectionRebuildCount)
        #expect(afterAccess.treeRebuildCount == beforeAccess.treeRebuildCount)
        #expect(afterAccess.cacheHitCount == beforeAccess.cacheHitCount)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.uploadJobCreated == false)
        #expect(result.storeMutated == false)
    }

    @MainActor
    @Test func macCanonicalEffectiveReadCacheRebuildsTreeOnceForRepeatedAccessAndInvalidatesDeterministically() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalReadRuntimeMacEffectiveCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root, listenForInboxChanges: false)
        _ = store.setCanonicalReadRuntimeConfiguration(.disabled)
        try await store.applySyncManifest(Self.studyManifest(title: "Mac Cached Store Lecture"), localDeviceID: "mac-local")
        let canonical = MacCanonicalReadRuntimeAdapter.makeCanonicalManifest(
            store.makeSyncManifest(deviceID: "mac-local", generatedAt: Date(timeIntervalSince1970: 3_000))
        )
        let beforeConfigure = store.canonicalReadEffectiveCacheMetrics

        let result = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(),
            canonicalManifest: canonical,
            syncRunID: "mac-effective-cache"
        )
        let afterConfigure = store.canonicalReadEffectiveCacheMetrics
        let backingItems = store.allStudyItems
        let firstItems = store.effectiveStudyItems
        let firstFolders = store.effectiveStudyFolders
        let secondItems = store.effectiveStudyItems
        let secondFolders = store.effectiveStudyFolders
        let firstTree = store.effectiveStudyTree
        let defaultTree = store.tree()
        let secondTree = store.effectiveStudyTree
        let afterRepeatedAccess = store.canonicalReadEffectiveCacheMetrics

        #expect(result.returnedSource == .canonical)
        #expect(result.canonicalReadServed)
        #expect(afterConfigure.projectionRebuildCount == beforeConfigure.projectionRebuildCount + 1)
        #expect(afterConfigure.treeRebuildCount == beforeConfigure.treeRebuildCount + 1)
        #expect(afterConfigure.itemProjectionBuildCount == beforeConfigure.itemProjectionBuildCount + 1)
        #expect(afterConfigure.folderProjectionBuildCount == beforeConfigure.folderProjectionBuildCount + 1)
        #expect(firstItems.first?.title == "Mac Cached Store Lecture")
        #expect(firstItems == secondItems)
        #expect(firstFolders == secondFolders)
        #expect(firstTree == defaultTree)
        #expect(firstTree == secondTree)
        #expect(afterRepeatedAccess.projectionRebuildCount == afterConfigure.projectionRebuildCount)
        #expect(afterRepeatedAccess.treeRebuildCount == afterConfigure.treeRebuildCount)
        #expect(afterRepeatedAccess.itemProjectionBuildCount == afterConfigure.itemProjectionBuildCount)
        #expect(afterRepeatedAccess.folderProjectionBuildCount == afterConfigure.folderProjectionBuildCount)
        #expect(afterRepeatedAccess.cacheHitCount >= 5)
        #expect(afterRepeatedAccess.repeatedAccessCount >= 3)
        #expect(store.allStudyItems == backingItems)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.uploadJobCreated == false)
        #expect(result.storeMutated == false)

        var sameContentNewGeneratedAt = canonical
        sameContentNewGeneratedAt.generatedAt = CanonicalTimestamp(Date(timeIntervalSince1970: 4_000))
        _ = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(),
            canonicalManifest: sameContentNewGeneratedAt,
            syncRunID: "mac-effective-cache-generated-at-only"
        )
        let afterGeneratedAtOnly = store.canonicalReadEffectiveCacheMetrics
        #expect(afterGeneratedAtOnly.projectionRebuildCount == afterRepeatedAccess.projectionRebuildCount)
        #expect(afterGeneratedAtOnly.treeRebuildCount == afterRepeatedAccess.treeRebuildCount)
        #expect(afterGeneratedAtOnly.cacheInvalidationCount == afterRepeatedAccess.cacheInvalidationCount)

        let changedContentCanonical = MacCanonicalReadRuntimeAdapter.makeCanonicalManifest(
            Self.studyManifest(title: "Mac Cached Store Lecture Content Changed")
        )
        _ = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(allowDivergentGuardedReadForTests: true),
            canonicalManifest: changedContentCanonical,
            syncRunID: "mac-effective-cache-content-change"
        )
        let afterResultChange = store.canonicalReadEffectiveCacheMetrics
        #expect(afterResultChange.projectionRebuildCount > afterGeneratedAtOnly.projectionRebuildCount)
        #expect(afterResultChange.treeRebuildCount > afterGeneratedAtOnly.treeRebuildCount)
        #expect(afterResultChange.cacheInvalidationCount > afterGeneratedAtOnly.cacheInvalidationCount)

        _ = store.setCanonicalReadRuntimeConfiguration(.disabled)
        let afterConfigChange = store.canonicalReadEffectiveCacheMetrics
        #expect(afterConfigChange.cacheInvalidationCount >= afterResultChange.cacheInvalidationCount)
        #expect(afterConfigChange.fallbackLegacyCount >= 1)

        _ = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(),
            canonicalManifest: canonical,
            syncRunID: "mac-effective-cache-refresh"
        )
        let beforeRefresh = store.canonicalReadEffectiveCacheMetrics
        store.refresh()
        let afterRefresh = store.canonicalReadEffectiveCacheMetrics
        #expect(afterRefresh.projectionRebuildCount > beforeRefresh.projectionRebuildCount)
        #expect(afterRefresh.treeRebuildCount > beforeRefresh.treeRebuildCount)
        #expect(afterRefresh.cacheInvalidationCount > beforeRefresh.cacheInvalidationCount)

        let diagnosticKinds = Set(store.canonicalReadEffectiveCacheDiagnosticEvents.map(\.kind))
        let diagnosticText = store.canonicalReadEffectiveCacheDiagnosticEvents.map(\.diagnosticsSummary).joined(separator: "\n")
        #expect(diagnosticKinds.contains(.canonicalReadEffectiveCacheHit))
        #expect(diagnosticKinds.contains(.canonicalReadEffectiveCacheMiss))
        #expect(diagnosticKinds.contains(.canonicalReadEffectiveCacheInvalidated))
        #expect(diagnosticKinds.contains(.canonicalReadEffectiveCacheRebuilt))
        #expect(diagnosticKinds.contains(.canonicalReadEffectiveTreeRebuilt))
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
    @Test func macStudyLibraryStoreFallsBackToLegacyOnDivergentCanonicalRead() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalReadRuntimeMacStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyLibraryStore(rootURL: root, listenForInboxChanges: false)
        try await store.applySyncManifest(Self.studyManifest(title: "Mac Legacy Store Lecture"), localDeviceID: "mac-local")

        let divergent = MacCanonicalReadRuntimeAdapter.makeCanonicalManifest(Self.studyManifest(title: "Mac Canonical Divergent"))
        let result = store.configureCanonicalReadRuntime(
            configuration: .explicitGuardedCanonicalRead(),
            canonicalManifest: divergent,
            syncRunID: "mac-store-read-divergent"
        )

        #expect(result.returnedSource == .legacy)
        #expect(store.canonicalReadRuntimeReturnedSource == .legacy)
        #expect(store.effectiveStudyItems.first?.title == "Mac Legacy Store Lecture")
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
            nodeID: "mac-test",
            metadata: metadata,
            artifacts: [audio, note],
            syncState: .synced,
            transferState: .completed
        )
        return CanonicalManifest.make(
            node: CanonicalNode(nodeID: "mac-test", platform: "Mac", capabilities: [.recordingMetadata, .audioArtifact, .noteArtifact]),
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

    private static func studyManifest(
        title: String,
        generatedAt: Date = Date(timeIntervalSince1970: 3_000)
    ) -> StudyLibrarySyncManifest {
        StudyLibrarySyncManifest.make(
            deviceID: "mac-test",
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
                    modifiedByDeviceID: "mac-test"
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
                    sourceDeviceID: "mac-test",
                    artifactRefs: nil,
                    audioLogicalPathToken: "audio/recording-01.m4a"
                )
            ]
        )
    }
}

private final class MacRecordingReadSideSeamSpy: MacRecordingMetadataReadSideSeamReading, @unchecked Sendable {
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
        return MacRecordingMetadataReadSideSeam(configuration: configuration).read(
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
