//
//  CanonicalShadowMigrationTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalShadowMigrationTests {
    @Test func defaultConfigurationIsDisabledAndGateBlocks() {
        let configuration = CanonicalShadowMigrationConfiguration()
        let gate = CanonicalShadowMigrationGate.evaluate(
            configuration: configuration,
            trigger: .macInventory,
            nodeRole: .mac
        )

        #expect(configuration.effectiveMode == .disabled)
        #expect(gate.allowed == false)
        #expect(gate.failure == .disabled)
    }

    @Test func diagnosticsOnlyRecordsCompletionWithoutDryRun() {
        let result = CanonicalShadowMigrationRunner().run(
            configuration: .enabled(mode: .diagnosticsOnly),
            trigger: .macInventory,
            nodeRole: .mac,
            domain: .inventory,
            localSnapshot: nil,
            peerSnapshot: nil,
            ports: MacCanonicalDryRunPorts.makePortSet(),
            syncRunID: "sync-run-diagnostics"
        )

        #expect(result.succeeded)
        #expect(result.dryRunPlan == nil)
        #expect(result.failure == nil)
        #expect(result.report.events.contains { $0.kind == .canonicalShadowMigrationCompleted })
        #expect(result.report.events.contains { $0.kind == .canonicalShadowMigrationSuppressedSideEffects })
    }

    @Test func dryRunCompareMissingPeerSnapshotIsNonFatal() {
        let result = CanonicalShadowMigrationRunner().run(
            configuration: .enabled(mode: .dryRunCompare),
            trigger: .macInventory,
            nodeRole: .mac,
            domain: .inventory,
            localSnapshot: CanonicalProductionTestFixtures.snapshot(),
            peerSnapshot: nil,
            ports: MacCanonicalDryRunPorts.makePortSet(),
            syncRunID: "sync-run-missing-peer"
        )

        #expect(result.succeeded == false)
        #expect(result.failure == .insufficientPeerSnapshot)
        #expect(result.isFatal == false)
        #expect(result.report.events.contains { $0.kind == .canonicalShadowMigrationBlocked })
    }

    @Test func shadowReadOnlyRunsDryRunWithSuppressedSideEffects() {
        let local = CanonicalProductionTestFixtures.snapshot()
        let peer = CanonicalProductionTestFixtures.snapshot(
            node: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone")
        )

        let result = CanonicalShadowMigrationRunner().run(
            configuration: .enabled(mode: .shadowReadOnly),
            trigger: .macInventory,
            nodeRole: .mac,
            domain: .inventory,
            localSnapshot: local,
            peerSnapshot: peer,
            ports: MacCanonicalDryRunPorts.makePortSet(),
            syncRunID: "sync-run-read-only"
        )

        #expect(result.dryRunPlan != nil)
        #expect(result.report.suppressedSideEffects.noWrite)
        #expect(result.report.suppressedSideEffects.noUpload)
        #expect(result.report.suppressedSideEffects.noApply)
        #expect(result.report.suppressedSideEffects.noProductionExecute)
    }

    @Test func networkProbePolicyDefaultsOffAndRejectsMutatingRoutes() {
        let defaultDecision = CanonicalShadowNetworkProbePolicy().decision(
            for: CanonicalShadowNetworkProbeRequest(kind: .fingerprint, routePath: "/fingerprint")
        )
        let enabledPolicy = CanonicalShadowNetworkProbePolicy(isEnabled: true)
        let fingerprintDecision = enabledPolicy.decision(
            for: CanonicalShadowNetworkProbeRequest(kind: .fingerprint, routePath: "/fingerprint")
        )
        let mutatingDecision = enabledPolicy.decision(
            for: CanonicalShadowNetworkProbeRequest(kind: .applyManifest, routePath: "/sync/apply", bodyByteCount: 12)
        )
        let oversizedDecision = enabledPolicy.decision(
            for: CanonicalShadowNetworkProbeRequest(
                kind: .artifactRequestReadOnly,
                routePath: "/sync/artifact",
                bodyByteCount: 1024,
                artifactByteLimit: 16
            )
        )

        #expect(defaultDecision.accepted == false)
        #expect(defaultDecision.reason == "networkProbeDisabled")
        #expect(fingerprintDecision.accepted)
        #expect(fingerprintDecision.noMutation)
        #expect(mutatingDecision.accepted == false)
        #expect(mutatingDecision.reason == "mutatingRouteRejected")
        #expect(oversizedDecision.accepted == false)
        #expect(oversizedDecision.reason == "artifactRequestSizeBoundExceeded")
    }

    @Test func productionExecuteIsBlockedForMacRole() {
        let audit = CanonicalProductionExecutionGuard.evaluate(
            mode: .productionExecute,
            token: CanonicalProductionExecutionToken(
                mode: .productionExecute,
                domainAllowlist: [],
                nodeRole: .mac,
                syncRunID: "sync-run-production-block",
                ownerApproved: true
            ),
            policy: CanonicalProductionExecutionPolicy(
                requiredDomains: [],
                requiredPorts: [],
                requireOwnerApproval: false,
                requireRollbackPlan: false,
                requireDryRunEquivalence: false,
                requireMigrationGateUnblocked: false,
                rejectUnresolvedConflicts: false
            ),
            domains: [],
            ports: CanonicalProductionPortSet(),
            rollbackPlan: nil,
            dryRunReportID: nil,
            dryRunEquivalence: nil,
            readinessReport: nil,
            unresolvedConflictCount: 0
        )

        #expect(audit.allowed == false)
        #expect(audit.rejectionReasons == [.blockedProductionExecute])
    }

    @Test func reportRedactsSensitivePathsAndContentSignals() {
        let event = CanonicalShadowMigrationEvent(
            kind: .canonicalShadowMigrationBlocked,
            syncRunID: "sync-token-secret",
            trigger: .manual,
            nodeRole: .mac,
            mode: .dryRunCompare,
            domain: .inventory,
            reason: "/Users/vita/secret-token/full transcript/provider response"
        )

        #expect(event.reason?.hasPrefix("redacted-") == true)
        #expect(event.diagnosticsSummary.contains("/Users") == false)
        #expect(event.diagnosticsSummary.lowercased().contains("secret") == false)
        #expect(event.syncRunID?.hasPrefix("redacted-") == true)
    }

    @Test func macShadowPortFactoryUsesAlreadyLoadedInventoryFactsOnly() {
        var legacyPlan = LocalNetworkSyncDiffPlan()
        legacyPlan.downloadArtifactActions = [
            LocalNetworkSyncDiffAction(
                id: "download-artifact-recording-01",
                kind: .downloadArtifact,
                entityKind: "artifact",
                entityID: "recording-01:noteMarkdown",
                reason: "peer_has_generated_artifact"
            )
        ]
        let inventory = makeInventory(
            deviceID: "mac-01",
            platform: .Mac,
            manifest: CanonicalProductionTestFixtures.snapshot().manifest
        )

        let output = MacCanonicalShadowPortFactory(
            configuration: .enabled(mode: .dryRunCompare)
        ).makeOutput(
            localInventory: inventory,
            peerInventory: nil,
            legacyPlan: legacyPlan
        )

        #expect(output.localSnapshot != nil)
        #expect(output.peerSnapshot == nil)
        #expect(output.missingPortReport.dryRunOnly)
        #expect(output.localSnapshot?.legacyActions.actionIDs(for: .generatedArtifacts) == ["download-artifact-recording-01"])
        #expect(output.diagnosticsSafeSummary.contains("/Users") == false)
    }

    private func makeInventory(
        deviceID: String,
        platform: LocalNetworkSyncPlatform,
        manifest: CanonicalManifest
    ) -> LocalNetworkSyncInventory {
        LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: deviceID,
                deviceName: platform.rawValue,
                platform: platform,
                generatedAt: Date(timeIntervalSince1970: 1_000),
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            canonicalManifest: manifest
        )
    }
}
