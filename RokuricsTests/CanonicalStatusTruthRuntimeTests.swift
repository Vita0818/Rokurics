//
//  CanonicalStatusTruthRuntimeTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/14.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalStatusTruthRuntimeTests {
    private static let now = CanonicalTimestamp(Date(timeIntervalSince1970: 9_400))
    private static let later = CanonicalTimestamp(Date(timeIntervalSince1970: 9_401))
    private static let objectID = CanonicalObjectID("recording-v940")
    private static let iPhoneNode = CanonicalNodeID("iphone-node")
    private static let macNode = CanonicalNodeID("mac-node")
    private static let hashA = CanonicalHash(String(repeating: "a", count: 64))
    private static let hashB = CanonicalHash(String(repeating: "b", count: 64))

    @Test func sharedTruthTableRejectsSoftEvidenceAndAcceptsProofs() {
        let proofs: [(CanonicalStatusProof, CanonicalStatusHardRule, Bool)] = [
            (Self.proof(.metadataOnly), .metadataOnlyIsNotAudioAvailable, false),
            (Self.proof(.receiveRecordOnly), .receiveRecordOnlyIsNotAudioAvailable, false),
            (Self.proof(.completedLedgerOnly), .completedLedgerAloneIsNotPeerProof, false),
            (Self.proof(.partialReceive), .partialReceiveIsNotCompleted, false),
            (Self.proof(.localFileExists, hash: Self.hashA, byteSize: 100), .localFileExistsIsNotPeerHasFile, false),
            (Self.proof(.expectedManifestHash, hash: Self.hashA), .expectedManifestHashIsNotPeerProof, false),
            (Self.proof(.peerUnknown), .peerUnknownMustDefer, false),
            (Self.proof(.existingDifferentAudio), .existingDifferentAudioMustConflictNoOverwrite, false),
            (Self.proof(.peerInventoryHashSizeMatch, hash: Self.hashA, byteSize: 100, peer: Self.macNode), .finalizeProofOrPeerHashSizeProofCanComplete, true),
            (Self.proof(.sameHashAndByteSize, hash: Self.hashA, byteSize: 100, peer: Self.macNode), .sameHashAndSameByteSizeIsAudioNoOp, true),
            (Self.finalizeStatusProof(), .finalizeProofOrPeerHashSizeProofCanComplete, true)
        ]

        for (proof, expectedRule, accepted) in proofs {
            let evaluation = CanonicalStatusTruthRules.evaluatePeerAudioProof(proof)
            #expect(evaluation.rule == expectedRule)
            #expect(evaluation.acceptedAsPeerAudioProof == accepted)
        }
        #expect(CanonicalStatusTruthRules.viewRefreshMayCreateUploadJob() == false)
        #expect(CanonicalStatusTruthRules.retryDrainerMayCreateFreshUploadJob() == false)
    }

    @Test func localAudioAndPeerMetadataOnlyNeedsUploadButIsNotComplete() async throws {
        let runtime = Self.runtime()
        let local = Self.fact("local-audio", source: .localFileObservation, kind: .localFileExists, hash: Self.hashA, byteSize: 100)
        let metadataOnly = Self.fact("peer-metadata", source: .peerMetadata, kind: .metadataOnly, producer: Self.macNode, counter: 2)

        _ = await runtime.produce([local, metadataOnly])
        let reconciliation = try await runtime.reconcile(facts: await runtime.facts(for: Self.objectID))

        #expect(reconciliation.effectiveStatus.phase == CanonicalStatusPhase.uploadNeeded)
        #expect(reconciliation.effectiveStatus.canCreateUploadJob)
        #expect(reconciliation.effectiveStatus.canDisplayAsComplete == false)
        #expect(reconciliation.effectiveStatus.blocker == CanonicalStatusBlocker.metadataOnlyRejectedAsAudioProof)
        #expect(reconciliation.blockers.contains(CanonicalStatusHardRule.metadataOnlyIsNotAudioAvailable))
    }

    @Test func peerUnknownOrdinarySyncDefersUploadCreation() async throws {
        let runtime = Self.runtime()
        let unknown = Self.fact("peer-unknown", source: .syncRuntime, kind: .peerUnknown)

        _ = await runtime.produce(unknown)
        let status = try await runtime.reconcile(facts: await runtime.facts(for: Self.objectID)).effectiveStatus

        #expect(status.phase == CanonicalStatusPhase.deferred)
        #expect(status.canCreateUploadJob == false)
        #expect(status.blocker == CanonicalStatusBlocker.peerProofUnavailable)
    }

    @Test func completedLedgerAloneIsRejectedAsPeerProof() async throws {
        let runtime = Self.runtime()
        let local = Self.fact("local-audio", source: .localFileObservation, kind: .localFileExists, hash: Self.hashA, byteSize: 100)
        let ledger = Self.fact("completed-ledger", source: .legacyCompletedLedger, kind: .completedLedgerOnly, counter: 3)

        _ = await runtime.produce([local, ledger])
        let reconciliation = try await runtime.reconcile(facts: await runtime.facts(for: Self.objectID))

        #expect(reconciliation.effectiveStatus.canDisplayAsComplete == false)
        #expect(reconciliation.effectiveStatus.phase == CanonicalStatusPhase.localOnly)
        #expect(reconciliation.blockers.contains(CanonicalStatusHardRule.completedLedgerAloneIsNotPeerProof))
        #expect(reconciliation.blockers.contains(CanonicalStatusHardRule.localFileExistsIsNotPeerHasFile))
    }

    @Test func sameHashAndSizeSuppressesDuplicateDifferentHashConflicts() async throws {
        let sameRuntime = Self.runtime()
        let local = Self.fact("local-audio", source: .localFileObservation, kind: .localFileExists, hash: Self.hashA, byteSize: 100)
        let samePeer = Self.fact(
            "peer-same",
            source: .peerInventory,
            kind: .peerInventoryHashSizeMatch,
            producer: Self.macNode,
            counter: 2,
            hash: Self.hashA,
            byteSize: 100
        )
        _ = await sameRuntime.produce([local, samePeer])
        let sameStatus = try await sameRuntime.reconcile(facts: await sameRuntime.facts(for: Self.objectID)).effectiveStatus

        #expect(sameStatus.phase == CanonicalStatusPhase.peerVerified)
        #expect(sameStatus.canDisplayAsComplete)
        #expect(sameStatus.canSuppressLegacyDuplicate)
        #expect(sameStatus.canCreateUploadJob == false)

        let conflictRuntime = Self.runtime()
        let differentPeer = Self.fact(
            "peer-different",
            source: .peerInventory,
            kind: .peerInventoryHashSizeMatch,
            producer: Self.macNode,
            counter: 2,
            hash: Self.hashB,
            byteSize: 100
        )
        _ = await conflictRuntime.produce([local, differentPeer])
        let conflict = try await conflictRuntime.reconcile(facts: await conflictRuntime.facts(for: Self.objectID))

        #expect(conflict.effectiveStatus.phase == CanonicalStatusPhase.conflict)
        #expect(conflict.effectiveStatus.canCreateUploadJob == false)
        #expect(conflict.effectiveStatus.blocker == CanonicalStatusBlocker.existingDifferentAudioConflict)
        #expect(conflict.mayOverwriteExistingPeerAudio == false)
    }

    @Test func uploadJobGateDeniesViewRefreshAndRetryDrainerFreshCreation() async throws {
        let local = Self.fact("local-audio", source: .localFileObservation, kind: .localFileExists, hash: Self.hashA, byteSize: 100)
        let viewRefreshMetadata = Self.fact(
            "view-refresh-metadata",
            source: .viewRefresh,
            kind: .metadataOnly,
            counter: 2,
            causality: CanonicalStatusCausality(trigger: .viewRefresh)
        )
        let viewRefresh = try await Self.runtime().reconcile(facts: [local, viewRefreshMetadata]).effectiveStatus

        #expect(viewRefresh.phase == CanonicalStatusPhase.uploadNeeded)
        #expect(viewRefresh.canCreateUploadJob == false)
        #expect(viewRefresh.blocker == CanonicalStatusBlocker.viewRefreshCannotCreateUploadJob)

        let retryMetadata = Self.fact(
            "retry-metadata",
            source: .retryDrainer,
            kind: .metadataOnly,
            counter: 2,
            causality: CanonicalStatusCausality(trigger: .retryDrainer)
        )
        let retryFresh = try await Self.runtime().reconcile(facts: [local, retryMetadata]).effectiveStatus

        #expect(retryFresh.phase == CanonicalStatusPhase.uploadNeeded)
        #expect(retryFresh.canCreateUploadJob == false)
        #expect(retryFresh.blocker == CanonicalStatusBlocker.retryDrainerRequiresExistingEligibleJob)

        let retryExisting = Self.fact(
            "retry-existing",
            source: .retryDrainer,
            kind: .existingEligibleRetry,
            counter: 3,
            causality: CanonicalStatusCausality(trigger: .retryDrainer)
        )
        let retryResumeOnly = try await Self.runtime().reconcile(facts: [local, retryMetadata, retryExisting]).effectiveStatus

        #expect(retryResumeOnly.phase == CanonicalStatusPhase.uploadNeeded)
        #expect(retryResumeOnly.canCreateUploadJob == false)
    }

    @Test func factStoreReplacementExpirationAndOrderingAreDeterministic() async {
        let store = CanonicalStatusFactStore()
        let older = Self.fact("replaceable", source: .peerMetadata, kind: .metadataOnly, counter: 1)
        let olderDuplicate = Self.fact("replaceable", source: .peerMetadata, kind: .metadataOnly, counter: 0)
        let newer = Self.fact("replaceable", source: .peerMetadata, kind: .metadataOnly, counter: 2)
        let replacement = Self.fact(
            "replacement",
            source: .peerInventory,
            kind: .peerInventoryHashSizeMatch,
            producer: Self.macNode,
            counter: 3,
            hash: Self.hashA,
            byteSize: 100,
            causality: CanonicalStatusCausality(replacesFactIDs: [older.factID])
        )
        let expired = Self.fact(
            "expired",
            source: .peerMetadata,
            kind: .metadataOnly,
            counter: 4,
            expiry: CanonicalStatusExpiry(expiresAt: Self.now)
        )

        let olderResult = await store.merge(older, now: Self.later)
        let olderDuplicateResult = await store.merge(olderDuplicate, now: Self.later)
        let newerResult = await store.merge(newer, now: Self.later)
        let replacementResult = await store.merge(replacement, now: Self.later)
        let expiredResult = await store.merge(expired, now: Self.later)

        #expect(olderResult.decision == CanonicalStatusFactMergeDecision.merged)
        #expect(olderDuplicateResult.decision == CanonicalStatusFactMergeDecision.ignoredOlderDuplicate)
        #expect(newerResult.decision == CanonicalStatusFactMergeDecision.merged)
        #expect(replacementResult.decision == CanonicalStatusFactMergeDecision.replaced)
        #expect(expiredResult.decision == CanonicalStatusFactMergeDecision.rejectedExpired)

        let facts = await store.facts(for: Self.objectID, now: Self.later)
        #expect(facts.map(\.factID) == [replacement.factID])
    }

    @Test func statusTruthProjectionCacheServesEffectiveStatusWithoutMainActorReconciliation() async {
        let runtime = Self.runtime()
        let local = Self.fact("local-audio", source: .localFileObservation, kind: .localFileExists, hash: Self.hashA, byteSize: 100)
        let metadataOnly = Self.fact("peer-metadata", source: .peerMetadata, kind: .metadataOnly, producer: Self.macNode, counter: 2)

        _ = await runtime.produce([local, metadataOnly])
        let beforeRead = await runtime.projectionMetricsSnapshot()
        let first = await runtime.effectiveStatus(for: Self.objectID)
        let second = await runtime.effectiveStatus(for: Self.objectID)
        let afterRead = await runtime.projectionMetricsSnapshot()
        let snapshot = await runtime.projectionSnapshot(for: Self.objectID)
        let diagnostics = await runtime.diagnosticRecords()

        #expect(first == second)
        #expect(first.phase == .uploadNeeded)
        #expect(snapshot?.effectiveStatus == first)
        #expect(snapshot?.version == beforeRead.projectionVersion)
        #expect(afterRead.projectedCount == beforeRead.projectedCount)
        #expect(afterRead.projectionCacheHitCount >= beforeRead.projectionCacheHitCount + 2)
        #expect(afterRead.mainActorStatusReconciliationAttemptCount == 0)
        #expect(diagnostics.contains { $0.event == .statusProjectionDurationMs })
        #expect(diagnostics.contains { $0.event == .effectiveStatusProjected })
    }

    @MainActor
    @Test func uploadCoordinatorDisplayCacheAppliesStatusTruthProjection() async throws {
        let objectID = CanonicalObjectID("recordingAudio:abc")
        let runtime = CanonicalStatusTruthRuntime(nowProvider: { Self.later })
        let uploadCoordinator = RecordingUploadCoordinator(canonicalStatusTruthRuntime: runtime)
        let proof = CanonicalTransferFinalizeProof.v930(
            receiverNodeID: Self.macNode,
            sessionID: CanonicalTransferSessionID("session-abc"),
            objectID: objectID,
            byteSize: 100,
            contentHash: Self.hashA,
            finalizedAt: Self.now
        )
        let fact = Self.fact(
            "finalize-proof",
            objectID: objectID,
            source: .transferFinalizeProof,
            kind: .finalizeProof,
            producer: Self.macNode,
            counter: 4,
            hash: Self.hashA,
            byteSize: 100,
            finalizeProof: proof,
            phase: .completed
        )

        _ = await runtime.produce(fact)
        let snapshot = try #require(await runtime.projectionSnapshot(for: objectID))
        uploadCoordinator.applyCanonicalStatusProjection(snapshot)

        let display = try #require(uploadCoordinator.canonicalDisplaySyncState(for: objectID))
        #expect(display.kind == .completed)
        #expect(display.canDisplayAsComplete)
        #expect(display.effectiveStatus.proof?.objectID == objectID)
    }

    @MainActor
    @Test func uploadCoordinatorDisplayCacheRejectsSoftAudioStatusFacts() async throws {
        let cases: [(CanonicalStatusProofKind, CanonicalStatusSource, CanonicalStatusPhase, CanonicalDisplaySyncStateKind?)] = [
            (.metadataOnly, .peerMetadata, .peerKnownMetadataOnly, .deferred),
            (.partialReceive, .partialReceive, .partialReceive, .uploading),
            (.completedLedgerOnly, .legacyCompletedLedger, .finalizedLocally, nil),
            (.peerUnknown, .syncRuntime, .deferred, .deferred),
            (.existingDifferentAudio, .peerInventory, .conflict, .conflict)
        ]

        for (kind, source, phase, expectedDisplayKind) in cases {
            let objectID = CanonicalObjectID("recordingAudio:\(kind.rawValue)-abc")
            let runtime = CanonicalStatusTruthRuntime(nowProvider: { Self.later })
            let uploadCoordinator = RecordingUploadCoordinator(canonicalStatusTruthRuntime: runtime)
            let fact = Self.fact(
                "soft-\(kind.rawValue)",
                objectID: objectID,
                source: source,
                kind: kind,
                producer: source == .peerInventory || source == .peerMetadata ? Self.macNode : Self.iPhoneNode,
                counter: 5,
                hash: kind == .existingDifferentAudio ? Self.hashB : nil,
                byteSize: kind == .existingDifferentAudio ? 100 : nil,
                phase: phase
            )

            _ = await runtime.produce(fact)
            let snapshot = try #require(await runtime.projectionSnapshot(for: objectID))
            uploadCoordinator.applyCanonicalStatusProjection(snapshot)

            let display = try #require(uploadCoordinator.canonicalDisplaySyncState(for: objectID))
            if let expectedDisplayKind {
                #expect(display.kind == expectedDisplayKind)
            }
            #expect(display.isTerminalComplete == false)
        }
    }

    @Test func diagnosticsAreRedactedAndReadinessRequiresOldKernelFallback() async throws {
        let fullHash = String(repeating: "c", count: 64)
        let unsafe = CanonicalStatusTruthDiagnosticRecord(
            event: .statusFactProduced,
            objectID: Self.objectID,
            domain: .audioUpload,
            phase: .localOnly,
            detail: "path=/Users/vita/private/audio.m4a hash=\(fullHash) request body raw audio full transcript"
        )

        #expect(unsafe.redactedDetail == "redactionRejected")
        #expect(unsafe.isRedacted)
        #expect(unsafe.hashPrefix == nil)

        let readyEvidence = CanonicalStatusTruthReadinessEvidence(
            proofDrivenEffectiveStatus: true,
            hardRulesEnforced: true,
            factStoreReady: true,
            integrationAvailabilityReady: true,
            uploadJobGateReady: true,
            diagnosticsRedacted: true,
            oldKernelFallbackPreserved: true,
            defaultReleaseOldKernel: true,
            legacyFallbackPreserved: true,
            noRouteChange: true,
            uploadRouteSchemaUnchanged: true,
            securityInvariantUnchanged: true
        )
        let unsafeEvidence = CanonicalStatusTruthReadinessEvidence(
            proofDrivenEffectiveStatus: true,
            hardRulesEnforced: true,
            factStoreReady: true,
            integrationAvailabilityReady: true,
            uploadJobGateReady: true,
            diagnosticsRedacted: true,
            oldKernelFallbackPreserved: true,
            defaultReleaseOldKernel: false,
            legacyFallbackPreserved: true,
            noRouteChange: true,
            uploadRouteSchemaUnchanged: true,
            securityInvariantUnchanged: true
        )
        let ready = CanonicalStatusTruthReadiness.v940(readyEvidence)
        let unsafeReadiness = CanonicalStatusTruthReadiness.v940(unsafeEvidence)

        #expect(ready.status == CanonicalStatusTruthReadinessStatus.readyForV940StatusTruth)
        #expect(ready.ready)
        #expect(unsafeReadiness.status == CanonicalStatusTruthReadinessStatus.unsafeToProceed)
        #expect(unsafeReadiness.blockers.contains(CanonicalStatusTruthReadinessBlocker.defaultReleaseNotOldKernel))
    }

    @Test func iPhoneAdaptersExposeStatusTruthReadPathWithoutChangingRoutes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let uploadCoordinator = try String(
            contentsOf: root.appendingPathComponent("Rokurics/RecordingUploadCoordinator.swift"),
            encoding: .utf8
        )
        let syncCoordinator = try String(
            contentsOf: root.appendingPathComponent("Rokurics/StudyLibrarySyncCoordinator.swift"),
            encoding: .utf8
        )
        let studyStore = try String(
            contentsOf: root.appendingPathComponent("Rokurics/StudyLibraryStore.swift"),
            encoding: .utf8
        )
        let transferAdapter = try String(
            contentsOf: root.appendingPathComponent("Rokurics/IPhoneCanonicalTransferAdapter.swift"),
            encoding: .utf8
        )
        let macHTTPServer = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/SecureLocalHTTPSServer.swift"),
            encoding: .utf8
        )

        for source in [uploadCoordinator, syncCoordinator, studyStore] {
            #expect(source.contains("canonicalStatusTruthRuntime"))
            #expect(source.contains("produceCanonicalStatusFact(_ fact: CanonicalStatusFact)"))
        }
        #expect(uploadCoordinator.contains("effectiveSyncStatusByObjectID"))
        #expect(uploadCoordinator.contains("func effectiveSyncStatus(for objectID: CanonicalObjectID) -> CanonicalEffectiveSyncStatus?"))
        #expect(studyStore.contains("effectiveSyncStatusByObjectID"))
        #expect(studyStore.contains("func effectiveSyncStatus(for objectID: CanonicalObjectID) -> CanonicalEffectiveSyncStatus?"))
        #expect(uploadCoordinator.contains("RecordingUploadClient()"))
        #expect(uploadCoordinator.contains("IPhoneCanonicalSecureAudioUploadPort"))
        #expect(uploadCoordinator.contains("func applyCanonicalStatusProjection(_ snapshot: CanonicalStatusProjectionSnapshot)"))
        #expect(uploadCoordinator.contains("publishDecisionDisplayState("))
        #expect(uploadCoordinator.contains("Self.canonicalAudioObjectID(recordingID: metadata.id)"))
        #expect(uploadCoordinator.contains("canonicalAudioObjectID(recordingID: job.recordingID)"))
        #expect(!uploadCoordinator.contains("CanonicalObjectID(metadata.id)"))
        #expect(!uploadCoordinator.contains("CanonicalObjectID(job.recordingID)"))
        #expect(syncCoordinator.contains("bridgeCanonicalStatusProjections("))
        #expect(syncCoordinator.contains("uploadCoordinator?.applyCanonicalStatusProjection(snapshot)"))
        #expect(studyStore.contains("func applyCanonicalStatusProjection(_ snapshot: CanonicalStatusProjectionSnapshot)"))
        #expect(transferAdapter.contains("routeRecordingID(for objectID: CanonicalObjectID)"))
        #expect(transferAdapter.contains("CanonicalObjectID(\"recordingAudio:\\(rawValue)\")"))
        #expect(macHTTPServer.contains("Self.canonicalAudioObjectID(recordingID: finalizeRequest.recordingID)"))
        #expect(!macHTTPServer.contains("CanonicalObjectID(finalizeRequest.recordingID)"))
        #expect(uploadCoordinator.contains("reasonCode: \"mac_not_paired\""))
        #expect(uploadCoordinator.contains("setActiveStatus(.uploading, for: metadata, job: try? jobStore.loadJob(recordingID: metadata.id))"))
    }

    private static func runtime() -> CanonicalStatusTruthRuntime {
        CanonicalStatusTruthRuntime(nowProvider: { Self.later })
    }

    private static func fact(
        _ id: String,
        source: CanonicalStatusSource,
        kind: CanonicalStatusProofKind,
        producer: CanonicalNodeID = iPhoneNode,
        counter: UInt64 = 1,
        hash: CanonicalHash? = nil,
        byteSize: Int64? = nil,
        causality: CanonicalStatusCausality = .ordinarySync,
        expiry: CanonicalStatusExpiry = .never
    ) -> CanonicalStatusFact {
        CanonicalStatusFact(
            factID: id,
            objectID: objectID,
            source: source,
            producerNodeID: producer,
            logicalTime: CanonicalLogicalTime(counter: counter, nodeID: producer),
            proof: Self.proof(kind, hash: hash, byteSize: byteSize, peer: producer == Self.macNode ? Self.macNode : nil),
            domain: .audioUpload,
            causality: causality,
            expiry: expiry
        )
    }

    private static func fact(
        _ id: String,
        objectID: CanonicalObjectID,
        source: CanonicalStatusSource,
        kind: CanonicalStatusProofKind,
        producer: CanonicalNodeID = iPhoneNode,
        counter: UInt64 = 1,
        hash: CanonicalHash? = nil,
        byteSize: Int64? = nil,
        finalizeProof: CanonicalTransferFinalizeProof? = nil,
        phase: CanonicalStatusPhase? = nil
    ) -> CanonicalStatusFact {
        CanonicalStatusFact(
            factID: id,
            objectID: objectID,
            source: source,
            producerNodeID: producer,
            logicalTime: CanonicalLogicalTime(counter: counter, nodeID: producer),
            proof: CanonicalStatusProof(
                kind: kind,
                objectID: objectID,
                hash: hash,
                byteSize: byteSize,
                peerNodeID: producer == Self.macNode ? Self.macNode : nil,
                finalizeProof: finalizeProof,
                observedAt: Self.now
            ),
            domain: .audioUpload,
            phase: phase
        )
    }

    private static func proof(
        _ kind: CanonicalStatusProofKind,
        hash: CanonicalHash? = nil,
        byteSize: Int64? = nil,
        peer: CanonicalNodeID? = nil
    ) -> CanonicalStatusProof {
        CanonicalStatusProof(
            kind: kind,
            objectID: objectID,
            hash: hash,
            byteSize: byteSize,
            peerNodeID: peer,
            observedAt: now
        )
    }

    private static func finalizeStatusProof() -> CanonicalStatusProof {
        CanonicalStatusProof(
            kind: .finalizeProof,
            objectID: objectID,
            peerNodeID: macNode,
            finalizeProof: CanonicalTransferFinalizeProof.v930(
                receiverNodeID: macNode,
                sessionID: CanonicalTransferSessionID("session-v940"),
                objectID: objectID,
                byteSize: 100,
                contentHash: hashA,
                finalizedAt: now
            ),
            observedAt: now
        )
    }
}
