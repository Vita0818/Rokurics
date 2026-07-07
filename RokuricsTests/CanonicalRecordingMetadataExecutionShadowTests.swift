//
//  CanonicalRecordingMetadataExecutionShadowTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalRecordingMetadataExecutionShadowTests {
    @Test func defaultDisabledProducesNoDiagnosticsOrWrites() {
        let report = CanonicalRecordingMetadataExecutionShadowPlanner().run(
            configuration: .disabled,
            trigger: .testHarness,
            nodeRole: .testHarness,
            localManifest: manifest(title: "Same"),
            peerManifest: manifest(title: "Same", nodeID: "mac-01", platform: "Mac"),
            syncRunID: "disabled"
        )

        #expect(report.domainResult.failure == .disabled)
        #expect(report.events.isEmpty)
        #expect(report.writes.isEmpty)
        #expect(report.records.isEmpty)
    }

    @Test func unsupportedOrMissingDomainDoesNotExecuteRecordingMetadata() {
        let report = run(
            configuration: .enabled(domains: [.recordingAudio], mode: .executionShadowDryRun),
            local: manifest(title: "Local", modifiedAt: 2_000),
            peer: manifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_100)
        )

        #expect(report.domainResult.failure == .unsupportedDomain)
        #expect(report.actions.isEmpty)
        #expect(report.events.isEmpty)
        #expect(report.writes.isEmpty)
    }

    @Test func sameCanonicalMetadataHashSuppressesLegacyMetadataChurn() {
        let legacy = CanonicalLegacyActionSnapshot(actionIDsByDomain: [
            .recordingMetadata: ["uploadMetadata:recording:recording-01:legacyHashMismatch"]
        ])
        let report = run(
            configuration: .enabled(domain: .recordingMetadata, mode: .dryRunCompare),
            local: manifest(title: "Same"),
            peer: manifest(title: "Same", nodeID: "mac-01", platform: "Mac"),
            legacyActions: legacy
        )

        #expect(report.equivalence == .canonicalMoreConservative)
        #expect(report.blockerCount == 0)
        #expect(report.noOpCount == 1)
        #expect(report.writes.isEmpty)
        #expect(report.events.contains { $0.kind == .canonicalRecordingMetadataShadowNoOp })
        #expect(report.events.contains { $0.kind == .canonicalRecordingMetadataExecutionShadowCompleted })
    }

    @Test func peerNewerMetadataAppliesIntoShadowStoreWhenLegacyMatchesDirection() {
        let legacy = CanonicalLegacyActionSnapshot(actionIDsByDomain: [
            .recordingMetadata: ["recordingMetadataApply:recording-01"]
        ])
        let report = run(
            configuration: .enabled(domain: .recordingMetadata, mode: .executionShadowWithShadowFileStore),
            local: manifest(title: "Local", modifiedAt: 2_000),
            peer: manifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_100),
            legacyActions: legacy
        )

        #expect(report.succeeded)
        #expect(report.equivalence == .equivalent)
        #expect(report.applyCount == 1)
        #expect(report.sendCount == 0)
        #expect(report.writes.first?.kind == .apply)
        #expect(report.writes.first?.postcondition.wroteProductionStore == false)
        #expect(report.writes.first?.postcondition.sentNetworkRequest == false)
        #expect(report.writes.first?.postcondition.touchedReceiveJSON == false)
        #expect(report.events.contains { $0.kind == .canonicalRecordingMetadataShadowApplyRehearsed })
    }

    @Test func localNewerMetadataProjectsShadowSendWhenLegacyMatchesDirection() {
        let legacy = CanonicalLegacyActionSnapshot(actionIDsByDomain: [
            .recordingMetadata: ["recordingMetadataSend:recording-01"]
        ])
        let report = run(
            configuration: .enabled(domain: .recordingMetadata, mode: .executionShadowDryRun),
            local: manifest(title: "Local", modifiedAt: 2_200),
            peer: manifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_000),
            legacyActions: legacy
        )

        #expect(report.succeeded)
        #expect(report.sendCount == 1)
        #expect(report.applyCount == 0)
        #expect(report.writes.first?.kind == .send)
        #expect(report.events.contains { $0.kind == .canonicalRecordingMetadataShadowSendRehearsed })
    }

    @Test func canonicalMoreAggressiveIsBlockingByDefaultAndDoesNotWrite() {
        let report = run(
            configuration: .enabled(domain: .recordingMetadata, mode: .executionShadowDryRun),
            local: manifest(title: "Local", modifiedAt: 2_000),
            peer: manifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_100)
        )

        #expect(report.equivalence == .canonicalMoreAggressive)
        #expect(report.blockerCount == 1)
        #expect(report.writes.isEmpty)
        #expect(report.events.contains { $0.kind == .canonicalRecordingMetadataShadowProductionExecuteBlocked })
        #expect(report.events.contains { $0.kind == .canonicalRecordingMetadataExecutionShadowBlocked })
    }

    @Test func policyCanAllowCanonicalMoreAggressiveShadowRehearsal() {
        let policy = CanonicalShadowDomainPolicy(allowCanonicalMoreAggressive: true)
        let report = run(
            configuration: .enabled(domain: .recordingMetadata, mode: .executionShadowDryRun, policy: policy),
            local: manifest(title: "Local", modifiedAt: 2_000),
            peer: manifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_100)
        )

        #expect(report.equivalence == .canonicalMoreAggressive)
        #expect(report.blockerCount == 0)
        #expect(report.applyCount == 1)
        #expect(report.writes.count == 1)
    }

    @Test func sameModifiedAtDifferentHashIsConflictOnly() {
        let report = run(
            configuration: .enabled(domain: .recordingMetadata, mode: .executionShadowDryRun),
            local: manifest(title: "Local", modifiedAt: 2_000),
            peer: manifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_000)
        )

        #expect(report.conflictCount == 1)
        #expect(report.blockerCount == 1)
        #expect(report.applyCount == 0)
        #expect(report.sendCount == 0)
        #expect(report.writes.isEmpty)
        #expect(report.events.contains { $0.kind == .canonicalRecordingMetadataShadowDivergenceDetected })
    }

    @Test func newerPeerTombstoneWritesMarkerOnlyInShadowStore() {
        let legacy = CanonicalLegacyActionSnapshot(actionIDsByDomain: [
            .recordingMetadata: ["recordingMetadataApply:recording-01"]
        ])
        let report = run(
            configuration: .enabled(domain: .recordingMetadata, mode: .executionShadowWithShadowFileStore),
            local: manifest(title: "Active", modifiedAt: 2_000),
            peer: manifest(
                title: "Deleted",
                nodeID: "mac-01",
                platform: "Mac",
                modifiedAt: 3_000,
                isDeleted: true,
                deletedAt: 3_000
            ),
            legacyActions: legacy
        )

        #expect(report.tombstoneCount == 1)
        #expect(report.records.first?.tombstone == true)
        #expect(report.writes.first?.kind == .tombstoneMarker)
        #expect(report.writes.first?.postcondition.wroteProductionStore == false)
        #expect(report.writes.first?.postcondition.touchedReceiveJSON == false)
    }

    @Test func activeVersusTombstoneConflictDoesNotApplyOrMarkTombstone() {
        let report = run(
            configuration: .enabled(domain: .recordingMetadata, mode: .executionShadowDryRun),
            local: manifest(title: "Active", modifiedAt: 3_000),
            peer: manifest(
                title: "Deleted",
                nodeID: "mac-01",
                platform: "Mac",
                modifiedAt: 2_900,
                isDeleted: true,
                deletedAt: 2_900
            )
        )

        #expect(report.conflictCount == 1)
        #expect(report.tombstoneCount == 0)
        #expect(report.writes.isEmpty)
        #expect(report.divergences.contains { $0.kind == .conflict && $0.blocking })
    }

    @Test func missingPeerSnapshotIsNonFatalBlockedReport() {
        let report = CanonicalRecordingMetadataExecutionShadowPlanner().run(
            configuration: .enabled(domain: .recordingMetadata, mode: .executionShadowDryRun),
            trigger: .macInventory,
            nodeRole: .mac,
            localManifest: manifest(title: "Local"),
            peerManifest: nil,
            syncRunID: "missing-peer"
        )

        #expect(report.domainResult.failure == .insufficientPeerSnapshot)
        #expect(report.succeeded == false)
        #expect(report.writes.isEmpty)
        #expect(report.events.contains { $0.kind == .canonicalRecordingMetadataExecutionShadowBlocked })
        #expect(report.events.contains { $0.kind == .canonicalRecordingMetadataExecutionShadowCompleted } == false)
    }

    @Test func diagnosticsOnlyReportsButDoesNotRecordShadowWrites() {
        let legacy = CanonicalLegacyActionSnapshot(actionIDsByDomain: [
            .recordingMetadata: ["recordingMetadataApply:recording-01"]
        ])
        let report = run(
            configuration: .enabled(domain: .recordingMetadata, mode: .diagnosticsOnly),
            local: manifest(title: "Local", modifiedAt: 2_000),
            peer: manifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_100),
            legacyActions: legacy
        )

        #expect(report.applyCount == 1)
        #expect(report.writes.isEmpty)
        #expect(report.records.isEmpty)
        #expect(report.events.contains { $0.kind == .canonicalRecordingMetadataShadowApplyRehearsed })
    }

    @Test func diagnosticsAreBoundedAndUseHashPrefixes() {
        let policy = CanonicalShadowDomainPolicy(maxDiagnosticsEvents: 2, allowCanonicalMoreAggressive: true)
        let legacy = CanonicalLegacyActionSnapshot(actionIDsByDomain: [
            .recordingMetadata: ["recordingMetadataApply:recording-01"]
        ])
        let report = run(
            configuration: .enabled(domain: .recordingMetadata, mode: .executionShadowDryRun, policy: policy),
            local: manifest(title: "Local", modifiedAt: 2_000),
            peer: manifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_100),
            legacyActions: legacy
        )

        #expect(report.events.count == 2)
        #expect(report.writes.first?.postcondition.resultHashPrefix?.count == 12)
        #expect(report.events.allSatisfy { $0.diagnosticsSummary.contains("domain=recordingMetadata") })
    }

    private func run(
        configuration: CanonicalSingleDomainShadowConfiguration,
        local: CanonicalManifest,
        peer: CanonicalManifest,
        legacyActions: CanonicalLegacyActionSnapshot = .empty
    ) -> CanonicalRecordingMetadataExecutionShadowReport {
        CanonicalRecordingMetadataExecutionShadowPlanner().run(
            configuration: configuration,
            trigger: .testHarness,
            nodeRole: .testHarness,
            localManifest: local,
            peerManifest: peer,
            legacyActions: legacyActions,
            syncRunID: "recording-metadata-shadow-test"
        )
    }

    private func manifest(
        title: String,
        nodeID: String = "iphone-01",
        platform: String = "iPhone",
        modifiedAt: TimeInterval = 2_000,
        isDeleted: Bool = false,
        deletedAt: TimeInterval? = nil
    ) -> CanonicalManifest {
        let metadata = CanonicalRecordingMetadata(
            objectID: "recording-01",
            title: title,
            createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1_000)),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: modifiedAt)),
            duration: 42,
            filing: CanonicalRecordingMetadata.Filing(type: "course", subject: "math"),
            tags: ["review"],
            isDeleted: isDeleted,
            deletedAt: deletedAt.map { CanonicalTimestamp(Date(timeIntervalSince1970: $0)) }
        )
        let audio = CanonicalArtifactFact.audio(
            availability: .available,
            contentHash: CanonicalHash("aaaaaaaa"),
            byteSize: 42,
            logicalName: "audio.m4a"
        ).makeArtifact(objectID: metadata.objectID, producedByNodeID: nodeID)
        return CanonicalManifest.make(
            node: CanonicalNode(
                nodeID: nodeID,
                platform: platform,
                capabilities: [.recordingMetadata, .audioArtifact, .objectProjection]
            ),
            generatedAt: Date(timeIntervalSince1970: 4_000),
            objects: [
                CanonicalRecordingObject(
                    objectID: metadata.objectID,
                    nodeID: nodeID,
                    metadata: metadata,
                    artifacts: [audio]
                )
            ]
        )
    }
}
