//
//  CanonicalSyncRuntimeTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalSyncRuntimeTests {
    @Test func defaultDisabledUsesLegacyOwner() {
        let result = Self.runtimeResult(configuration: .disabled)

        #expect(result.canonicalPlanUsed == false)
        #expect(result.canonicalPlanFallback == true)
        #expect(result.canonicalPlanNoCommit == true)
    }

    @Test func diagnosticsOnlyDoesNotChangeOwner() {
        let result = Self.runtimeResult(
            configuration: CanonicalSyncRuntimeConfiguration(mode: .diagnosticsOnly)
        )

        #expect(result.gateResult.state == .allowedNoCommit)
        #expect(result.canonicalPlanUsed == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataDecisionEvaluated })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataDecisionFallback })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactDecisionEvaluated })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactDecisionFallback })
    }

    @Test func canonicalPlanNoCommitDoesNotSuppressLegacy() {
        let identity = CanonicalSyncRuntimeActionIdentity(scope: .recordingMetadata, objectID: "recording-01", actionKind: "uploadMetadata")
        let guardResult = CanonicalSyncRuntimeDuplicateExecutionGuard().evaluate(
            canonicalOwnerUsed: false,
            mode: .canonicalPlanNoCommit,
            syncRunID: "sync-runtime-test",
            canonicalActions: [identity],
            legacyActions: [identity],
            enabledScopes: [.recordingMetadata]
        )

        #expect(guardResult.suppressedLegacyActions.isEmpty)
        #expect(guardResult.preventedDuplicateActions.isEmpty)
    }

    @Test func primaryModeRequiresDebugInternalConfig() {
        let result = Self.runtimeResult(
            configuration: CanonicalSyncRuntimeConfiguration(mode: .canonicalPlanPrimaryWithLegacyFallback)
        )

        #expect(result.gateResult.state == .blockedReleaseDefault)
        #expect(result.canonicalPlanUsed == false)
        #expect(result.canonicalPlanFallback == true)
    }

    @Test func primaryModeBlockedWithoutV837Snapshot() {
        let result = Self.runtimeResult(
            configuration: Self.primaryConfiguration(),
            inventorySnapshotAvailable: false
        )

        #expect(result.gateResult.state == .blockedMissingSnapshot)
        #expect(result.canonicalPlanBlocked == true)
    }

    @Test func primaryModeBlockedOnSchemaMismatch() {
        let result = Self.runtimeResult(
            configuration: Self.primaryConfiguration(),
            peerMetadataHashSchemaVersion: "legacy-recording-metadata-v0"
        )

        #expect(result.gateResult.state == .blockedSchemaMismatch)
        #expect(result.diagnostics.contains { $0.kind == .canonicalSyncRuntimeSchemaMismatch })
    }

    @Test func primaryModeBlockedOnLibraryMetadataSchemaMismatch() {
        let result = Self.runtimeResult(
            configuration: Self.primaryConfiguration(),
            peerLibraryMetadataHashSchemaVersion: "legacy-library-metadata-v0"
        )

        #expect(result.gateResult.state == .blockedSchemaMismatch)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataSchemaMismatch })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataDecisionFallback })
    }

    @Test func primaryModeBlockedOnGeneratedArtifactSchemaMismatch() {
        let result = Self.runtimeResult(
            configuration: Self.primaryConfiguration(),
            peerGeneratedArtifactHashSchemaVersion: "legacy-generated-artifact-v0"
        )

        #expect(result.gateResult.state == .blockedSchemaMismatch)
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactSchemaMismatch })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactDecisionFallback })
    }

    @Test func primaryModeBlockedOnUnsupportedObjects() {
        let result = Self.runtimeResult(
            configuration: Self.primaryConfiguration(),
            unsupportedLegacyObjectCount: 1
        )

        #expect(result.gateResult.state == .blockedUnsupportedObjects)
        #expect(result.diagnostics.contains { $0.kind == .canonicalSyncRuntimeUnsupportedObjectBlocked })
    }

    @Test func primaryModeBlockedOnConflicts() {
        let result = Self.runtimeResult(
            configuration: Self.primaryConfiguration(),
            conflictCount: 1
        )

        #expect(result.gateResult.state == .blockedConflicts)
        #expect(result.diagnostics.contains { $0.kind == .canonicalSyncRuntimeConflictBlocked })
    }

    @Test func sameCanonicalHashWithDifferentLegacyHashIsCanonicalNoOp() throws {
        let plan = try CanonicalSyncPlanner().plan(
            local: Self.manifest(),
            peer: Self.manifest(nodeID: "mac-01", platform: "Mac"),
            trigger: .periodic,
            legacyContext: CanonicalSyncPlannerLegacyContext(legacyUploadMetadataObjectIDs: ["recording-01"])
        )

        #expect(plan.uploadRecordingMetadata.isEmpty)
        #expect(plan.downloadRecordingMetadata.isEmpty)
        #expect(plan.noOpRecordingMetadata.first?.reason == .metadataHashEqual)
        #expect(plan.diagnostics.contains { $0.reason == .legacyMetadataHashMismatchButCanonicalHashMatch })
    }

    @Test func modifiedAtLWWIsDeterministic() throws {
        let localNewer = try CanonicalSyncPlanner().plan(
            local: Self.manifest(title: "Local", modifiedAt: 3_000),
            peer: Self.manifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_000),
            trigger: .periodic
        )
        let tieA = try CanonicalSyncPlanner().plan(
            local: Self.manifest(title: "A", modifiedAt: 2_000),
            peer: Self.manifest(title: "B", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_000),
            trigger: .periodic
        )
        let tieB = try CanonicalSyncPlanner().plan(
            local: Self.manifest(title: "A", modifiedAt: 2_000),
            peer: Self.manifest(title: "B", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_000),
            trigger: .periodic
        )

        #expect(localNewer.uploadRecordingMetadata.first?.reason == .localMetadataNewer)
        #expect(tieA.conflictRecordingMetadata.first?.reason == .metadataTieConflict)
        #expect(tieA == tieB)
    }

    @Test func peerUnknownDoesNotBecomeMissing() {
        let result = Self.runtimeResult(
            configuration: Self.primaryConfiguration(),
            peerUnknownAudioCount: 1
        )

        #expect(result.gateResult.state == .blockedPeerUnknown)
        #expect(result.canonicalPlanUsed == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadPeerUnknownDeferred })
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadDecisionFallback })
    }

    @Test func audioUploadScopeCanBePrimaryDecisionAndSuppressExactDuplicate() {
        let configuration = Self.primaryConfiguration()
        let result = Self.runtimeResult(configuration: configuration)
        let identity = CanonicalSyncRuntimeActionIdentity(
            scope: .audioUpload,
            objectID: "recording-01",
            actionKind: "audioUpload"
        )
        let guardResult = CanonicalSyncRuntimeDuplicateExecutionGuard().evaluate(
            canonicalOwnerUsed: true,
            mode: .canonicalPlanPrimaryWithLegacyFallback,
            syncRunID: "sync-runtime-test",
            canonicalActions: [identity],
            legacyActions: [identity],
            enabledScopes: configuration.policy.enabledScopes
        )

        #expect(configuration.policy.enabledScopes.contains(.audioUpload))
        #expect(result.canonicalPlanUsed)
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadDecisionEvaluated })
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadDecisionUsed })
        #expect(guardResult.suppressedLegacyActions == [identity])
        #expect(guardResult.preventedDuplicateActions == [identity])
    }

    @Test func duplicateExecutionGuardPreventsExactDoubleAction() {
        let identity = CanonicalSyncRuntimeActionIdentity(scope: .recordingMetadata, objectID: "recording-01", actionKind: "uploadMetadata")
        let guardResult = CanonicalSyncRuntimeDuplicateExecutionGuard().evaluate(
            canonicalOwnerUsed: true,
            mode: .canonicalPlanPrimaryWithLegacyFallback,
            syncRunID: "sync-runtime-test",
            canonicalActions: [identity],
            legacyActions: [identity],
            enabledScopes: [.recordingMetadata]
        )

        #expect(guardResult.suppressedLegacyActions == [identity])
        #expect(guardResult.preventedDuplicateActions == [identity])
        #expect(guardResult.diagnostics.contains { $0.kind == .canonicalSyncRuntimeDuplicateExecutionPrevented })
    }

    @Test func duplicateExecutionGuardPreventsGeneratedArtifactDoubleAction() {
        let identity = CanonicalSyncRuntimeActionIdentity(scope: .generatedArtifacts, objectID: "transcriptJSON:recording-01", actionKind: "downloadArtifact")
        let guardResult = CanonicalSyncRuntimeDuplicateExecutionGuard().evaluate(
            canonicalOwnerUsed: true,
            mode: .canonicalPlanPrimaryWithLegacyFallback,
            syncRunID: "sync-runtime-test",
            canonicalActions: [identity],
            legacyActions: [identity],
            enabledScopes: [.generatedArtifacts]
        )

        #expect(guardResult.suppressedLegacyActions == [identity])
        #expect(guardResult.preventedDuplicateActions == [identity])
        #expect(guardResult.diagnostics.contains { $0.kind == .canonicalSyncRuntimeDuplicateExecutionPrevented })
    }

    @Test func fallbackPreservesLegacyOnBlocker() {
        let result = Self.runtimeResult(
            configuration: Self.primaryConfiguration(),
            peerManifest: nil
        )

        #expect(result.gateResult.state == .blockedPeerUnavailable)
        #expect(result.canonicalPlanUsed == false)
        #expect(result.canonicalPlanFallback == true)
    }

    @Test func diagnosticsAreRedacted() {
        let fullHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        let diagnostic = CanonicalSyncRuntimeDiagnostic(
            kind: .canonicalSyncRuntimeLegacyHashMismatchIgnored,
            syncRunID: "sync-runtime-test",
            mode: .canonicalPlanPrimaryWithLegacyFallback,
            objectID: "/Users/example/private/recording-01.json",
            actionKind: "uploadMetadata",
            hash: CanonicalHash(fullHash),
            detail: #"{"absolutePath":"/Users/example/private"}"#
        )

        #expect(diagnostic.isRedacted)
        #expect(diagnostic.hashPrefix == String(fullHash.prefix(12)))
        #expect(!diagnostic.summary().contains(fullHash))
        #expect(!diagnostic.summary().contains("/Users/example/private"))
    }

    private static func runtimeResult(
        configuration: CanonicalSyncRuntimeConfiguration,
        inventorySnapshotAvailable: Bool = true,
        peerManifest: CanonicalManifest? = Self.manifest(nodeID: "mac-01", platform: "Mac"),
        peerMetadataHashSchemaVersion: String? = CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
        peerLibraryMetadataHashSchemaVersion: String? = CanonicalLibraryMetadataHashSchema.version,
        peerGeneratedArtifactHashSchemaVersion: String? = CanonicalGeneratedArtifactHashSchema.version,
        unsupportedLegacyObjectCount: Int = 0,
        conflictCount: Int = 0,
        peerUnknownAudioCount: Int = 0
    ) -> CanonicalSyncRuntimeResult {
        let gateResult = CanonicalSyncPlanAuthorityGate().evaluate(
            configuration: configuration,
            context: CanonicalSyncPlanAuthorityGateContext(
                inventorySnapshotAvailable: inventorySnapshotAvailable,
                localManifest: Self.manifest(),
                peerManifest: peerManifest,
                localMetadataHashSchemaVersion: CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
                peerMetadataHashSchemaVersion: peerMetadataHashSchemaVersion,
                localLibraryMetadataHashSchemaVersion: CanonicalLibraryMetadataHashSchema.version,
                peerLibraryMetadataHashSchemaVersion: peerLibraryMetadataHashSchemaVersion,
                localGeneratedArtifactHashSchemaVersion: CanonicalGeneratedArtifactHashSchema.version,
                peerGeneratedArtifactHashSchemaVersion: peerGeneratedArtifactHashSchemaVersion,
                canonicalModifiedAtSemanticsAvailable: true,
                unsupportedLegacyObjectCount: unsupportedLegacyObjectCount,
                conflictCount: conflictCount,
                peerUnknownAudioCount: peerUnknownAudioCount,
                legacyFallbackAvailable: true,
                diagnosticsRedacted: true,
                runtimeSwitchEnabled: false,
                readPathLegacy: true,
                debugInternalBuild: configuration.policy.debugInternalBuild,
                ownerApproved: configuration.policy.ownerApproved,
                releaseDefaultBuild: configuration.policy.releaseDefaultBuild
            )
        )
        return CanonicalSyncRuntimeResult.make(
            mode: configuration.mode,
            gateResult: gateResult,
            syncRunID: "sync-runtime-test",
            extraDiagnostics: Self.blockerDiagnostics(gateResult: gateResult, mode: configuration.mode)
        )
    }

    private static func blockerDiagnostics(
        gateResult: CanonicalSyncPlanAuthorityGateResult,
        mode: CanonicalSyncRuntimeMode
    ) -> [CanonicalSyncRuntimeDiagnostic] {
        var diagnostics: [CanonicalSyncRuntimeDiagnostic] = []
        if gateResult.blockers.contains(.unsupportedObjects) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimeUnsupportedObjectBlocked, syncRunID: "sync-runtime-test", mode: mode, detail: gateResult.state.rawValue))
        }
        if gateResult.blockers.contains(.unresolvedConflicts) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimeConflictBlocked, syncRunID: "sync-runtime-test", mode: mode, detail: gateResult.state.rawValue))
        }
        if gateResult.blockers.contains(.schemaMismatch) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimeSchemaMismatch, syncRunID: "sync-runtime-test", mode: mode, detail: gateResult.state.rawValue))
        }
        return diagnostics
    }

    private static func primaryConfiguration() -> CanonicalSyncRuntimeConfiguration {
        CanonicalSyncRuntimeConfiguration(
            mode: .canonicalPlanPrimaryWithLegacyFallback,
            policy: CanonicalSyncRuntimePolicy(
                debugInternalBuild: true,
                ownerApproved: true,
                releaseDefaultBuild: false
            )
        )
    }

    private static func manifest(
        title: String = "Lecture",
        nodeID: String = "iphone-01",
        platform: String = "iPhone",
        modifiedAt: TimeInterval = 2_000
    ) -> CanonicalManifest {
        let metadata = CanonicalRecordingMetadata(
            objectID: "recording-01",
            title: title,
            createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1_000)),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: modifiedAt)),
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
