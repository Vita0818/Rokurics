//
//  CanonicalStatusTruthRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated struct CanonicalStatusProjectionSnapshot: Codable, Equatable, Hashable, Sendable {
    var objectID: CanonicalObjectID
    var version: UInt64
    var contentSignature: String
    var effectiveStatus: CanonicalEffectiveSyncStatus
    var statusProjectionDurationMs: Int

    nonisolated init(
        objectID: CanonicalObjectID,
        version: UInt64,
        contentSignature: String,
        effectiveStatus: CanonicalEffectiveSyncStatus,
        statusProjectionDurationMs: Int
    ) {
        self.objectID = objectID
        self.version = version
        self.contentSignature = contentSignature
        self.effectiveStatus = effectiveStatus
        self.statusProjectionDurationMs = max(0, statusProjectionDurationMs)
    }
}

nonisolated struct CanonicalStatusTruthProjectionMetrics: Codable, Equatable, Hashable, Sendable {
    var projectionVersion: UInt64 = 0
    var projectedCount: Int = 0
    var projectionCacheHitCount: Int = 0
    var statusProjectionDurationMs: Int = 0
    var mainActorStatusReconciliationAttemptCount: Int = 0
}

private struct CanonicalCachedStatusProjection: Sendable {
    var snapshot: CanonicalStatusProjectionSnapshot
    var reconciliation: CanonicalStatusReconciliation
}

actor CanonicalStatusTruthRuntime: CanonicalStatusTruthEngine {
    private let factStore: CanonicalStatusFactStore
    private let nowProvider: @Sendable () -> CanonicalTimestamp
    private let isMainActorStatusReconciliationAttempt: @Sendable () -> Bool
    private var diagnostics: [CanonicalStatusTruthDiagnosticRecord] = []
    private let maxDiagnosticRecords: Int
    private var projectionCacheByObjectID: [CanonicalObjectID: CanonicalCachedStatusProjection] = [:]
    private var projectionCacheBySignature: [String: CanonicalCachedStatusProjection] = [:]
    private var projectionMetrics = CanonicalStatusTruthProjectionMetrics()

    init(
        factStore: CanonicalStatusFactStore = CanonicalStatusFactStore(),
        nowProvider: @escaping @Sendable () -> CanonicalTimestamp = { CanonicalTimestamp(Date()) },
        maxDiagnosticRecords: Int = 128,
        isMainActorStatusReconciliationAttempt: @escaping @Sendable () -> Bool = { false }
    ) {
        self.factStore = factStore
        self.nowProvider = nowProvider
        self.isMainActorStatusReconciliationAttempt = isMainActorStatusReconciliationAttempt
        self.maxDiagnosticRecords = max(1, maxDiagnosticRecords)
    }

    func produce(_ fact: CanonicalStatusFact) async -> CanonicalStatusFactMergeResult {
        appendDiagnostic(
            CanonicalStatusTruthDiagnosticRecord(
                event: .statusFactProduced,
                objectID: fact.objectID,
                domain: fact.domain,
                factID: fact.factID,
                source: fact.source,
                phase: fact.phase,
                hash: fact.proof.hash,
                byteSize: fact.proof.byteSize,
                detail: fact.proof.kind.rawValue
            )
        )
        let result = await factStore.merge(fact, now: nowProvider())
        appendDiagnostics(result.diagnostics)
        await rebuildProjectionForObject(fact.objectID, reason: "factProduced")
        return result
    }

    func produce(_ facts: [CanonicalStatusFact]) async -> [CanonicalStatusFactMergeResult] {
        var results: [CanonicalStatusFactMergeResult] = []
        for fact in facts {
            results.append(await produce(fact))
        }
        return results
    }

    func facts(for objectID: CanonicalObjectID) async -> [CanonicalStatusFact] {
        await factStore.facts(for: objectID, now: nowProvider())
    }

    func allFactsSnapshot() async -> [CanonicalStatusFact] {
        await factStore.allFacts(now: nowProvider())
    }

    func effectiveStatus(for objectID: CanonicalObjectID) async -> CanonicalEffectiveSyncStatus {
        if let cached = projectionCacheByObjectID[objectID] {
            projectionMetrics.projectionCacheHitCount += 1
            return cached.snapshot.effectiveStatus
        }
        if let cached = await rebuildProjectionForObject(objectID, reason: "cacheMiss") {
            return cached.snapshot.effectiveStatus
        }
        return CanonicalEffectiveSyncStatus(
            objectID: objectID,
            domain: .audioUpload,
            phase: .deferred,
            displayState: .waiting,
            blocker: .peerProofUnavailable
        )
    }

    func effectiveStatus(for facts: [CanonicalStatusFact]) async -> CanonicalEffectiveSyncStatus {
        let reconciliation = try? await cachedReconciliation(facts: facts, reason: "directFactsEffectiveStatus")
        return reconciliation?.effectiveStatus ?? CanonicalEffectiveSyncStatus.peerUnknownDeferred
    }

    func reconcile(facts: [CanonicalStatusFact]) async throws -> CanonicalStatusReconciliation {
        try await cachedReconciliation(facts: facts, reason: "explicitReconcile")
    }

    func diagnosticRecords() async -> [CanonicalStatusTruthDiagnosticRecord] {
        let storeDiagnostics = await factStore.diagnosticRecords()
        return storeDiagnostics + diagnostics
    }

    func projectionSnapshot(for objectID: CanonicalObjectID) -> CanonicalStatusProjectionSnapshot? {
        projectionCacheByObjectID[objectID]?.snapshot
    }

    func projectionMetricsSnapshot() -> CanonicalStatusTruthProjectionMetrics {
        projectionMetrics
    }

    func reset() async {
        await factStore.removeAll()
        diagnostics.removeAll()
        projectionCacheByObjectID.removeAll()
        projectionCacheBySignature.removeAll()
        projectionMetrics = CanonicalStatusTruthProjectionMetrics()
    }

    @discardableResult
    private func rebuildProjectionForObject(
        _ objectID: CanonicalObjectID,
        reason: String
    ) async -> CanonicalCachedStatusProjection? {
        let now = nowProvider()
        let prunedObjectIDs = await factStore.pruneExpired(now: now)
        for prunedObjectID in prunedObjectIDs {
            projectionCacheByObjectID.removeValue(forKey: prunedObjectID)
        }
        let currentFacts = await factStore.facts(for: objectID, now: now)
        guard currentFacts.isEmpty == false else {
            projectionCacheByObjectID.removeValue(forKey: objectID)
            return nil
        }
        let cached = buildProjection(facts: currentFacts, now: now, reason: reason)
        projectionCacheByObjectID[objectID] = cached
        projectionCacheBySignature[cached.snapshot.contentSignature] = cached
        return cached
    }

    private func cachedReconciliation(
        facts: [CanonicalStatusFact],
        reason: String
    ) async throws -> CanonicalStatusReconciliation {
        let now = nowProvider()
        let signature = Self.factsContentSignature(facts, now: now)
        if let cached = projectionCacheBySignature[signature] {
            projectionMetrics.projectionCacheHitCount += 1
            return cached.reconciliation
        }
        let cached = buildProjection(facts: facts, now: now, reason: reason)
        projectionCacheBySignature[signature] = cached
        projectionCacheByObjectID[cached.snapshot.objectID] = cached
        return cached.reconciliation
    }

    private func buildProjection(
        facts: [CanonicalStatusFact],
        now: CanonicalTimestamp,
        reason: String
    ) -> CanonicalCachedStatusProjection {
        if isMainActorStatusReconciliationAttempt() {
            projectionMetrics.mainActorStatusReconciliationAttemptCount += 1
            appendDiagnostic(
                CanonicalStatusTruthDiagnosticRecord(
                    event: .mainActorStatusReconciliationAttemptCount,
                    phase: .blocked,
                    detail: "count=\(projectionMetrics.mainActorStatusReconciliationAttemptCount),reason=\(reason)"
                )
            )
        }

        let startedAt = now
        let result = CanonicalStatusReconciliationRuntime.reconcile(facts: facts, now: now)
        let endedAt = nowProvider()
        let durationMs = max(0, Int(endedAt.date.timeIntervalSince(startedAt.date) * 1_000))
        projectionMetrics.projectionVersion += 1
        projectionMetrics.projectedCount += 1
        projectionMetrics.statusProjectionDurationMs += durationMs
        appendDiagnostics(result.diagnostics)
        appendDiagnostic(
            CanonicalStatusTruthDiagnosticRecord(
                event: .statusProjectionDurationMs,
                objectID: result.reconciliation.objectID,
                domain: result.reconciliation.effectiveStatus.domain,
                phase: result.reconciliation.effectiveStatus.phase,
                detail: "statusProjectionDurationMs=\(durationMs),version=\(projectionMetrics.projectionVersion),reason=\(reason)"
            )
        )
        let signature = Self.factsContentSignature(facts, now: now)
        return CanonicalCachedStatusProjection(
            snapshot: CanonicalStatusProjectionSnapshot(
                objectID: result.reconciliation.objectID,
                version: projectionMetrics.projectionVersion,
                contentSignature: signature,
                effectiveStatus: result.reconciliation.effectiveStatus,
                statusProjectionDurationMs: durationMs
            ),
            reconciliation: result.reconciliation
        )
    }

    private func appendDiagnostics(_ records: [CanonicalStatusTruthDiagnosticRecord]) {
        for record in records {
            appendDiagnostic(record)
        }
    }

    private func appendDiagnostic(_ record: CanonicalStatusTruthDiagnosticRecord) {
        diagnostics.append(record)
        if diagnostics.count > maxDiagnosticRecords {
            diagnostics.removeFirst(diagnostics.count - maxDiagnosticRecords)
        }
    }

    private nonisolated static func factsContentSignature(
        _ facts: [CanonicalStatusFact],
        now: CanonicalTimestamp
    ) -> String {
        CanonicalStatusFactStore.deterministicOrder(facts)
            .filter { !$0.isExpired(now: now) }
            .map(factSignature)
            .joined(separator: "|")
    }

    private nonisolated static func factSignature(_ fact: CanonicalStatusFact) -> String {
        [
            fact.objectID.rawValue,
            fact.domain.rawValue,
            fact.phase.rawValue,
            fact.source.rawValue,
            fact.factID.rawValue,
            "\(fact.logicalTime.counter)",
            fact.logicalTime.nodeID.rawValue,
            proofSignature(fact.proof),
            fact.causality.trigger.rawValue,
            fact.causality.replacesFactIDs.map(\.rawValue).joined(separator: ","),
            fact.causality.causedByFactIDs.map(\.rawValue).joined(separator: ","),
            "\(fact.causality.permitsManualPeerUnknownUpload)",
            fact.expiry.staleAfter.map { "\($0.date.timeIntervalSince1970)" } ?? "stale=none",
            fact.expiry.expiresAt.map { "\($0.date.timeIntervalSince1970)" } ?? "expires=none"
        ].joined(separator: ":")
    }

    private nonisolated static func proofSignature(_ proof: CanonicalStatusProof) -> String {
        let hash = proof.hash?.value ?? "hash=none"
        let byteSize = proof.byteSize.map { String($0) } ?? "bytes=none"
        let peerNodeID = proof.peerNodeID?.rawValue ?? "peer=none"
        let finalize = proof.finalizeProof.map { finalizeProofSignature($0) } ?? "finalize=none"
        let proofChain = proof.proofChain?.map { proofSignature($0) }.joined(separator: ",") ?? "chain=none"
        let observedAt = String(proof.observedAt.date.timeIntervalSince1970)
        let expiresAt = proof.expiresAt.map { String($0.date.timeIntervalSince1970) } ?? "proofExpires=none"
        return [
            proof.kind.rawValue,
            proof.objectID.rawValue,
            hash,
            byteSize,
            peerNodeID,
            finalize,
            proof.ackID ?? "ack=none",
            proof.schemaVersion ?? "schema=none",
            proofChain,
            observedAt,
            expiresAt
        ].joined(separator: "#")
    }

    private nonisolated static func finalizeProofSignature(_ proof: CanonicalTransferFinalizeProof) -> String {
        [
            proof.receiverNodeID.rawValue,
            proof.sessionID.rawValue,
            proof.objectID.rawValue,
            "\(proof.byteSize)",
            proof.contentHash.value,
            "\(proof.finalizedAt.date.timeIntervalSince1970)",
            "\(proof.verified)"
        ].joined(separator: "#")
    }
}
