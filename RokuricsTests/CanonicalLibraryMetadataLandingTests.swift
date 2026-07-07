//
//  CanonicalLibraryMetadataLandingTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/6.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalLibraryMetadataLandingTests {
    @Test func debugPilotDefaultsDisabledAndStrictLibraryMetadataN1() {
        let configuration = CanonicalLibraryMetadataDebugPilotConfiguration.disabled

        #expect(configuration.mode == .disabled)
        #expect(configuration.rootMode == .disabled)
        #expect(configuration.policy.domain == .libraryMetadata)
        #expect(configuration.policy.canaryMaxObjectsPerSyncRun == 1)
        #expect(configuration.policy.isStrictLibraryMetadataN1)
        #expect(configuration.explicitInternalDebugConfiguration == false)
        #expect(configuration.allowProductionRootWrites == false)
        #expect(configuration.policy.runtimeSwitchEnabled == false)
        #expect(configuration.policy.releaseDefaultEnabled == false)
    }

    @Test func iPhoneRealDeviceDebugPilotUserDefaultsDefaultOff() {
        let defaults = Self.makeIsolatedDefaults("iphone-default-off")

        #expect(CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotStoredMode(userDefaults: defaults) == CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotOffMode)

        let runtime = CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotRuntime(
            userDefaults: defaults,
            productionRootURL: nil
        )
        #expect(runtime.configuration.mode == .disabled)
        #expect(runtime.executor == nil)
    }

    @Test func iPhoneRealDeviceDebugPilotDiagnosticsOnlyMapsToConfigWithoutExecutor() {
        let defaults = Self.makeIsolatedDefaults("iphone-diagnostics")
        CanonicalLibraryMetadataDebugPilotConfiguration.setIPhoneRealDeviceDebugPilotMode(
            CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotDiagnosticsOnlyMode,
            userDefaults: defaults
        )

        let runtime = CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotRuntime(
            userDefaults: defaults,
            productionRootURL: nil
        )

        #expect(runtime.configuration.mode == .diagnosticsOnly)
        #expect(runtime.configuration.explicitInternalDebugConfiguration)
        #expect(runtime.configuration.allowProductionRootWrites == false)
        #expect(runtime.executor == nil)
    }

    @Test func iPhoneRealDeviceDebugPilotTestRootModesInjectBootstrapExecutorOnlyForTestRoot() {
        let armDefaults = Self.makeIsolatedDefaults("iphone-arm-test-root")
        CanonicalLibraryMetadataDebugPilotConfiguration.setIPhoneRealDeviceDebugPilotMode(
            CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotArmTestRootN1Mode,
            userDefaults: armDefaults
        )
        let armed = CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotRuntime(
            userDefaults: armDefaults,
            productionRootURL: nil
        )

        #expect(armed.configuration.mode == .armN1Canary)
        #expect(armed.configuration.rootMode == .testRoot)
        #expect(armed.configuration.allowProductionRootWrites == false)
        #expect(armed.configuration.evidence.testRootUsed)
        #expect(armed.configuration.evidence.applyPortMode == .testRootBound)
        #expect(armed.executor != nil)

        let executeDefaults = Self.makeIsolatedDefaults("iphone-execute-test-root")
        CanonicalLibraryMetadataDebugPilotConfiguration.setIPhoneRealDeviceDebugPilotMode(
            CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotExecuteTestRootN1Mode,
            userDefaults: executeDefaults
        )
        let execute = CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotRuntime(
            userDefaults: executeDefaults,
            productionRootURL: nil
        )

        #expect(execute.configuration.mode == .executeN1Canary)
        #expect(execute.configuration.rootMode == .testRoot)
        #expect(execute.configuration.allowProductionRootWrites == false)
        #expect(execute.configuration.evidence.testRootUsed)
        #expect(execute.executor != nil)
    }

    @Test func iPhoneRealDeviceDebugPilotProductionRootRequiresConfirmationAndSafeRoot() {
        let unconfirmedDefaults = Self.makeIsolatedDefaults("iphone-production-unconfirmed")
        CanonicalLibraryMetadataDebugPilotConfiguration.setIPhoneRealDeviceDebugPilotMode(
            CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotExecuteProductionRootN1Mode,
            userDefaults: unconfirmedDefaults
        )
        let unconfirmed = CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotRuntime(
            userDefaults: unconfirmedDefaults,
            productionRootURL: FileManager.default.temporaryDirectory
        )
        #expect(unconfirmed.configuration.mode == .disabled)
        #expect(unconfirmed.executor == nil)

        let noRootDefaults = Self.makeIsolatedDefaults("iphone-production-no-root")
        CanonicalLibraryMetadataDebugPilotConfiguration.setIPhoneRealDeviceDebugPilotMode(
            CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotExecuteProductionRootN1Mode,
            userDefaults: noRootDefaults
        )
        noRootDefaults.set(true, forKey: CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotProductionRootConfirmedKey)
        let noRoot = CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotRuntime(
            userDefaults: noRootDefaults,
            productionRootURL: nil
        )
        #expect(noRoot.configuration.mode == .disabled)
        #expect(noRoot.executor == nil)
    }

    @Test func iPhoneRealDeviceDebugPilotConfirmedProductionRootAllowsWritesOnlyInProductionMode() {
        let defaults = Self.makeIsolatedDefaults("iphone-production-confirmed")
        let rootURL = LibraryMetadataCutoverTestSupport.makeScratchRoot("IPhoneRealDevicePilotProductionRoot")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        CanonicalLibraryMetadataDebugPilotConfiguration.setIPhoneRealDeviceDebugPilotMode(
            CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotExecuteProductionRootN1Mode,
            userDefaults: defaults
        )
        defaults.set(true, forKey: CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotProductionRootConfirmedKey)

        let runtime = CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotRuntime(
            userDefaults: defaults,
            productionRootURL: rootURL
        )

        #expect(runtime.configuration.mode == .executeN1Canary)
        #expect(runtime.configuration.rootMode == .productionRootExplicit)
        #expect(runtime.configuration.allowProductionRootWrites)
        #expect(runtime.configuration.evidence.applyPortMode == .productionRootBound)
        #expect(runtime.executor != nil)
    }

    @Test func iPhoneRealDeviceDebugPilotDiagnosticPathTextIsRedacted() {
        let text = CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDiagnosticsPathText

        #expect(text.contains("Documents/Rokurics/Sync/Diagnostics/connection-diagnostics.jsonl"))
        #expect(text.contains("/Users/") == false)
        #expect(text.contains(NSHomeDirectory()) == false)
    }

    @Test func landingFreezeAllowsOnlyLibraryMetadataActivePilot() {
        let result = CanonicalMigrationLandingFreeze().evaluate(matrix: .defaultV813())

        #expect(result.allowed)
        #expect(result.activePilotDomain == .libraryMetadata)
        #expect(result.otherDomainsStaticOnly)
        #expect(result.runtimeSwitchEnabled == false)
        #expect(result.violations.isEmpty)
    }

    @Test func landingFreezeBlocksTombstoneConflictActivePilotForV829() {
        let matrix = CanonicalMigrationDomainMatrix.v827TombstoneConflictActivePilot(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
            generatedArtifactsTemplateCompleteOrObservationReady: true
        )
        let result = CanonicalMigrationLandingFreeze().evaluate(matrix: matrix)

        #expect(result.allowed == false)
        #expect(result.violations.contains(.nonLibraryMetadataActivePilot))
        #expect(result.violations.contains(.tombstoneConflictNotStaticOnly))
    }

    @Test func diagnosticsOnlyBuildsReportWithoutCommitOrDuplicateSuppression() async {
        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: .diagnosticsOnly(evidence: LibraryMetadataCutoverTestSupport.evidence()),
            candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            trigger: .manual,
            nodeRole: .iPhone,
            syncRunID: "v829-diagnostics-only",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: nil
        )

        #expect(result.report.status == .diagnosticsOnly)
        #expect(result.freezeResult.allowed)
        #expect(result.injectionResult == nil)
        #expect(result.report.activePilot == .libraryMetadata)
        #expect(result.report.candidate.selected == false)
        #expect(result.report.commitAttempted == false)
        #expect(result.report.duplicateSuppressed == false)
        #expect(result.report.uiReadPathSwitched == false)
        #expect(result.report.legacyReadPathPreserved)
        #expect(result.report.otherDomainsStaticOnly)
        #expect(result.report.runtimeSwitchEnabled == false)
        #expect(result.report.recommendation == .remainDisabled)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataLandingConfigEvaluated })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataLandingReportBuilt })
    }

    @Test func armedN1DoesNotCommitAndKeepsLegacyFallback() async {
        let configuration = CanonicalLibraryMetadataDebugPilotConfiguration.armTestRootN1(
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: LibraryMetadataCutoverTestSupport.evidence()
        )
        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: configuration,
            candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            trigger: .manual,
            nodeRole: .iPhone,
            syncRunID: "v829-armed",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: nil
        )

        #expect(result.report.status == .armed)
        #expect(result.report.candidate.selected)
        #expect(result.report.commitAttempted == false)
        #expect(result.report.duplicateSuppressed == false)
        #expect(result.injectionResult?.executorInjected == false)
        #expect(result.injectionResult?.applyPortInjected == false)
        #expect(result.report.legacyReadPathPreserved)
        #expect(result.report.readSideEquivalent)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataLandingArmed })
    }

    @Test func executeN1CommitsExactlyOneSafeFolderCandidateInTestRoot() async throws {
        let rootURL = LibraryMetadataCutoverTestSupport.makeScratchRoot("IPhoneV829LandingRoot")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pair = LibraryMetadataCutoverTestSupport.folderCandidate()
        let applyPort = try IPhoneLibraryMetadataRealApplyPort(testRootURL: rootURL)
        try await applyPort.setRootBoundLibraryMetadataPayload(candidate: pair.candidate, metadataBytes: pair.bytes)
        let executor = IPhoneLibraryMetadataCutoverExecutor(applyPort: applyPort)
        let configuration = CanonicalLibraryMetadataDebugPilotConfiguration.executeTestRootN1(
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: LibraryMetadataCutoverTestSupport.evidence()
        )

        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: configuration,
            candidates: [pair.candidate, LibraryMetadataCutoverTestSupport.resourceMoveCandidate()],
            trigger: .manual,
            nodeRole: .iPhone,
            syncRunID: "v829-execute-test-root",
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
        #expect(result.report.candidate.selected)
        #expect(result.report.candidate.kind == .folderRenameOrColorMetadata)
        #expect(result.report.candidate.metadataOnly)
        #expect(result.report.commitAttempted)
        #expect(result.report.commitSucceeded)
        #expect(result.report.rollbackAttempted == false)
        #expect(result.report.duplicateSuppressed)
        #expect(result.report.duplicateSuppressedCount == 1)
        #expect(result.report.readSideEquivalent)
        #expect(result.report.uiReadPathSwitched == false)
        #expect(result.report.recommendation == .runAnotherN1)
        #expect(result.cutoverResult?.commits.count == 1)
        #expect(committedBytes == pair.bytes)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataLandingCommitCompleted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataLandingDuplicateSuppressed })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataLandingReadSideEquivalent })
    }

    @Test func unsafeResourceMoveCandidateIsSkippedWithNoCommit() async {
        let configuration = CanonicalLibraryMetadataDebugPilotConfiguration.executeTestRootN1(
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: LibraryMetadataCutoverTestSupport.evidence()
        )

        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: configuration,
            candidates: [LibraryMetadataCutoverTestSupport.resourceMoveCandidate()],
            trigger: .manual,
            nodeRole: .iPhone,
            syncRunID: "v829-resource-move-blocked",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: LibraryMetadataCutoverTestSupport.FakeExecutor()
        )

        #expect(result.report.status == .unsafeCandidateSkipped)
        #expect(result.report.commitAttempted == false)
        #expect(result.report.candidate.resourceMoveAttempted)
        #expect(result.report.duplicateSuppressed == false)
        #expect(result.report.blockers.contains(CanonicalLibraryMetadataRealCanaryBlocker.unsafeCandidateSkipped.rawValue))
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataLandingNoEligibleCandidate })
    }

    @Test func productionRootExplicitRemainsBlockedWhenAllowProductionRootWritesFalse() async {
        var evidence = LibraryMetadataCutoverTestSupport.evidence()
        evidence.applyPortMode = .productionRootDisabled
        evidence.testRootUsed = false
        let configuration = CanonicalLibraryMetadataDebugPilotConfiguration.executeProductionRootN1(
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: evidence,
            allowProductionRootWrites: false
        )

        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: configuration,
            candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            trigger: .manual,
            nodeRole: .iPhone,
            syncRunID: "v829-production-disabled",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: LibraryMetadataCutoverTestSupport.FakeExecutor()
        )

        #expect(result.report.status == .blocked)
        #expect(result.report.commitAttempted == false)
        #expect(result.report.blockers.contains(CanonicalLibraryMetadataRealCanaryBlocker.productionRootWritesDisabled.rawValue))
        #expect(result.report.blockers.contains(CanonicalLibraryMetadataRealCanaryBlocker.productionRootGuardMissing.rawValue))
        #expect(result.report.runtimeSwitchEnabled == false)
    }

    @Test func allowProductionRootWritesTrueStillRequiresV830TestRootEvidence() async {
        var evidence = LibraryMetadataCutoverTestSupport.evidence()
        evidence.applyPortMode = .productionRootBound
        evidence.testRootUsed = false
        let configuration = CanonicalLibraryMetadataDebugPilotConfiguration.executeProductionRootN1(
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: evidence,
            allowProductionRootWrites: true
        )

        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: configuration,
            candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            trigger: .manual,
            nodeRole: .iPhone,
            syncRunID: "v830-production-allow-true",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: LibraryMetadataCutoverTestSupport.FakeExecutor()
        )

        #expect(result.report.status == .blocked)
        #expect(result.report.commitAttempted == false)
        #expect(result.report.blockers.contains(CanonicalLibraryMetadataRealCanaryBlocker.testRootMissing.rawValue))
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataProductionRootGateBlocked })
    }

    @Test func readSideDivergenceBlocksExecutionAndKeepsLegacyReadPath() async {
        var evidence = LibraryMetadataCutoverTestSupport.evidence()
        evidence.readSideParallelEquivalent = false
        let configuration = CanonicalLibraryMetadataDebugPilotConfiguration.executeTestRootN1(
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: evidence
        )

        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: configuration,
            candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            trigger: .manual,
            nodeRole: .iPhone,
            syncRunID: "v829-read-divergent",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: LibraryMetadataCutoverTestSupport.FakeExecutor()
        )

        #expect(result.report.status == .blocked)
        #expect(result.report.readSideEquivalent == false)
        #expect(result.report.readSideDivergenceCount == 1)
        #expect(result.report.uiReadPathSwitched == false)
        #expect(result.report.legacyReadPathPreserved)
        #expect(result.report.blockers.contains(CanonicalLibraryMetadataRealCanaryBlocker.readSideParallelDivergent.rawValue))
    }

    @Test func runtimeSwitchInPolicyTripsFreezeGuard() async {
        var policy = CanonicalLibraryMetadataDebugPilotPolicy.strictLibraryMetadataN1
        policy.runtimeSwitchEnabled = true
        let configuration = CanonicalLibraryMetadataDebugPilotConfiguration(
            mode: .executeN1Canary,
            rootMode: .testRoot,
            policy: policy,
            explicitInternalDebugConfiguration: true,
            evidence: LibraryMetadataCutoverTestSupport.evidence(),
            cutoverToken: LibraryMetadataCutoverTestSupport.token()
        )

        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: configuration,
            candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            trigger: .manual,
            nodeRole: .iPhone,
            syncRunID: "v829-runtime-switch",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: LibraryMetadataCutoverTestSupport.FakeExecutor()
        )

        #expect(result.freezeResult.allowed == false)
        #expect(result.freezeResult.violations.contains(.runtimeSwitchEnabled))
        #expect(result.report.status == .blocked)
        #expect(result.report.commitAttempted == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalMigrationLandingFreezeViolation })
    }

    @Test func landingFreezeDetectsV830MisconfigurationBoundaries() {
        let nonLibrary = CanonicalMigrationDomainMatrix.v824GeneratedArtifactsStagedCanary(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        )
        let readPath = matrixReplacing(.libraryMetadata) { policy in
            policy.readPathLegacy = false
        }
        let freeze = CanonicalMigrationLandingFreeze()

        let nonLibraryResult = freeze.evaluate(matrix: nonLibrary)
        let readPathResult = freeze.evaluate(matrix: readPath)
        let hardeningResult = freeze.evaluate(
            matrix: .defaultV813(),
            productionInjectionPresent: true,
            productionExecutorInjectedByDefault: true,
            productionRootWriteEnabledByDefault: true,
            legacyFallbackAvailable: false,
            canaryMaxObjectsPerSyncRun: 2,
            allEligibleEnabled: true,
            unsafeCandidateAllowed: true,
            resourceMoveAllowed: true,
            contentWriteAllowed: true,
            tombstoneDeleteAllowed: true
        )

        #expect(nonLibraryResult.allowed == false)
        #expect(nonLibraryResult.violations.contains(.nonLibraryMetadataActivePilot))
        #expect(readPathResult.allowed == false)
        #expect(readPathResult.violations.contains(.readPathNotLegacy))
        #expect(hardeningResult.allowed == false)
        #expect(hardeningResult.violations.contains(.productionExecutorInjectedByDefault))
        #expect(hardeningResult.violations.contains(.productionRootWriteEnabledByDefault))
        #expect(hardeningResult.violations.contains(.legacyFallbackUnavailable))
        #expect(hardeningResult.violations.contains(.canaryBudgetAboveOneDenied))
        #expect(hardeningResult.violations.contains(.allEligibleEnabled))
        #expect(hardeningResult.violations.contains(.unsafeCandidateAllowed))
        #expect(hardeningResult.violations.contains(.resourceMoveAllowed))
        #expect(hardeningResult.violations.contains(.contentWriteAllowed))
        #expect(hardeningResult.violations.contains(.tombstoneDeleteAllowed))
        #expect(hardeningResult.redacted)
    }

    @Test func safeDiagnosticExporterRedactsAndKeepsSummaryBounded() async {
        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: .diagnosticsOnly(evidence: LibraryMetadataCutoverTestSupport.evidence()),
            candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            trigger: .manual,
            nodeRole: .iPhone,
            syncRunID: "/Users/example/private/sync-run",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: nil
        )
        let summary = CanonicalLibraryMetadataPilotDiagnosticExporter().export(
            result: result,
            nodeRole: .iPhone
        )
        let unsafe = "/Users/example/private/note.json \(String(repeating: "a", count: 64)) api_key=secret"
        let redacted = CanonicalLibraryMetadataPilotDiagnosticRedactor().redact(unsafe)

        #expect(summary.mode == .diagnosticsOnly)
        #expect(summary.nodeRole == .iPhone)
        #expect(summary.activePilot == .libraryMetadata)
        #expect(summary.freezeStatus == "allowed")
        #expect(summary.candidateSelected == false)
        #expect(summary.canaryAttempted == false)
        #expect(summary.otherDomainsStatic)
        #expect(summary.runtimeSwitchFalse)
        #expect(summary.diagnosticsRedacted)
        #expect(redacted.contains("/Users") == false)
        #expect(redacted.contains(String(repeating: "a", count: 64)) == false)
        #expect(redacted.lowercased().contains("api_key") == false)
    }

    private static func makeIsolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "RokuricsTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func matrixReplacing(
        _ domain: CanonicalMigrationDomain,
        mutate: (inout CanonicalMigrationDomainPolicy) -> Void
    ) -> CanonicalMigrationDomainMatrix {
        var matrix = CanonicalMigrationDomainMatrix.defaultV813()
        matrix.policies = matrix.policies.map { existing in
            var copy = existing
            if copy.domain == domain {
                mutate(&copy)
            }
            return copy
        }
        return matrix
    }
}
