//
//  CanonicalSyncRuntimeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalSyncRuntimeTests {
    @Test func macMissingPeerSnapshotBlocksPrimaryAndFallsBack() {
        let configuration = CanonicalSyncRuntimeConfiguration(
            mode: .canonicalPlanPrimaryWithLegacyFallback,
            policy: CanonicalSyncRuntimePolicy(
                debugInternalBuild: true,
                ownerApproved: true,
                releaseDefaultBuild: false
            )
        )
        let gateResult = CanonicalSyncPlanAuthorityGate().evaluate(
            configuration: configuration,
            context: CanonicalSyncPlanAuthorityGateContext(
                inventorySnapshotAvailable: true,
                localManifest: Self.manifest(),
                peerManifest: nil,
                peerAbsenceExplicitlyModeled: false,
                canonicalModifiedAtSemanticsAvailable: true,
                legacyFallbackAvailable: true,
                diagnosticsRedacted: true,
                runtimeSwitchEnabled: false,
                readPathLegacy: true,
                debugInternalBuild: true,
                ownerApproved: true,
                releaseDefaultBuild: false
            )
        )
        let result = CanonicalSyncRuntimeResult.make(
            mode: configuration.mode,
            gateResult: gateResult,
            syncRunID: "mac-runtime-test",
            extraDiagnostics: [
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalSyncRuntimePeerSnapshotUnavailable,
                    syncRunID: "mac-runtime-test",
                    mode: configuration.mode,
                    detail: gateResult.state.rawValue
                )
            ]
        )

        #expect(gateResult.state == .blockedPeerUnavailable)
        #expect(result.canonicalPlanUsed == false)
        #expect(result.canonicalPlanFallback == true)
        #expect(result.diagnostics.contains { $0.kind == .canonicalSyncRuntimePlanBlocked })
        #expect(result.diagnostics.contains { $0.kind == .canonicalSyncRuntimePlanFallback })
        #expect(result.diagnostics.contains { $0.kind == .canonicalSyncRuntimePeerSnapshotUnavailable })
    }

    @Test func defaultDisabledKeepsLegacyOwnerOnMac() {
        let gateResult = CanonicalSyncPlanAuthorityGate().evaluate(
            configuration: .disabled,
            context: CanonicalSyncPlanAuthorityGateContext(
                inventorySnapshotAvailable: true,
                localManifest: Self.manifest(),
                peerManifest: Self.manifest(nodeID: "iphone-01", platform: "iPhone"),
                canonicalModifiedAtSemanticsAvailable: true
            )
        )
        let result = CanonicalSyncRuntimeResult.make(
            mode: .disabled,
            gateResult: gateResult,
            syncRunID: "mac-runtime-test"
        )

        #expect(result.canonicalPlanUsed == false)
        #expect(result.canonicalPlanNoCommit == true)
    }

    @Test func audioUploadScopeCanBePrimaryDecisionAndSuppressDuplicateOnMac() {
        let configuration = CanonicalSyncRuntimeConfiguration(
            mode: .canonicalPlanPrimaryWithLegacyFallback,
            policy: CanonicalSyncRuntimePolicy(
                debugInternalBuild: true,
                ownerApproved: true,
                releaseDefaultBuild: false
            )
        )
        let gateResult = CanonicalSyncPlanAuthorityGate().evaluate(
            configuration: configuration,
            context: CanonicalSyncPlanAuthorityGateContext(
                inventorySnapshotAvailable: true,
                localManifest: Self.manifest(),
                peerManifest: Self.manifest(nodeID: "iphone-01", platform: "iPhone"),
                canonicalModifiedAtSemanticsAvailable: true,
                debugInternalBuild: true,
                ownerApproved: true,
                releaseDefaultBuild: false
            )
        )
        let result = CanonicalSyncRuntimeResult.make(
            mode: configuration.mode,
            gateResult: gateResult,
            syncRunID: "mac-runtime-test"
        )
        let identity = CanonicalSyncRuntimeActionIdentity(
            scope: .audioUpload,
            objectID: "recording-01",
            actionKind: "audioUpload"
        )
        let guardResult = CanonicalSyncRuntimeDuplicateExecutionGuard().evaluate(
            canonicalOwnerUsed: true,
            mode: configuration.mode,
            syncRunID: "mac-runtime-test",
            canonicalActions: [identity],
            legacyActions: [identity],
            enabledScopes: configuration.policy.enabledScopes
        )

        #expect(configuration.policy.enabledScopes.contains(.audioUpload))
        #expect(result.canonicalPlanUsed)
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadDecisionEvaluated })
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadDecisionUsed })
        #expect(guardResult.suppressedLegacyActions == [identity])
    }

    @Test func generatedArtifactSchemaMismatchFallsBackOnMac() {
        let configuration = CanonicalSyncRuntimeConfiguration(
            mode: .canonicalPlanPrimaryWithLegacyFallback,
            policy: CanonicalSyncRuntimePolicy(
                debugInternalBuild: true,
                ownerApproved: true,
                releaseDefaultBuild: false
            )
        )
        let gateResult = CanonicalSyncPlanAuthorityGate().evaluate(
            configuration: configuration,
            context: CanonicalSyncPlanAuthorityGateContext(
                inventorySnapshotAvailable: true,
                localManifest: Self.manifest(),
                peerManifest: Self.manifest(nodeID: "iphone-01", platform: "iPhone"),
                localGeneratedArtifactHashSchemaVersion: CanonicalGeneratedArtifactHashSchema.version,
                peerGeneratedArtifactHashSchemaVersion: "legacy-generated-artifact-v0",
                canonicalModifiedAtSemanticsAvailable: true,
                debugInternalBuild: true,
                ownerApproved: true,
                releaseDefaultBuild: false
            )
        )
        let result = CanonicalSyncRuntimeResult.make(
            mode: configuration.mode,
            gateResult: gateResult,
            syncRunID: "mac-runtime-test"
        )

        #expect(gateResult.state == .blockedSchemaMismatch)
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactSchemaMismatch })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactDecisionFallback })
    }

    @Test func macRuntimeDiagnosticsAreRedacted() {
        let fullHash = "abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"
        let diagnostic = CanonicalSyncRuntimeDiagnostic(
            kind: .canonicalSyncRuntimePlanBlocked,
            syncRunID: "mac-runtime-test",
            mode: .canonicalPlanPrimaryWithLegacyFallback,
            objectID: "/private/var/Rokurics/recording-01.json",
            hash: CanonicalHash(fullHash),
            detail: #"{"path":"/private/var/Rokurics"}"#
        )

        #expect(diagnostic.isRedacted)
        #expect(diagnostic.hashPrefix == String(fullHash.prefix(12)))
        #expect(!diagnostic.summary().contains(fullHash))
        #expect(!diagnostic.summary().contains("/private/var/Rokurics"))
    }

    private static func manifest(
        nodeID: String = "mac-01",
        platform: String = "Mac"
    ) -> CanonicalManifest {
        let metadata = CanonicalRecordingMetadata(
            objectID: "recording-01",
            title: "Lecture",
            createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1_000)),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2_000)),
            duration: 42,
            filing: CanonicalRecordingMetadata.Filing(type: "course", subject: "math"),
            tags: []
        )
        let audio = CanonicalArtifactFact.audio(
            availability: .available,
            contentHash: CanonicalHash("aaaaaaaa"),
            byteSize: 42,
            logicalName: "audio.m4a"
        ).makeArtifact(objectID: metadata.objectID)
        let object = CanonicalRecordingObject(
            objectID: metadata.objectID,
            nodeID: nodeID,
            metadata: metadata,
            artifacts: [audio]
        )
        return CanonicalManifest.make(
            node: CanonicalNode(
                nodeID: nodeID,
                platform: platform,
                capabilities: [.recordingMetadata, .audioArtifact, .objectProjection]
            ),
            generatedAt: Date(timeIntervalSince1970: 3_000),
            objects: [object]
        )
    }
}
