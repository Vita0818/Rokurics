//
//  CanonicalStatusFactStore.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalStatusFactMergeDecision: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case merged
    case replaced
    case ignoredOlderDuplicate
    case rejectedExpired
    case rejectedStale
}

nonisolated struct CanonicalStatusFactMergeResult: Codable, Equatable, Hashable, Sendable {
    var factID: CanonicalStatusFactID
    var objectID: CanonicalObjectID
    var decision: CanonicalStatusFactMergeDecision
    var diagnostics: [CanonicalStatusTruthDiagnosticRecord]

    nonisolated init(
        factID: CanonicalStatusFactID,
        objectID: CanonicalObjectID,
        decision: CanonicalStatusFactMergeDecision,
        diagnostics: [CanonicalStatusTruthDiagnosticRecord] = []
    ) {
        self.factID = factID
        self.objectID = objectID
        self.decision = decision
        self.diagnostics = diagnostics
    }
}

actor CanonicalStatusFactStore {
    private var factsByID: [CanonicalStatusFactID: CanonicalStatusFact] = [:]
    private var diagnostics: [CanonicalStatusTruthDiagnosticRecord] = []
    private let maxDiagnosticRecords: Int

    init(maxDiagnosticRecords: Int = 128) {
        self.maxDiagnosticRecords = max(1, maxDiagnosticRecords)
    }

    func merge(
        _ fact: CanonicalStatusFact,
        now: CanonicalTimestamp = CanonicalTimestamp(Date())
    ) -> CanonicalStatusFactMergeResult {
        if fact.isExpired(now: now) {
            return reject(fact, decision: .rejectedExpired, event: .statusProofExpired, detail: "expired")
        }

        for replacedID in fact.causality.replacesFactIDs {
            factsByID.removeValue(forKey: replacedID)
        }

        if let existing = factsByID[fact.factID],
           Self.ordersBefore(fact, existing) == false {
            return reject(fact, decision: .ignoredOlderDuplicate, event: .statusFactRejected, detail: "olderDuplicate")
        }

        factsByID[fact.factID] = fact
        let decision: CanonicalStatusFactMergeDecision = fact.causality.replacesFactIDs.isEmpty ? .merged : .replaced
        let record = CanonicalStatusTruthDiagnosticRecord(
            event: .statusFactMerged,
            objectID: fact.objectID,
            domain: fact.domain,
            factID: fact.factID,
            source: fact.source,
            phase: fact.phase,
            hash: fact.proof.hash,
            byteSize: fact.proof.byteSize,
            detail: decision.rawValue
        )
        appendDiagnostic(record)
        return CanonicalStatusFactMergeResult(
            factID: fact.factID,
            objectID: fact.objectID,
            decision: decision,
            diagnostics: [record]
        )
    }

    func merge(
        _ facts: [CanonicalStatusFact],
        now: CanonicalTimestamp = CanonicalTimestamp(Date())
    ) -> [CanonicalStatusFactMergeResult] {
        facts.map { merge($0, now: now) }
    }

    func facts(
        for objectID: CanonicalObjectID,
        now: CanonicalTimestamp = CanonicalTimestamp(Date()),
        includeExpired: Bool = false
    ) -> [CanonicalStatusFact] {
        Self.deterministicOrder(
            Array(factsByID.values.filter { fact in
                fact.objectID == objectID && (includeExpired || !fact.isExpired(now: now))
            })
        )
    }

    func allFacts(
        now: CanonicalTimestamp = CanonicalTimestamp(Date()),
        includeExpired: Bool = false
    ) -> [CanonicalStatusFact] {
        Self.deterministicOrder(Array(factsByID.values.filter { includeExpired || !$0.isExpired(now: now) }))
    }

    func pruneExpired(now: CanonicalTimestamp = CanonicalTimestamp(Date())) -> [CanonicalObjectID] {
        let expiredFacts = factsByID.values.filter { $0.isExpired(now: now) }
        guard expiredFacts.isEmpty == false else {
            return []
        }
        for fact in expiredFacts {
            factsByID.removeValue(forKey: fact.factID)
            appendDiagnostic(
                CanonicalStatusTruthDiagnosticRecord(
                    event: .statusProofExpired,
                    objectID: fact.objectID,
                    domain: fact.domain,
                    factID: fact.factID,
                    source: fact.source,
                    phase: fact.phase,
                    hash: fact.proof.hash,
                    byteSize: fact.proof.byteSize,
                    detail: "pruned"
                )
            )
        }
        return Array(Set(expiredFacts.map(\.objectID))).sorted()
    }

    func diagnosticRecords() -> [CanonicalStatusTruthDiagnosticRecord] {
        diagnostics
    }

    func removeAll() {
        factsByID.removeAll()
        diagnostics.removeAll()
    }

    private func reject(
        _ fact: CanonicalStatusFact,
        decision: CanonicalStatusFactMergeDecision,
        event: CanonicalStatusTruthDiagnosticEvent,
        detail: String
    ) -> CanonicalStatusFactMergeResult {
        let record = CanonicalStatusTruthDiagnosticRecord(
            event: event,
            objectID: fact.objectID,
            domain: fact.domain,
            factID: fact.factID,
            source: fact.source,
            phase: fact.phase,
            hash: fact.proof.hash,
            byteSize: fact.proof.byteSize,
            detail: detail
        )
        appendDiagnostic(record)
        return CanonicalStatusFactMergeResult(
            factID: fact.factID,
            objectID: fact.objectID,
            decision: decision,
            diagnostics: [record]
        )
    }

    private func appendDiagnostic(_ record: CanonicalStatusTruthDiagnosticRecord) {
        diagnostics.append(record)
        if diagnostics.count > maxDiagnosticRecords {
            diagnostics.removeFirst(diagnostics.count - maxDiagnosticRecords)
        }
    }

    nonisolated static func deterministicOrder(_ facts: [CanonicalStatusFact]) -> [CanonicalStatusFact] {
        facts.sorted { left, right in
            if left.objectID != right.objectID { return left.objectID < right.objectID }
            if left.domain != right.domain { return left.domain.rawValue < right.domain.rawValue }
            if left.logicalTime != right.logicalTime { return right.logicalTime < left.logicalTime }
            if left.proof.observedAt != right.proof.observedAt { return right.proof.observedAt < left.proof.observedAt }
            if left.source != right.source { return left.source.rawValue < right.source.rawValue }
            return left.factID < right.factID
        }
    }

    private nonisolated static func ordersBefore(_ incoming: CanonicalStatusFact, _ existing: CanonicalStatusFact) -> Bool {
        if incoming.objectID != existing.objectID { return incoming.objectID < existing.objectID }
        if incoming.domain != existing.domain { return incoming.domain.rawValue < existing.domain.rawValue }
        if incoming.logicalTime != existing.logicalTime { return existing.logicalTime < incoming.logicalTime }
        if incoming.proof.observedAt != existing.proof.observedAt {
            return existing.proof.observedAt < incoming.proof.observedAt
        }
        if incoming.source != existing.source { return incoming.source.rawValue < existing.source.rawValue }
        return incoming.factID <= existing.factID
    }
}
