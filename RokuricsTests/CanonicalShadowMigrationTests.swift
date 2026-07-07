//
//  CanonicalShadowMigrationTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalShadowMigrationTests {
    @Test func defaultConfigurationIsDisabledAndGateBlocks() {
        let configuration = CanonicalShadowMigrationConfiguration()
        let gate = CanonicalShadowMigrationGate.evaluate(
            configuration: configuration,
            trigger: .iPhoneSyncTick,
            nodeRole: .iPhone
        )

        #expect(configuration.effectiveMode == .disabled)
        #expect(gate.allowed == false)
        #expect(gate.failure == .disabled)
    }

    @Test func diagnosticsOnlyRecordsCompletionWithoutDryRun() {
        let result = CanonicalShadowMigrationRunner().run(
            configuration: .enabled(mode: .diagnosticsOnly),
            trigger: .iPhoneSyncTick,
            nodeRole: .iPhone,
            domain: .inventory,
            localSnapshot: nil,
            peerSnapshot: nil,
            ports: IPhoneCanonicalDryRunPorts.makePortSet(),
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
            trigger: .iPhoneSyncTick,
            nodeRole: .iPhone,
            domain: .inventory,
            localSnapshot: CanonicalProductionTestFixtures.snapshot(),
            peerSnapshot: nil,
            ports: IPhoneCanonicalDryRunPorts.makePortSet(),
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
            node: CanonicalProductionTestFixtures.node("mac-01", platform: "Mac")
        )

        let result = CanonicalShadowMigrationRunner().run(
            configuration: .enabled(mode: .shadowReadOnly),
            trigger: .iPhoneSyncTick,
            nodeRole: .iPhone,
            domain: .inventory,
            localSnapshot: local,
            peerSnapshot: peer,
            ports: IPhoneCanonicalDryRunPorts.makePortSet(),
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
            for: CanonicalShadowNetworkProbeRequest(kind: .health, routePath: "/health")
        )
        let enabledPolicy = CanonicalShadowNetworkProbePolicy(isEnabled: true)
        let healthDecision = enabledPolicy.decision(
            for: CanonicalShadowNetworkProbeRequest(kind: .health, routePath: "/health")
        )
        let mutatingDecision = enabledPolicy.decision(
            for: CanonicalShadowNetworkProbeRequest(kind: .uploadAudio, routePath: "/recordings/audio", bodyByteCount: 12)
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
        #expect(healthDecision.accepted)
        #expect(healthDecision.noMutation)
        #expect(mutatingDecision.accepted == false)
        #expect(mutatingDecision.reason == "mutatingRouteRejected")
        #expect(oversizedDecision.accepted == false)
        #expect(oversizedDecision.reason == "artifactRequestSizeBoundExceeded")
    }

    @Test func productionExecuteIsBlockedForIPhoneRole() {
        let audit = CanonicalProductionExecutionGuard.evaluate(
            mode: .productionExecute,
            token: CanonicalProductionExecutionToken(
                mode: .productionExecute,
                domainAllowlist: [],
                nodeRole: .iPhone,
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
            nodeRole: .iPhone,
            mode: .dryRunCompare,
            domain: .inventory,
            reason: "/Users/vita/secret-token/full transcript/provider response"
        )

        #expect(event.reason?.hasPrefix("redacted-") == true)
        #expect(event.diagnosticsSummary.contains("/Users") == false)
        #expect(event.diagnosticsSummary.lowercased().contains("secret") == false)
        #expect(event.syncRunID?.hasPrefix("redacted-") == true)
    }

    @Test func iPhoneShadowPortFactoryUsesAlreadyLoadedInventoryFactsOnly() {
        var legacyPlan = LocalNetworkSyncDiffPlan()
        legacyPlan.uploadRecordingAudioActions = [
            LocalNetworkSyncDiffAction(
                id: "upload-audio-recording-01",
                kind: .uploadRecordingAudio,
                entityKind: "recording",
                entityID: "recording-01",
                reason: "peer_missing_audio"
            )
        ]
        let inventory = makeInventory(
            deviceID: "iphone-01",
            platform: .iPhone,
            manifest: CanonicalProductionTestFixtures.snapshot().manifest
        )

        let output = IPhoneCanonicalShadowPortFactory(
            configuration: .enabled(mode: .dryRunCompare)
        ).makeOutput(
            localInventory: inventory,
            peerInventory: nil,
            legacyPlan: legacyPlan
        )

        #expect(output.localSnapshot != nil)
        #expect(output.peerSnapshot == nil)
        #expect(output.missingPortReport.dryRunOnly)
        #expect(output.localSnapshot?.legacyActions.actionIDs(for: .recordingAudio) == ["upload-audio-recording-01"])
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
