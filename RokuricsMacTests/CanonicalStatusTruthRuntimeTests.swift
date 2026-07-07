//
//  CanonicalStatusTruthRuntimeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/14.
//

import Foundation
import Testing
@testable import RokuricsMac

@Suite(.serialized)
struct CanonicalStatusTruthRuntimeTests {
    private static let now = CanonicalTimestamp(Date(timeIntervalSince1970: 9_400))
    private static let later = CanonicalTimestamp(Date(timeIntervalSince1970: 9_401))
    private static let objectID = CanonicalObjectID("recording-v940")
    private static let iPhoneNode = CanonicalNodeID("iphone-node")
    private static let macNode = CanonicalNodeID("mac-node")
    private static let hashA = CanonicalHash(String(repeating: "d", count: 64))

    @Test func partialReceiveIsNeverCompleted() async throws {
        let runtime = Self.runtime()
        let partial = Self.fact("partial-receive", source: .partialReceive, kind: .partialReceive, phase: .partialReceive)

        _ = await runtime.produce(partial)
        let reconciliation = try await runtime.reconcile(facts: await runtime.facts(for: Self.objectID))

        #expect(reconciliation.effectiveStatus.phase == CanonicalStatusPhase.partialReceive)
        #expect(reconciliation.effectiveStatus.canDisplayAsComplete == false)
        #expect(reconciliation.effectiveStatus.canCreateUploadJob == false)
        #expect(reconciliation.effectiveStatus.blocker == CanonicalStatusBlocker.partialReceiveRejectedAsCompleted)
        #expect(reconciliation.blockers.contains(CanonicalStatusHardRule.partialReceiveIsNotCompleted))
    }

    @Test func finalizeProofProjectsCompletedAndPeerVerifiedSemantics() async throws {
        let runtime = Self.runtime()
        let finalize = Self.fact(
            "finalize-proof",
            source: .transferFinalizeProof,
            kind: .finalizeProof,
            phase: .completed,
            proofOverride: Self.finalizeProof()
        )

        _ = await runtime.produce(finalize)
        let status = try await runtime.reconcile(facts: await runtime.facts(for: Self.objectID)).effectiveStatus

        #expect(status.phase == CanonicalStatusPhase.completed)
        #expect(status.displayState == CanonicalStatusDisplayState.complete)
        #expect(status.canDisplayAsComplete)
        #expect(status.canSuppressLegacyDuplicate)
        #expect(status.canCreateUploadJob == false)
        #expect(status.proof?.hasAcceptedFinalizeProof == true)
    }

    @Test func metadataOnlyLedgerDoesNotMeanAudioAvailable() async throws {
        let runtime = Self.runtime()
        let metadataOnly = Self.fact(
            "metadata-only-ledger",
            source: .metadataOnlyLedger,
            kind: .metadataOnly,
            phase: .metadataOnly
        )

        _ = await runtime.produce(metadataOnly)
        let reconciliation = try await runtime.reconcile(facts: await runtime.facts(for: Self.objectID))

        #expect(reconciliation.effectiveStatus.phase == CanonicalStatusPhase.peerKnownMetadataOnly)
        #expect(reconciliation.effectiveStatus.canDisplayAsComplete == false)
        #expect(reconciliation.effectiveStatus.canCreateUploadJob == false)
        #expect(reconciliation.effectiveStatus.blocker == CanonicalStatusBlocker.metadataOnlyRejectedAsAudioProof)
        #expect(reconciliation.blockers.contains(CanonicalStatusHardRule.metadataOnlyIsNotAudioAvailable))
    }

    @Test func receiveRecordOnlyDoesNotMeanAudioAvailable() async throws {
        let runtime = Self.runtime()
        let receiveOnly = Self.fact(
            "receive-record-only",
            source: .peerReceiveRecord,
            kind: .receiveRecordOnly,
            phase: .peerKnownMetadataOnly
        )

        _ = await runtime.produce(receiveOnly)
        let status = try await runtime.reconcile(facts: await runtime.facts(for: Self.objectID)).effectiveStatus

        #expect(status.phase == CanonicalStatusPhase.peerKnownMetadataOnly)
        #expect(status.canDisplayAsComplete == false)
        #expect(status.blocker == CanonicalStatusBlocker.receiveRecordOnlyRejectedAsAudioProof)
    }

    @Test func staleFactCannotOverrideFreshFinalizeProof() async throws {
        let staleMetadata = Self.fact(
            "stale-metadata",
            source: .peerMetadata,
            kind: .metadataOnly,
            counter: 1,
            expiry: CanonicalStatusExpiry(staleAfter: Self.now)
        )
        let freshFinalize = Self.fact(
            "fresh-finalize",
            source: .transferFinalizeProof,
            kind: .finalizeProof,
            phase: .completed,
            counter: 2,
            proofOverride: Self.finalizeProof()
        )
        let status = try await Self.runtime().reconcile(facts: [staleMetadata, freshFinalize]).effectiveStatus

        #expect(status.phase == CanonicalStatusPhase.completed)
        #expect(status.canDisplayAsComplete)
        #expect(status.blocker == nil)
    }

    @Test func statusTruthProjectionCacheServesEffectiveStatusWithoutMainActorReconciliation() async {
        let runtime = Self.runtime()
        let finalize = Self.fact(
            "finalize-proof",
            source: .transferFinalizeProof,
            kind: .finalizeProof,
            phase: .completed,
            proofOverride: Self.finalizeProof()
        )

        _ = await runtime.produce(finalize)
        let beforeRead = await runtime.projectionMetricsSnapshot()
        let first = await runtime.effectiveStatus(for: Self.objectID)
        let second = await runtime.effectiveStatus(for: Self.objectID)
        let afterRead = await runtime.projectionMetricsSnapshot()
        let snapshot = await runtime.projectionSnapshot(for: Self.objectID)
        let diagnostics = await runtime.diagnosticRecords()

        #expect(first == second)
        #expect(first.phase == .completed)
        #expect(snapshot?.effectiveStatus == first)
        #expect(snapshot?.version == beforeRead.projectionVersion)
        #expect(afterRead.projectedCount == beforeRead.projectedCount)
        #expect(afterRead.projectionCacheHitCount >= beforeRead.projectionCacheHitCount + 2)
        #expect(afterRead.mainActorStatusReconciliationAttemptCount == 0)
        #expect(diagnostics.contains { $0.event == .statusProjectionDurationMs })
        #expect(diagnostics.contains { $0.event == .effectiveStatusProjected })
    }

    @Test func macAdaptersExposeStatusTruthReadPathWithoutRouteOrSchemaMutation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let receiver = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/SecureReceiverService.swift"),
            encoding: .utf8
        )
        let server = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/SecureLocalHTTPSServer.swift"),
            encoding: .utf8
        )
        let studyStore = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/StudyLibraryStore.swift"),
            encoding: .utf8
        )
        let fileStore = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/MacRecordingFileStore.swift"),
            encoding: .utf8
        )

        for source in [receiver, server, studyStore, fileStore] {
            #expect(source.contains("canonicalStatusTruthRuntime"))
            #expect(source.contains("produceCanonicalStatusFact(_ fact: CanonicalStatusFact)"))
        }
        #expect(receiver.contains("effectiveSyncStatusByObjectID"))
        #expect(receiver.contains("func effectiveSyncStatus(for objectID: CanonicalObjectID) -> CanonicalEffectiveSyncStatus?"))
        #expect(studyStore.contains("effectiveSyncStatusByObjectID"))
        #expect(studyStore.contains("func effectiveSyncStatus(for objectID: CanonicalObjectID) -> CanonicalEffectiveSyncStatus?"))
        #expect(server.contains("handleSecureUploadRequest"))
        #expect(server.contains("handleRecordingMetadataUploadRequest"))
        #expect(server.contains("handleRecordingAudioUploadRequest"))
        #expect(server.contains("RequestVerifier"))
        #expect(server.contains("canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime? = nil"))
    }

    @Test func statusTruthDiagnosticsStayRedactedOnMac() async throws {
        let runtime = Self.runtime()
        let fact = Self.fact("metadata-only-ledger", source: .metadataOnlyLedger, kind: .metadataOnly)

        _ = await runtime.produce(fact)
        _ = try await runtime.reconcile(facts: await runtime.facts(for: Self.objectID))
        let diagnostics = await runtime.diagnosticRecords()
        let containsMetadataOnlyRejection = diagnostics.contains {
            $0.event == CanonicalStatusTruthDiagnosticEvent.metadataOnlyRejectedAsAudioProof
        }
        let allRedacted = diagnostics.allSatisfy { $0.isRedacted }
        let allDetailsPathFree = diagnostics.allSatisfy { ($0.redactedDetail ?? "").contains("/Users/") == false }
        let allHashPrefixesShort = diagnostics.allSatisfy { ($0.hashPrefix?.count ?? 0) <= 12 }

        #expect(containsMetadataOnlyRejection)
        #expect(allRedacted)
        #expect(allDetailsPathFree)
        #expect(allHashPrefixesShort)
    }

    private static func runtime() -> CanonicalStatusTruthRuntime {
        CanonicalStatusTruthRuntime(nowProvider: { Self.later })
    }

    private static func fact(
        _ id: String,
        source: CanonicalStatusSource,
        kind: CanonicalStatusProofKind,
        phase: CanonicalStatusPhase? = nil,
        counter: UInt64 = 1,
        expiry: CanonicalStatusExpiry = .never,
        proofOverride: CanonicalStatusProof? = nil
    ) -> CanonicalStatusFact {
        CanonicalStatusFact(
            factID: id,
            objectID: Self.objectID,
            source: source,
            producerNodeID: Self.macNode,
            logicalTime: CanonicalLogicalTime(counter: counter, nodeID: Self.macNode),
            proof: proofOverride ?? CanonicalStatusProof(
                kind: kind,
                objectID: Self.objectID,
                peerNodeID: Self.iPhoneNode,
                observedAt: Self.now
            ),
            domain: .audioUpload,
            phase: phase,
            expiry: expiry
        )
    }

    private static func finalizeProof() -> CanonicalStatusProof {
        CanonicalStatusProof(
            kind: .finalizeProof,
            objectID: Self.objectID,
            peerNodeID: Self.iPhoneNode,
            finalizeProof: CanonicalTransferFinalizeProof.v930(
                receiverNodeID: Self.macNode,
                sessionID: CanonicalTransferSessionID("session-v940-mac"),
                objectID: Self.objectID,
                byteSize: 512,
                contentHash: Self.hashA,
                finalizedAt: Self.now
            ),
            observedAt: Self.now
        )
    }
}
