//
//  CanonicalLibraryMetadataLandingTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/6.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalLibraryMetadataLandingTests {
    @Test func macDebugPilotDefaultsDisabled() {
        let configuration = CanonicalLibraryMetadataDebugPilotConfiguration.disabled

        #expect(configuration.mode == .disabled)
        #expect(configuration.rootMode == .disabled)
        #expect(configuration.policy.domain == .libraryMetadata)
        #expect(configuration.policy.canaryMaxObjectsPerSyncRun == 1)
        #expect(configuration.policy.runtimeSwitchEnabled == false)
        #expect(configuration.allowProductionRootWrites == false)
    }

    @Test func macRealDeviceDebugPilotUserDefaultsDefaultOff() {
        let defaults = Self.makeIsolatedDefaults("mac-default-off")

        #expect(CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotStoredMode(userDefaults: defaults) == CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotOffMode)

        let runtime = CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotRuntime(
            userDefaults: defaults,
            productionRootURL: nil
        )
        #expect(runtime.configuration.mode == .disabled)
        #expect(runtime.executor == nil)
    }

    @Test func macRealDeviceDebugPilotDiagnosticsOnlyMapsToConfigWithoutExecutor() {
        let defaults = Self.makeIsolatedDefaults("mac-diagnostics")
        CanonicalLibraryMetadataDebugPilotConfiguration.setMacRealDeviceDebugPilotMode(
            CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotDiagnosticsOnlyMode,
            userDefaults: defaults
        )

        let runtime = CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotRuntime(
            userDefaults: defaults,
            productionRootURL: nil
        )

        #expect(runtime.configuration.mode == .diagnosticsOnly)
        #expect(runtime.configuration.explicitInternalDebugConfiguration)
        #expect(runtime.configuration.allowProductionRootWrites == false)
        #expect(runtime.executor == nil)
    }

    @Test func macRealDeviceDebugPilotTestRootModesInjectBootstrapExecutorOnlyForTestRoot() {
        let armDefaults = Self.makeIsolatedDefaults("mac-arm-test-root")
        CanonicalLibraryMetadataDebugPilotConfiguration.setMacRealDeviceDebugPilotMode(
            CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotArmTestRootN1Mode,
            userDefaults: armDefaults
        )
        let armed = CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotRuntime(
            userDefaults: armDefaults,
            productionRootURL: nil
        )

        #expect(armed.configuration.mode == .armN1Canary)
        #expect(armed.configuration.rootMode == .testRoot)
        #expect(armed.configuration.allowProductionRootWrites == false)
        #expect(armed.configuration.evidence.testRootUsed)
        #expect(armed.configuration.evidence.applyPortMode == .testRootBound)
        #expect(armed.executor != nil)

        let executeDefaults = Self.makeIsolatedDefaults("mac-execute-test-root")
        CanonicalLibraryMetadataDebugPilotConfiguration.setMacRealDeviceDebugPilotMode(
            CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotExecuteTestRootN1Mode,
            userDefaults: executeDefaults
        )
        let execute = CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotRuntime(
            userDefaults: executeDefaults,
            productionRootURL: nil
        )

        #expect(execute.configuration.mode == .executeN1Canary)
        #expect(execute.configuration.rootMode == .testRoot)
        #expect(execute.configuration.allowProductionRootWrites == false)
        #expect(execute.configuration.evidence.testRootUsed)
        #expect(execute.executor != nil)
    }

    @Test func macRealDeviceDebugPilotProductionRootRequiresConfirmationAndSafeRoot() {
        let unconfirmedDefaults = Self.makeIsolatedDefaults("mac-production-unconfirmed")
        CanonicalLibraryMetadataDebugPilotConfiguration.setMacRealDeviceDebugPilotMode(
            CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotExecuteProductionRootN1Mode,
            userDefaults: unconfirmedDefaults
        )
        let unconfirmed = CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotRuntime(
            userDefaults: unconfirmedDefaults,
            productionRootURL: FileManager.default.temporaryDirectory
        )
        #expect(unconfirmed.configuration.mode == .disabled)
        #expect(unconfirmed.executor == nil)

        let noRootDefaults = Self.makeIsolatedDefaults("mac-production-no-root")
        CanonicalLibraryMetadataDebugPilotConfiguration.setMacRealDeviceDebugPilotMode(
            CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotExecuteProductionRootN1Mode,
            userDefaults: noRootDefaults
        )
        noRootDefaults.set(true, forKey: CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotProductionRootConfirmedKey)
        let noRoot = CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotRuntime(
            userDefaults: noRootDefaults,
            productionRootURL: nil
        )
        #expect(noRoot.configuration.mode == .disabled)
        #expect(noRoot.executor == nil)
    }

    @Test func macRealDeviceDebugPilotConfirmedProductionRootAllowsWritesOnlyInProductionMode() {
        let defaults = Self.makeIsolatedDefaults("mac-production-confirmed")
        let rootURL = MacLibraryMetadataCutoverTestSupport.makeScratchRoot("MacRealDevicePilotProductionRoot")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        CanonicalLibraryMetadataDebugPilotConfiguration.setMacRealDeviceDebugPilotMode(
            CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotExecuteProductionRootN1Mode,
            userDefaults: defaults
        )
        defaults.set(true, forKey: CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotProductionRootConfirmedKey)

        let runtime = CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotRuntime(
            userDefaults: defaults,
            productionRootURL: rootURL
        )

        #expect(runtime.configuration.mode == .executeN1Canary)
        #expect(runtime.configuration.rootMode == .productionRootExplicit)
        #expect(runtime.configuration.allowProductionRootWrites)
        #expect(runtime.configuration.evidence.applyPortMode == .productionRootBound)
        #expect(runtime.executor != nil)
    }

    @Test func macRealDeviceDebugPilotDiagnosticPathTextUsesHomeShorthandOnly() {
        let text = CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDiagnosticsPathText

        #expect(text.contains("~/Library/Application Support/Rokurics*/Sync/Diagnostics/connection-diagnostics.jsonl"))
        #expect(text.contains("~/Library/Application Support/Rokurics*/Sync/Diagnostics/canonical-shadow.jsonl"))
        #expect(text.contains("/Users/") == false)
        #expect(text.contains(NSHomeDirectory()) == false)
    }

    @Test func macFingerprintLogOutputIsRedacted() {
        let fullFingerprint = String(repeating: "abcdef0123456789", count: 4)
        let redacted = MacIdentityManager.redactedFingerprintForLog(fullFingerprint)

        #expect(redacted == "\(fullFingerprint.prefix(12))...")
        #expect(redacted.contains(fullFingerprint) == false)
        #expect(redacted.count < fullFingerprint.count)
    }

    @Test func macFreezeGuardKeepsOnlyLibraryMetadataActive() {
        let result = CanonicalMigrationLandingFreeze().evaluate(matrix: .defaultV813())

        #expect(result.allowed)
        #expect(result.activePilotDomain == .libraryMetadata)
        #expect(result.otherDomainsStaticOnly)
    }

    @Test func macDiagnosticsOnlyProducesSafeSummaryWithoutCandidateOrCommit() async {
        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: .diagnosticsOnly(evidence: MacLibraryMetadataCutoverTestSupport.evidence()),
            candidates: [MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            trigger: .manual,
            nodeRole: .mac,
            syncRunID: "mac-v830-diagnostics",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: nil
        )
        let summary = CanonicalLibraryMetadataPilotDiagnosticExporter().export(
            result: result,
            nodeRole: .mac
        )

        #expect(result.report.status == .diagnosticsOnly)
        #expect(result.injectionResult == nil)
        #expect(result.report.candidate.selected == false)
        #expect(result.report.commitAttempted == false)
        #expect(result.report.otherDomainsStaticOnly)
        #expect(result.report.runtimeSwitchEnabled == false)
        #expect(summary.freezeStatus == "allowed")
        #expect(summary.diagnosticsRedacted)
        #expect(summary.canaryAttempted == false)
    }

    @Test func macArmN1ProducesReadinessOnlyWithoutExecutorOrCommit() async {
        let configuration = CanonicalLibraryMetadataDebugPilotConfiguration.armTestRootN1(
            token: MacLibraryMetadataCutoverTestSupport.token(),
            evidence: MacLibraryMetadataCutoverTestSupport.evidence()
        )
        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: configuration,
            candidates: [MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            trigger: .manual,
            nodeRole: .mac,
            syncRunID: "mac-v830-arm",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: nil
        )

        #expect(result.report.status == .armed)
        #expect(result.report.candidate.selected)
        #expect(result.report.commitAttempted == false)
        #expect(result.injectionResult?.executorInjected == false)
        #expect(result.injectionResult?.applyPortInjected == false)
        #expect(result.report.readSideEquivalent)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataLandingArmed })
    }

    @Test func macExecuteN1CommitsExactlyOneSafeFolderCandidateInTestRoot() async throws {
        let rootURL = MacLibraryMetadataCutoverTestSupport.makeScratchRoot("MacV829LandingRoot")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pair = MacLibraryMetadataCutoverTestSupport.folderCandidate()
        let applyPort = try MacLibraryMetadataRealApplyPort(testRootURL: rootURL)
        try await applyPort.setRootBoundLibraryMetadataPayload(candidate: pair.candidate, metadataBytes: pair.bytes)
        let executor = MacLibraryMetadataCutoverExecutor(applyPort: applyPort)
        let configuration = CanonicalLibraryMetadataDebugPilotConfiguration.executeTestRootN1(
            token: MacLibraryMetadataCutoverTestSupport.token(),
            evidence: MacLibraryMetadataCutoverTestSupport.evidence()
        )

        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: configuration,
            candidates: [pair.candidate],
            trigger: .manual,
            nodeRole: .mac,
            syncRunID: "mac-v829-execute-test-root",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: executor
        )
        let committedBytes = try await applyPort.rootBoundLibraryMetadataBytes(
            objectID: pair.candidate.objectID,
            objectKind: .folder,
            domain: .folderMetadata
        )

        #expect(result.report.status == .executedSucceeded)
        #expect(result.report.commitAttempted)
        #expect(result.report.commitSucceeded)
        #expect(result.report.duplicateSuppressed)
        #expect(result.report.readSideEquivalent)
        #expect(result.report.uiReadPathSwitched == false)
        #expect(result.report.generatedArtifactsStaticOnly)
        #expect(result.report.tombstoneConflictStaticOnly)
        #expect(result.report.audioUploadStaticOnly)
        #expect(committedBytes == pair.bytes)
    }

    @Test func macPeerSnapshotMissingBlocksServerInventoryPilot() async throws {
        let harness = try Self.makeHarness(
            configuration: .executeTestRootN1(
                token: MacLibraryMetadataCutoverTestSupport.token(),
                evidence: MacLibraryMetadataCutoverTestSupport.evidence()
            )
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            Self.pairedDevice(),
            syncRunID: "mac-v829-peer-missing"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(events.contains { $0.phase == "canonicalLibraryMetadataLandingConfigEvaluated" })
        #expect(events.contains { $0.phase == "canonicalLibraryMetadataLandingBlocked" })
        #expect(events.contains { $0.phase == "canonicalLibraryMetadataLandingLegacyFallbackUsed" })
        #expect(events.contains { $0.phase == "canonicalLibraryMetadataLandingReportBuilt" })
        #expect(events.contains { $0.phase == "canonicalLibraryMetadataLandingCommitStarted" } == false)
    }

    @Test func macProductionRootDefaultDisabledBlocksExecution() async {
        var evidence = MacLibraryMetadataCutoverTestSupport.evidence()
        evidence.applyPortMode = .productionRootDisabled
        evidence.testRootUsed = false
        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: .executeProductionRootN1(
                token: MacLibraryMetadataCutoverTestSupport.token(),
                evidence: evidence,
                allowProductionRootWrites: false
            ),
            candidates: [MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            trigger: .manual,
            nodeRole: .mac,
            syncRunID: "mac-v829-production-disabled",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: nil
        )

        #expect(result.report.status == .blocked)
        #expect(result.report.commitAttempted == false)
        #expect(result.report.blockers.contains(CanonicalLibraryMetadataRealCanaryBlocker.productionRootWritesDisabled.rawValue))
        #expect(result.report.blockers.contains(CanonicalLibraryMetadataRealCanaryBlocker.productionRootGuardMissing.rawValue))
        #expect(result.report.uiReadPathSwitched == false)
    }

    @Test func macAllowProductionRootWritesTrueStillRequiresV830TestRootEvidence() async {
        var evidence = MacLibraryMetadataCutoverTestSupport.evidence()
        evidence.applyPortMode = .productionRootBound
        evidence.testRootUsed = false
        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: .executeProductionRootN1(
                token: MacLibraryMetadataCutoverTestSupport.token(),
                evidence: evidence,
                allowProductionRootWrites: true
            ),
            candidates: [MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            trigger: .manual,
            nodeRole: .mac,
            syncRunID: "mac-v830-production-allow-true",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: nil
        )

        #expect(result.report.status == .blocked)
        #expect(result.report.commitAttempted == false)
        #expect(result.report.blockers.contains(CanonicalLibraryMetadataRealCanaryBlocker.testRootMissing.rawValue))
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataProductionRootGateBlocked })
    }

    @Test func macFreezeBlocksGeneratedArtifactsActivePilotForLanding() async {
        let matrix = CanonicalMigrationDomainMatrix.v824GeneratedArtifactsStagedCanary(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        )
        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: .executeTestRootN1(
                token: MacLibraryMetadataCutoverTestSupport.token(),
                evidence: MacLibraryMetadataCutoverTestSupport.evidence()
            ),
            matrix: matrix,
            candidates: [MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            trigger: .manual,
            nodeRole: .mac,
            syncRunID: "mac-v829-generated-active",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: nil
        )

        #expect(result.freezeResult.allowed == false)
        #expect(result.freezeResult.violations.contains(.nonLibraryMetadataActivePilot))
        #expect(result.freezeResult.violations.contains(.generatedArtifactsNotStaticOnly))
        #expect(result.report.commitAttempted == false)
    }

    private struct Harness {
        let rootURL: URL
        let server: SecureLocalHTTPSServer
        let recorder: V829MacDiagnosticRecorder
    }

    private static func makeHarness(
        configuration: CanonicalLibraryMetadataDebugPilotConfiguration
    ) throws -> Harness {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacV829LibraryMetadataLanding", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let recorder = V829MacDiagnosticRecorder()
        let recordingFileStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Recordings", isDirectory: true))
        let studyLibraryStore = StudyLibraryStore(
            rootURL: rootURL.appendingPathComponent("Study", isDirectory: true),
            recordingFileStore: recordingFileStore,
            listenForInboxChanges: false
        )
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityURL)
        let server = SecureLocalHTTPSServer(
            port: 0,
            identityManager: MacIdentityManager(securityDirectoryURL: securityURL, tlsKeyTagNamespace: "v829-library-\(UUID().uuidString)"),
            pairingManager: PairingManager(pairedDeviceStore: pairedDeviceStore),
            requestVerifier: RequestVerifier(pairedDeviceStore: pairedDeviceStore),
            receivedFileStore: ReceivedFileStore(),
            recordingFileStore: recordingFileStore,
            studyLibraryStore: studyLibraryStore,
            gitBackedStudyMetadataStore: nil,
            deviceConnectionStatusStore: DeviceConnectionStatusStore(rootURL: rootURL.appendingPathComponent("ConnectionStatus", isDirectory: true)),
            syncStateStore: StudyLibrarySyncStateStore(rootURL: rootURL.appendingPathComponent("SyncState", isDirectory: true)),
            canonicalLibraryMetadataDebugPilotConfiguration: configuration,
            onReady: {},
            onFailed: { _ in },
            onPairingChanged: {},
            onUploadAccepted: { _ in },
            onRecordingAccepted: { _, _ in },
            onConnectionDiagnostic: { recorder.record($0) },
            canonicalKernelMode: .canonicalApplyNoAudio
        )
        return Harness(rootURL: rootURL, server: server, recorder: recorder)
    }

    private static func pairedDevice() -> PairedDevice {
        PairedDevice(
            id: "iphone-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: Data("v829-library-secret".utf8).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
    }

    private static func makeIsolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "RokuricsMacTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class V829MacDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SecureConnectionDiagnosticEvent] = []

    func record(_ event: SecureConnectionDiagnosticEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [SecureConnectionDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
