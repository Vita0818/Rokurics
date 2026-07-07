//
//  CanonicalV8RecordingMetadataNoCommitTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/3.
//

import Foundation
import Testing
@testable import Rokurics

@MainActor
struct CanonicalV8RecordingMetadataNoCommitTests {
    @Test func v8CutoverSeamConfigIsDisabledByDefaultAndOnlyAllowsNoCommit() {
        let disabled = CanonicalCutoverAppSeamConfiguration()
        #expect(disabled.isEnabled == false)
        #expect(disabled.effectiveMode == .disabled)

        let commit = CanonicalRecordingMetadataNoCommitRunner().evaluateGate(
            configuration: .enabled(mode: .guardedExecuteCommit, evidence: RecordingMetadataCutoverTestSupport.evidence()),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [Self.noCommitCandidate()],
            trigger: .periodic
        )
        let production = CanonicalRecordingMetadataNoCommitRunner().evaluateGate(
            configuration: .enabled(mode: .productionExecute, evidence: RecordingMetadataCutoverTestSupport.evidence()),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [Self.noCommitCandidate()],
            trigger: .periodic
        )
        let canary = CanonicalRecordingMetadataNoCommitRunner().evaluateGate(
            configuration: .enabled(mode: .canaryCommit, evidence: RecordingMetadataCutoverTestSupport.evidence()),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [Self.noCommitCandidate()],
            trigger: .periodic
        )
        let unsupportedDomain = CanonicalRecordingMetadataNoCommitRunner().evaluateGate(
            configuration: .enabled(domain: .generatedArtifacts, evidence: RecordingMetadataCutoverTestSupport.evidence()),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [Self.noCommitCandidate()],
            trigger: .periodic
        )

        #expect(commit.failures.contains(.guardedExecuteCommitDenied))
        #expect(production.failures.contains(.productionExecuteDenied))
        #expect(canary.failures.contains(.canaryCommitDenied))
        #expect(unsupportedDomain.failures.contains(.unsupportedDomain))
    }

    @Test func v8RejectsViewRefreshAndRetryDrainerTriggers() {
        let config = CanonicalCutoverAppSeamConfiguration.enabled(evidence: RecordingMetadataCutoverTestSupport.evidence())
        let viewRefresh = CanonicalRecordingMetadataNoCommitRunner().evaluateGate(
            configuration: config,
            evidence: config.evidence,
            candidates: [Self.noCommitCandidate()],
            trigger: .viewRefresh
        )
        let retryDrainer = CanonicalRecordingMetadataNoCommitRunner().evaluateGate(
            configuration: config,
            evidence: config.evidence,
            candidates: [Self.noCommitCandidate()],
            trigger: .retryDrainer
        )

        #expect(viewRefresh.failures.contains(.viewRefreshTriggerDenied))
        #expect(retryDrainer.failures.contains(.retryDrainerFreshMetadataDenied))
    }

    @Test func noCommitRunnerDoesNotCommitOrSuppressLegacyDuplicates() {
        let result = Self.runNoCommit(candidates: [Self.noCommitCandidate()])

        #expect(result.gate.allowed)
        #expect(result.productionCommitSuppressed)
        #expect(result.legacyFallbackPreserved)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.diagnostics.contains { $0.kind == .canonicalV8RecordingMetadataNoCommitProductionCommitSuppressed })
        #expect(result.diagnostics.contains { $0.kind == .canonicalV8RecordingMetadataNoCommitLegacyFallbackPreserved })
        #expect(result.diagnostics.contains { $0.kind == .canonicalV8NoCommitCommitSuppressed })
        #expect(result.diagnostics.contains { $0.kind == .canonicalV8NoCommitLegacyDuplicatePreserved })
        #expect(result.evidenceReport.productionCommitSuppressed)
        #expect(result.evidenceReport.legacyDuplicateSuppressed == false)
    }

    @Test func equivalentMetadataApplyAndSendReturnEquivalent() throws {
        let applyResult = Self.runNoCommit(candidates: [Self.noCommitCandidate()])
        let sendResult = Self.runNoCommit(candidates: [Self.noCommitCandidate(kind: .recordingMetadataSend, legacyDirection: .send, includeLegacyPayloadEvidence: true)])

        #expect(try #require(applyResult.candidateResults.first).equivalence.status == .equivalent)
        #expect(try #require(sendResult.candidateResults.first).equivalence.status == .equivalent)
        #expect(sendResult.candidateResults.first?.equivalence.routePath == "/sync/apply-metadata")
    }

    @Test func canonicalMoreAggressiveAndInsufficientEvidenceAreBlockingButNonfatal() throws {
        let aggressive = Self.runNoCommit(candidates: [Self.noCommitCandidate(legacyDirection: .none)])
        let insufficientEvidence = CanonicalRecordingMetadataNoCommitRunner().run(
            configuration: .enabled(),
            candidates: [Self.noCommitCandidate()],
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v8-insufficient-evidence",
            executor: IPhoneRecordingMetadataNoCommitExecutor(stagingRootURL: Self.makeScratchRoot("IPhoneV8NoCommitInsufficient"))
        )

        #expect(try #require(aggressive.candidateResults.first).equivalence.status == .canonicalMoreAggressive)
        #expect(aggressive.nonfatalFailureCount == 1)
        #expect(insufficientEvidence.gate.failures.contains(.insufficientEvidence))
        #expect(insufficientEvidence.diagnostics.contains { $0.kind == .canonicalV8RecordingMetadataNoCommitInsufficientEvidence })
    }

    @Test func iphoneExecutorWritesOnlyStagingRoot() throws {
        let rootURL = Self.makeScratchRoot("IPhoneV8NoCommitStaging")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let executor = IPhoneRecordingMetadataNoCommitExecutor(stagingRootURL: rootURL)
        let staging = executor.stageNoCommit(Self.noCommitCandidate())

        let logicalPath = try #require(staging.stagedLogicalPathToken)
        #expect(staging.staged)
        #expect(staging.wroteOnlyStagingRoot)
        #expect(staging.stagingEvidence?.lifecycleStatus == .created)
        #expect(staging.cleanupEvidence?.status == .removed)
        #expect(staging.wroteProductionStore == false)
        #expect(staging.calledApplySyncManifest == false)
        #expect(staging.sentNetworkRequest == false)
        #expect(staging.suppressedLegacyDuplicate == false)
        #expect(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(logicalPath).path) == false)
        #expect(FileManager.default.fileExists(atPath: rootURL.path) == false)
    }

    @Test func iphoneExecutorCanRetainExplicitStagingRootForDiagnostics() throws {
        let rootURL = Self.makeScratchRoot("IPhoneV8NoCommitRetainedStaging")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let executor = IPhoneRecordingMetadataNoCommitExecutor(
            stagingRootURL: rootURL,
            cleanupPolicy: .retainForDiagnostics(maxAge: 3_600, maxCount: 4, maxBytes: 1_000_000)
        )
        let staging = executor.stageNoCommit(Self.noCommitCandidate())

        let logicalPath = try #require(staging.stagedLogicalPathToken)
        #expect(staging.staged)
        #expect(staging.cleanupEvidence?.status == .retainedForDiagnostics)
        #expect(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(logicalPath).path))
    }

    @Test func diagnosticsAreRedactedAndUseHashPrefixesOnly() {
        let result = Self.runNoCommit(candidates: [Self.noCommitCandidate(kind: .recordingMetadataSend, legacyDirection: .send, includeLegacyPayloadEvidence: true)])
        let summaries = result.diagnostics.map(\.diagnosticsSummary).joined(separator: "\n")

        #expect(summaries.contains("/Users/") == false)
        #expect(summaries.contains("/private/") == false)
        #expect(summaries.contains(String(repeating: "a", count: 64)) == false)
        #expect(summaries.contains("/sync/apply-metadata"))
    }

    @Test func performTickDefaultV8SeamRecordsNoDiagnostics() async throws {
        let harness = try Self.makeHarness(peerInventory: Self.emptyInventory(deviceID: "mac-01", platform: .Mac))
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 2_000),
            bypassBackoff: true,
            syncRunID: "v8-disabled"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(entries.contains { $0.phase == "canonicalV8CutoverSeamStarted" } == false)
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    @Test func performTickEnabledV8SeamRecordsNoCommitReportWithoutChangingLegacyPlan() async throws {
        let harness = try Self.makeHarness(
            peerInventory: Self.emptyInventory(deviceID: "mac-01", platform: .Mac),
            v8Configuration: .enabled()
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 2_100),
            bypassBackoff: true,
            syncRunID: "v8-enabled"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(plan?.uploadMetadataActions.isEmpty == true)
        #expect(plan?.downloadMetadataActions.isEmpty == true)
        #expect(plan?.uploadRecordingAudioActions.isEmpty == true)
        #expect(entries.contains { $0.phase == "canonicalV8CutoverSeamStarted" })
        #expect(entries.contains { $0.phase == "canonicalV8RecordingMetadataNoCommitInsufficientEvidence" })
        #expect(entries.contains { $0.phase == "canonicalV8RecordingMetadataNoCommitProductionCommitSuppressed" } == false)
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    private struct Harness {
        let rootURL: URL
        let diagnosticsStore: ConnectionDiagnosticsStore
        let client: V8FakeLocalNetworkSyncClient
        let engine: LocalNetworkSyncEngine
    }

    private static func makeHarness(
        peerInventory: LocalNetworkSyncInventory,
        v8Configuration: CanonicalCutoverAppSeamConfiguration = .disabled
    ) throws -> Harness {
        let rootURL = Self.makeScratchRoot("IPhoneV8NoCommitSeam")
        let audioStore = AudioFileStore(rootDirectoryURL: rootURL)
        try audioStore.ensureStorageDirectories()
        let studyStore = StudyLibraryStore(rootURL: rootURL.appendingPathComponent("Study", isDirectory: true), audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL.appendingPathComponent("Diagnostics", isDirectory: true))
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL.appendingPathComponent("SyncState", isDirectory: true))
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let client = V8FakeLocalNetworkSyncClient(peerInventory: peerInventory)
        let engine = LocalNetworkSyncEngine(
            connectionStore: V8FakeSecureMacConnectionSnapshotProvider(snapshot: Self.pairedSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore,
            client: client,
            stateStore: stateStore,
            diagnosticsStore: diagnosticsStore,
            canonicalV8CutoverAppSeamConfiguration: v8Configuration
        )
        return Harness(rootURL: rootURL, diagnosticsStore: diagnosticsStore, client: client, engine: engine)
    }

    private static func runNoCommit(
        candidates: [CanonicalRecordingMetadataNoCommitCandidate]
    ) -> CanonicalRecordingMetadataNoCommitResult {
        let rootURL = Self.makeScratchRoot("IPhoneV8NoCommitRunner")
        return CanonicalRecordingMetadataNoCommitRunner().run(
            configuration: .enabled(evidence: RecordingMetadataCutoverTestSupport.evidence()),
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v8-no-commit",
            executor: IPhoneRecordingMetadataNoCommitExecutor(stagingRootURL: rootURL)
        )
    }

    private static func noCommitCandidate(
        kind: CanonicalApplyActionKind = .recordingMetadataApply,
        legacyDirection: CanonicalRecordingMetadataNoCommitDirection = .apply,
        includeLegacyPayloadEvidence: Bool = false
    ) -> CanonicalRecordingMetadataNoCommitCandidate {
        let cutover = kind == .recordingMetadataSend
            ? Self.sendCutoverCandidate()
            : RecordingMetadataCutoverTestSupport.candidate(kind: kind)
        var candidate = CanonicalRecordingMetadataNoCommitCandidate(
            cutoverCandidate: cutover,
            legacyDirection: legacyDirection,
            legacyObjectID: cutover.objectID,
            expectedRoutePath: kind == .recordingMetadataSend ? "/sync/apply-metadata" : nil
        )
        guard includeLegacyPayloadEvidence else {
            return candidate
        }
        let bytes = CanonicalRecordingMetadataNoCommitPayloadSummary(candidate: candidate).encodedBytes()
        candidate = CanonicalRecordingMetadataNoCommitCandidate(
            cutoverCandidate: cutover,
            legacyDirection: legacyDirection,
            legacyObjectID: cutover.objectID,
            legacyPayloadByteCount: bytes.count,
            legacyPayloadHashPrefix: CanonicalTransportEnvelope.hash(bytes).value,
            expectedRoutePath: "/sync/apply-metadata"
        )
        return candidate
    }

    private static func pairedSnapshot() -> SecureMacConnectionSnapshot {
        SecureMacConnectionSnapshot(
            macHost: "127.0.0.1",
            macPort: 8787,
            macFingerprint: String(repeating: "a", count: 64),
            macName: "Rokurics Mac",
            macModel: "Mac",
            deviceID: "mac-01",
            sharedSecretBase64URL: Data("v8-no-commit-secret".utf8).base64URLEncodedString(),
            pairedAt: "2026-06-03T00:00:00Z"
        )
    }

    private static func sendCutoverCandidate(id: String = "recording-01") -> CanonicalRecordingMetadataCutoverCandidate {
        let local = CanonicalProductionTestFixtures.recording(
            id: id,
            title: "LocalNewer",
            modifiedAt: CanonicalProductionTestFixtures.date(2_200)
        )
        let peer = CanonicalProductionTestFixtures.recording(
            id: id,
            title: "PeerOlder",
            modifiedAt: CanonicalProductionTestFixtures.date(2_100)
        )
        return CanonicalRecordingMetadataCutoverCandidate(
            action: CanonicalApplyAction(
                kind: .recordingMetadataSend,
                source: .local,
                target: CanonicalApplyTarget(objectID: id),
                bridgeHint: .legacyMetadataManifestSend,
                reason: CanonicalApplyActionKind.recordingMetadataSend.rawValue
            ),
            localObject: local,
            peerObject: peer,
            rollbackCheckpointID: "recording-metadata-checkpoint-\(id)",
            unresolvedConflict: false
        )
    }

    private static func emptyInventory(deviceID: String, platform: LocalNetworkSyncPlatform) -> LocalNetworkSyncInventory {
        LocalNetworkSyncInventory.make(device: Self.device(deviceID: deviceID, platform: platform))
    }

    private static func device(deviceID: String, platform: LocalNetworkSyncPlatform) -> LocalNetworkSyncDeviceSection {
        LocalNetworkSyncDeviceSection(
            deviceID: deviceID,
            deviceName: platform.rawValue,
            platform: platform,
            generatedAt: Date(timeIntervalSince1970: 1_000),
            lastKnownPeerRevision: nil,
            appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
        )
    }

    private static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

@MainActor
private final class V8FakeSecureMacConnectionSnapshotProvider: SecureMacConnectionSnapshotProviding, SecureMacConnectionIntentProviding {
    var snapshot: SecureMacConnectionSnapshot
    var userConnectionIntent: UserConnectionIntent = .wantsConnected

    init(snapshot: SecureMacConnectionSnapshot) {
        self.snapshot = snapshot
    }
}

private final class V8FakeLocalNetworkSyncClient: LocalNetworkSyncClientProtocol {
    let peerInventory: LocalNetworkSyncInventory
    private(set) var inventoryRequestCount = 0
    private(set) var applyMetadataCount = 0
    private(set) var artifactRequestCount = 0
    private(set) var artifactPutCount = 0

    init(peerInventory: LocalNetworkSyncInventory) {
        self.peerInventory = peerInventory
    }

    func sendDeviceStatus(
        settings: SecureMacConnectionSnapshot,
        statusRequest: DeviceStatusRequest
    ) async throws -> DeviceStatusResponse {
        DeviceStatusResponse(ok: true, status: nil, syncState: nil, error: nil)
    }

    func fetchLocalNetworkSyncInventory(
        settings: SecureMacConnectionSnapshot,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String?
    ) async throws -> LocalNetworkSyncInventoryResponse {
        inventoryRequestCount += 1
        return LocalNetworkSyncInventoryResponse(ok: true, inventory: peerInventory, error: nil)
    }

    func sendLocalNetworkSyncStartSignal(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartRequest
    ) async throws -> LocalNetworkSyncStartResponse {
        LocalNetworkSyncStartResponse(
            ok: true,
            syncRunID: request.syncRunID,
            peerDeviceID: "mac-01",
            ackAt: Date(),
            disposition: "ack",
            error: nil
        )
    }

    func sendLocalNetworkSyncStartAck(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartAckRequest
    ) async throws -> LocalNetworkSyncStartAckResponse {
        LocalNetworkSyncStartAckResponse(
            ok: true,
            syncRunID: request.syncRunID,
            peerDeviceID: "mac-01",
            ackReceivedAt: Date(),
            error: nil
        )
    }

    func applyLocalNetworkSyncMetadata(
        settings: SecureMacConnectionSnapshot,
        manifest: StudyLibrarySyncManifest
    ) async throws -> StudyLibrarySyncManifestResponse {
        applyMetadataCount += 1
        return StudyLibrarySyncManifestResponse(
            ok: true,
            manifest: nil,
            syncState: nil,
            deviceStatus: nil,
            applyResult: StudyLibrarySyncApplyResult(),
            baseCommitID: nil,
            newCommitID: nil,
            remoteChanges: nil,
            rejectedChanges: nil,
            error: nil
        )
    }

    func requestLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactRequest
    ) async throws -> LocalNetworkSyncArtifactResponse {
        artifactRequestCount += 1
        return LocalNetworkSyncArtifactResponse(
            ok: false,
            artifactID: nil,
            kind: nil,
            checksum: nil,
            size: nil,
            logicalPathToken: nil,
            dataBase64: nil,
            error: "not_expected"
        )
    }

    func fetchLocalNetworkSyncArtifactStatus(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactStatusRequest
    ) async throws -> LocalNetworkSyncArtifactStatusResponse {
        LocalNetworkSyncArtifactStatusResponse(
            ok: true,
            artifactID: request.artifactID,
            checksum: request.checksum,
            size: request.size,
            confirmedBytes: 0,
            nextOffset: 0,
            state: .pending,
            error: nil
        )
    }

    func putLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactPutRequest
    ) async throws -> LocalNetworkSyncArtifactPutResponse {
        artifactPutCount += 1
        return LocalNetworkSyncArtifactPutResponse(
            ok: true,
            artifactID: request.artifactID,
            disposition: "acceptedNew",
            checksum: request.checksum,
            size: request.size,
            confirmedBytes: request.size,
            error: nil
        )
    }
}
