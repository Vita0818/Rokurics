//
//  CanonicalTombstoneConflictTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalTombstoneConflictTests {
    @Test func sameTombstoneConflictMarkersProduceSameCanonicalHashAcrossRoles() {
        let iPhoneMarker = Self.softObjectMarker()
        let macMarker = Self.softObjectMarker(
            ignoredDeleteTargetPath: "/Users/example/private/delete-target",
            ignoredLocalPath: "/private/var/mobile/local-object.json",
            ignoredUIOnlyState: "selected-row",
            ignoredUploadProgressState: "in-flight"
        )

        #expect(CanonicalTombstoneConflictHashSchema.version == "canonical-tombstone-conflict-v1")
        #expect(iPhoneMarker.markerHash == macMarker.markerHash)
        #expect(CanonicalTombstoneConflictHashSchema.v1.excludedFields.contains("deleteTargetPath"))
        #expect(CanonicalTombstoneConflictHashSchema.v1.excludedFields.contains("localPath"))
        #expect(CanonicalTombstoneConflictHashSchema.v1.excludedFields.contains("uiOnlyState"))
        #expect(CanonicalTombstoneConflictHashSchema.v1.excludedFields.contains("fullObjectContent"))
    }

    @Test func conflictAndResurrectionRecordsUseStableHashFactsOnly() {
        let conflict = Self.conflictRecord(conflictKind: "activeVsTombstone")
        let sameConflict = Self.conflictRecord(conflictKind: "activeVsTombstone")
        let resurrection = Self.resurrectionBlock()
        let sameResurrection = Self.resurrectionBlock()

        #expect(conflict.markerHash == sameConflict.markerHash)
        #expect(resurrection.markerHash == sameResurrection.markerHash)
        #expect(conflict.markerHash != resurrection.markerHash)
    }

    @Test func markerKindConflictKindAndLogicalTimeAffectHashDeterministically() {
        let base = Self.conflictRecord(conflictKind: "activeVsTombstone", modifiedAt: 10)
        let kindChanged = Self.softObjectMarker(markerID: base.markerID, modifiedAt: 10)
        let conflictKindChanged = Self.conflictRecord(conflictKind: "metadataConcurrentEdit", modifiedAt: 10)
        let timeChanged = Self.conflictRecord(conflictKind: "activeVsTombstone", modifiedAt: 11)

        #expect(base.markerHash != kindChanged.markerHash)
        #expect(base.markerHash != conflictKindChanged.markerHash)
        #expect(base.markerHash != timeChanged.markerHash)
    }

    @Test func logicalTimePolicyNoOpsAppliesNewerMarkerAndDefersEqualTie() {
        let policy = CanonicalTombstoneConflictModifiedAtPolicy.current
        let equal = policy.decide(.init(local: Self.softObjectMarker(), peer: Self.softObjectMarker()))
        let peerNewer = policy.decide(.init(local: Self.softObjectMarker(modifiedAt: 10), peer: Self.softObjectMarker(modifiedAt: 20)))
        let tie = policy.decide(.init(local: Self.softObjectMarker(markerID: "marker-a", modifiedAt: 10), peer: Self.softObjectMarker(markerID: "marker-b", modifiedAt: 10)))
        let missingTime = policy.decide(.init(local: Self.softObjectMarker(modifiedAt: nil), peer: Self.softObjectMarker(modifiedAt: nil), logicalTimeAvailable: false))

        #expect(equal.action == .noOp)
        #expect(equal.hashEqual)
        #expect(peerNewer.action == .applyPeerMarker)
        #expect(peerNewer.logicalTimeApplied)
        #expect(tie.action == .writeConflictRecord)
        #expect(tie.tieDeferred)
        #expect(missingTime.action == .legacyFallback)
        #expect(missingTime.legacyFallback)
    }

    @Test func antiResurrectionAndUnsafeDeleteActionsAreBlockedOrRecorded() {
        let policy = CanonicalTombstoneConflictModifiedAtPolicy.current
        let stale = policy.decide(.init(local: Self.softObjectMarker(), peer: Self.softObjectMarker(), staleLiveResurrectionDetected: true))
        let ambiguous = policy.decide(.init(local: Self.softObjectMarker(), peer: Self.softObjectMarker(markerID: "marker-b"), ambiguousConflictDetected: true))
        let restore = policy.decide(.init(local: Self.softObjectMarker(), peer: nil, restoreRequested: true))
        let clear = policy.decide(.init(local: Self.softObjectMarker(), peer: nil, clearTombstoneRequested: true))
        let physicalDelete = policy.decide(.init(local: Self.softObjectMarker(), peer: nil, physicalDeleteRequested: true))
        let permanentDelete = policy.decide(.init(local: Self.softObjectMarker(), peer: nil, permanentDeleteRequested: true))
        let gc = policy.decide(.init(local: Self.softObjectMarker(), peer: nil, tombstoneGCRequested: true))
        let unsupported = policy.decide(.init(local: Self.generatedArtifactReportOnlyMarker(), peer: nil))

        #expect(stale.action == .writeResurrectionBlockRecord)
        #expect(stale.resurrectionBlocked)
        #expect(ambiguous.action == .writeConflictRecord)
        #expect(ambiguous.conflictRecorded)
        #expect(restore.restoreBlocked)
        #expect(clear.clearBlocked)
        #expect(physicalDelete.physicalDeleteBlocked)
        #expect(permanentDelete.permanentDeleteBlocked)
        #expect(gc.tombstoneGCBlocked)
        #expect(unsupported.unsupportedKindBlocked)
        #expect(unsupported.legacyFallback)
    }

    @Test func cutoverCandidateMarkerHashUsesV854BusinessSchema() {
        let tombstone = CanonicalTombstone(
            target: CanonicalApplyTarget(objectID: "recording-01"),
            state: .tombstoned,
            reason: .peerTombstoneNewer,
            deletedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 10)),
            sourceNodeID: "iphone"
        )
        let action = CanonicalApplyAction(
            kind: .objectTombstoneApply,
            source: .peer,
            target: CanonicalApplyTarget(objectID: "recording-01"),
            tombstoneID: tombstone.tombstoneID,
            reason: "softDelete"
        )
        let candidate = CanonicalTombstoneConflictCandidate(
            action: action,
            recordingTombstone: tombstone
        )

        #expect(candidate.markerPayload["schema"] == CanonicalTombstoneConflictHashSchema.version)
        #expect(candidate.markerPayload["markerKind"] == CanonicalTombstoneConflictMarkerKind.softObjectTombstoneMarker.rawValue)
        #expect(candidate.markerPayload["deleteTargetPath"] == nil)
        #expect(candidate.markerHash == candidate.businessFields.markerHash)
    }

    @Test func syncRuntimeAndReadRuntimeExposeTombstoneConflictDomainDiagnostics() {
        let configuration = CanonicalSyncRuntimeConfiguration(
            mode: .canonicalPlanPrimaryWithLegacyFallback,
            policy: CanonicalSyncRuntimePolicy(
                debugInternalBuild: true,
                ownerApproved: true,
                releaseDefaultBuild: false
            )
        )
        let gate = CanonicalSyncPlanAuthorityGate().evaluate(
            configuration: configuration,
            context: CanonicalSyncPlanAuthorityGateContext(
                inventorySnapshotAvailable: true,
                localManifest: Self.manifest(),
                peerManifest: Self.manifest(nodeID: "mac-01", platform: "Mac"),
                localTombstoneConflictHashSchemaVersion: CanonicalTombstoneConflictHashSchema.version,
                peerTombstoneConflictHashSchemaVersion: "legacy-tombstone-conflict-v0",
                canonicalModifiedAtSemanticsAvailable: true,
                debugInternalBuild: true,
                ownerApproved: true,
                releaseDefaultBuild: false
            )
        )
        let syncResult = CanonicalSyncRuntimeResult.make(mode: configuration.mode, gateResult: gate, syncRunID: "tombstone-conflict-runtime")

        #expect(gate.state == .blockedSchemaMismatch)
        #expect(configuration.policy.enabledScopes.contains(.tombstoneConflict))
        #expect(syncResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictDecisionEvaluated })
        #expect(syncResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictSchemaMismatch })

        let readResult = CanonicalReadRuntimeProvider(configuration: .explicitGuardedCanonicalRead()).read(
            legacySnapshot: CanonicalReadSnapshot.build(source: .legacy, manifest: Self.manifest(), generatedAt: Date(timeIntervalSince1970: 3_000)),
            canonicalSnapshot: CanonicalReadSnapshot.build(source: .canonical, manifest: Self.manifest(), generatedAt: Date(timeIntervalSince1970: 3_000)),
            syncRunID: "tombstone-conflict-read"
        )

        #expect(readResult.returnedSource == .canonical)
        #expect(readResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictReadServedCanonical })
        #expect(readResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictReadDiffEquivalent })
        #expect(readResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictReadDidNotTriggerDelete })
    }

    @Test func v854ScorecardIsCodeCompleteButDeviceEvidenceAndRetirementRemainReportOnly() {
        let scorecard = CanonicalTombstoneConflictDomainReadinessScorecard.v854P2_4()

        #expect(scorecard.domain == .tombstoneConflict)
        #expect(scorecard.writeExecutorReady)
        #expect(scorecard.decisionRuntimeReady)
        #expect(scorecard.applyRuntimeReady)
        #expect(scorecard.readRuntimeReady)
        #expect(scorecard.antiResurrectionReady)
        #expect(scorecard.deleteTargetPathExcludedFromHash)
        #expect(scorecard.contentPathUIStateExcludedFromHash)
        #expect(scorecard.unsafeDeleteRestoreGCBlocked)
        #expect(scorecard.codeComplete)
        #expect(scorecard.realDeviceEvidencePresent == false)
        #expect(scorecard.readyForManualSwitchTrial == false)
        #expect(scorecard.readyToRetireLegacyReportOnly == false)
    }

    private static func softObjectMarker(
        markerID: String = "tombstone|recording-01|object|metadata",
        modifiedAt: TimeInterval? = 10,
        ignoredDeleteTargetPath: String? = nil,
        ignoredLocalPath: String? = nil,
        ignoredUIOnlyState: String? = nil,
        ignoredUploadProgressState: String? = nil
    ) -> CanonicalTombstoneConflictBusinessFields {
        CanonicalTombstoneConflictBusinessFields(
            markerID: markerID,
            objectID: "recording-01",
            markerKind: .softObjectTombstoneMarker,
            tombstoneState: .tombstoned,
            businessModifiedAt: modifiedAt.map { CanonicalTimestamp(Date(timeIntervalSince1970: $0)) },
            actorDeviceRole: "owner",
            ignoredDeleteTargetPath: ignoredDeleteTargetPath,
            ignoredLocalPath: ignoredLocalPath,
            ignoredUIOnlyState: ignoredUIOnlyState,
            ignoredUploadProgressState: ignoredUploadProgressState
        )
    }

    private static func conflictRecord(conflictKind: String, modifiedAt: TimeInterval = 10) -> CanonicalTombstoneConflictBusinessFields {
        CanonicalTombstoneConflictBusinessFields(
            markerID: "conflict|recording-01",
            objectID: "recording-01",
            markerKind: .conflictRecord,
            conflictKind: conflictKind,
            tombstoneState: .tombstoned,
            displayState: .manualReviewRequired,
            businessModifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: modifiedAt)),
            conflictResolutionState: "unresolved"
        )
    }

    private static func resurrectionBlock() -> CanonicalTombstoneConflictBusinessFields {
        CanonicalTombstoneConflictBusinessFields(
            markerID: "resurrection-block|recording-01",
            objectID: "recording-01",
            markerKind: .resurrectionBlockRecord,
            conflictKind: "activeVsTombstone",
            tombstoneState: .tombstoned,
            displayState: .resurrectionBlocked,
            businessModifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 12)),
            conflictResolutionState: "unresolved"
        )
    }

    private static func generatedArtifactReportOnlyMarker() -> CanonicalTombstoneConflictBusinessFields {
        CanonicalTombstoneConflictBusinessFields(
            markerID: "artifact-tombstone|recording-01|noteJSON",
            objectID: "recording-01",
            markerKind: .generatedArtifactTombstoneMarkerReportOnly,
            tombstoneState: .tombstoned,
            businessModifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 10))
        )
    }

    private static func manifest(nodeID: String = "iphone-01", platform: String = "iPhone") -> CanonicalManifest {
        let metadata = CanonicalRecordingMetadata(
            objectID: "recording-01",
            title: "Lecture",
            createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1_000)),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2_000)),
            duration: 42
        )
        let object = CanonicalRecordingObject(
            objectID: "recording-01",
            nodeID: nodeID,
            metadata: metadata,
            syncState: .synced
        )
        return CanonicalManifest.make(
            node: CanonicalNode(nodeID: nodeID, platform: platform, capabilities: [.recordingMetadata, .objectProjection]),
            generatedAt: Date(timeIntervalSince1970: 3_000),
            objects: [object]
        )
    }
}
