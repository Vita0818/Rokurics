//
//  CanonicalApplyRuntimeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalApplyRuntimeTests {
    @Test func defaultDisabledKeepsLegacyOwnerOnMac() async {
        let result = await CanonicalApplyRuntimeOwner().execute(
            CanonicalApplyRuntimeTests.context(mode: .disabled)
        )

        #expect(result.gateResult.state == CanonicalApplyRuntimeGateState.legacyOwner)
        #expect(result.legacyFallbackUsed)
        #expect(result.executedActionIDs.isEmpty)
    }

    @Test func explicitTestRootCanExecuteRecordingExistenceBridgeAction() async {
        let action = CanonicalApplyAction(
            kind: .recordingMetadataApply,
            source: .peer,
            target: CanonicalApplyTarget(objectID: "recording-existence"),
            bridgeHint: .legacyMetadataManifestApply,
            reason: CanonicalApplyRuntimeOwner.recordingExistenceBridgeReason
        )
        let result = await CanonicalApplyRuntimeOwner().execute(
            CanonicalApplyRuntimeTests.context(
                mode: .testRootApply,
                action: action,
                enabledDomains: [.recordingExistence],
                registry: CanonicalApplyRuntimeExecutorRegistry(entries: [
                    CanonicalApplyRuntimeExecutorEntry(domain: .recordingExistence) { context in
                        .success(action: context.action, domain: .recordingExistence, detail: "metadataOnlyBridge")
                    }
                ])
            )
        )

        #expect(result.gateResult.executesCommit)
        #expect(result.executedActionIDs == [action.actionID])
        #expect(result.report.diagnostics.contains { $0.kind == CanonicalSyncRuntimeDiagnosticKind.canonicalApplyRuntimeActionCompleted })
    }

    @Test func audioActionBlockedOnMacRuntime() async {
        let action = CanonicalApplyAction(
            kind: .generatedArtifactDownloadApply,
            source: .peer,
            target: CanonicalApplyTarget(
                objectID: "recording-audio",
                artifactID: CanonicalArtifact.Kind.audio.artifactID(for: "recording-audio"),
                artifactKind: .audio
            ),
            reason: "audioUpload"
        )
        let result = await CanonicalApplyRuntimeOwner().execute(
            CanonicalApplyRuntimeTests.context(
                mode: .testRootApply,
                action: action,
                enabledDomains: [.generatedArtifacts, .audioUpload],
                registry: CanonicalApplyRuntimeExecutorRegistry(entries: [
                    CanonicalApplyRuntimeExecutorEntry(domain: .generatedArtifacts) { context in
                        .success(action: context.action, domain: .generatedArtifacts)
                    }
                ])
            )
        )

        #expect(result.gateResult.blockers.contains(CanonicalApplyRuntimeBlocker.audioActionBlocked))
        #expect(result.executedActionIDs.isEmpty)
    }

    private static func context(
        mode: CanonicalApplyRuntimeMode,
        action: CanonicalApplyAction = CanonicalApplyAction(
            kind: .recordingMetadataApply,
            source: .peer,
            target: CanonicalApplyTarget(objectID: "recording-01"),
            reason: CanonicalApplyActionKind.recordingMetadataApply.rawValue
        ),
        enabledDomains: [CanonicalApplyRuntimeDomain] = [.recordingMetadata],
        registry: CanonicalApplyRuntimeExecutorRegistry = CanonicalApplyRuntimeExecutorRegistry(entries: [
            CanonicalApplyRuntimeExecutorEntry(domain: .recordingMetadata) { context in
                .success(action: context.action, domain: .recordingMetadata)
            }
        ])
    ) -> CanonicalApplyRuntimeOwnerContext {
        CanonicalApplyRuntimeOwnerContext(
            configuration: CanonicalApplyRuntimeConfiguration(
                mode: mode,
                policy: CanonicalApplyRuntimePolicy(
                    debugInternalBuild: true,
                    ownerApproved: true,
                    releaseDefaultBuild: false,
                    enabledDomains: enabledDomains
                )
            ),
            applyPlan: CanonicalApplyPlan(trigger: .manual, actions: [action]),
            localManifest: manifest(nodeID: "mac-01", platform: "Mac"),
            peerManifest: manifest(nodeID: "iphone-01", platform: "iPhone"),
            inventorySnapshotValid: true,
            canonicalPlanAuthorityAllowed: true,
            legacyFallbackAvailable: true,
            registry: registry,
            syncRunID: "mac-apply-runtime-test"
        )
    }

    private static func manifest(nodeID: String, platform: String) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(nodeID: nodeID, platform: platform, capabilities: [.recordingMetadata]),
            objects: [],
            manifestCapabilities: [.recordingMetadata]
        )
    }
}
