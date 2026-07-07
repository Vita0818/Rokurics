//
//  CanonicalMainActorHotPathGuard.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalMainActorHotPathKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case fileTreeSnapshot
    case manifestBuild
    case fullHash
    case diagnosticsWrite
    case readProjectionRebuild
    case statusTruthReconciliation
    case effectiveStatusProjection
}

nonisolated struct CanonicalMainActorHotPathCounters: Codable, Equatable, Hashable, Sendable {
    var fileTreeSnapshotAttemptCount: Int = 0
    var manifestBuildAttemptCount: Int = 0
    var fullHashAttemptCount: Int = 0
    var diagnosticsWriteAttemptCount: Int = 0
    var readProjectionRebuildAttemptCount: Int = 0
    var statusTruthReconciliationAttemptCount: Int = 0
    var effectiveStatusProjectionAttemptCount: Int = 0

    nonisolated var totalAttemptCount: Int {
        fileTreeSnapshotAttemptCount
            + manifestBuildAttemptCount
            + fullHashAttemptCount
            + diagnosticsWriteAttemptCount
            + readProjectionRebuildAttemptCount
            + statusTruthReconciliationAttemptCount
            + effectiveStatusProjectionAttemptCount
    }
}

actor CanonicalMainActorHotPathGuard {
    private var counters = CanonicalMainActorHotPathCounters()
    private var reasons: [String] = []
    private let isMainActorHotPath: @Sendable () -> Bool

    init(isMainActorHotPath: @escaping @Sendable () -> Bool = CanonicalInventoryRuntimeExecutionProbe.isMainThread) {
        self.isMainActorHotPath = isMainActorHotPath
    }

    func recordAttempt(kind: CanonicalMainActorHotPathKind, reason: String) {
        guard isMainActorHotPath() else {
            return
        }
        switch kind {
        case .fileTreeSnapshot:
            counters.fileTreeSnapshotAttemptCount += 1
        case .manifestBuild:
            counters.manifestBuildAttemptCount += 1
        case .fullHash:
            counters.fullHashAttemptCount += 1
        case .diagnosticsWrite:
            counters.diagnosticsWriteAttemptCount += 1
        case .readProjectionRebuild:
            counters.readProjectionRebuildAttemptCount += 1
        case .statusTruthReconciliation:
            counters.statusTruthReconciliationAttemptCount += 1
        case .effectiveStatusProjection:
            counters.effectiveStatusProjectionAttemptCount += 1
        }
        if let safeReason = CanonicalFileRuntimeTokenValidator.safeOptionalToken(reason) {
            reasons.append(safeReason)
        }
        if reasons.count > 32 {
            reasons.removeFirst(reasons.count - 32)
        }
    }

    func snapshot() -> CanonicalMainActorHotPathCounters {
        counters
    }

    func redactedReasons() -> [String] {
        reasons
    }

    func reset() {
        counters = CanonicalMainActorHotPathCounters()
        reasons = []
    }
}
