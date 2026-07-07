//
//  CanonicalConflictResolver.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalConflictResolverAction: String, Codable, Equatable, Sendable {
    case recordOnly
    case keepBothNoOverwrite
    case requireManualReview
    case tombstoneManualReview
}

nonisolated struct CanonicalConflictResolutionDecision: Codable, Equatable, Identifiable, Sendable {
    var id: String { conflictID }
    var conflictID: String
    var target: CanonicalApplyTarget
    var action: CanonicalConflictResolverAction
    var state: CanonicalConflictResolutionState
    var detail: String?
}

nonisolated struct CanonicalConflictResolverReport: Codable, Equatable, Sendable {
    var decisions: [CanonicalConflictResolutionDecision]
    var unresolvedCount: Int
    var manualReviewCount: Int
    var keepBothCount: Int
}

nonisolated struct CanonicalConflictResolver {
    nonisolated init() {}

    nonisolated func resolve(
        conflicts: [CanonicalConflictRecord],
        libraryConflicts: [CanonicalLibraryConflict] = []
    ) -> CanonicalConflictResolverReport {
        let recordingDecisions = conflicts.map(decision)
        let libraryDecisions = libraryConflicts.map(decision)
        let decisions = (recordingDecisions + libraryDecisions).sorted { $0.conflictID < $1.conflictID }
        return CanonicalConflictResolverReport(
            decisions: decisions,
            unresolvedCount: decisions.filter { $0.state == .unresolved }.count,
            manualReviewCount: decisions.filter { $0.action == .requireManualReview || $0.action == .tombstoneManualReview }.count,
            keepBothCount: decisions.filter { $0.action == .keepBothNoOverwrite }.count
        )
    }

    private func decision(_ conflict: CanonicalConflictRecord) -> CanonicalConflictResolutionDecision {
        let action: CanonicalConflictResolverAction
        switch conflict.resolutionPolicy {
        case .manualReview:
            action = .requireManualReview
        case .keepBothNoOverwrite:
            action = .keepBothNoOverwrite
        case .tombstoneRequiresManualReview:
            action = .tombstoneManualReview
        }
        return CanonicalConflictResolutionDecision(
            conflictID: conflict.conflictID,
            target: conflict.target,
            action: action,
            state: .unresolved,
            detail: conflict.kind.rawValue
        )
    }

    private func decision(_ conflict: CanonicalLibraryConflict) -> CanonicalConflictResolutionDecision {
        let action: CanonicalConflictResolverAction = conflict.kind == .activeVsTombstone
            ? .tombstoneManualReview
            : .requireManualReview
        return CanonicalConflictResolutionDecision(
            conflictID: conflict.conflictID,
            target: CanonicalApplyTarget(objectID: conflict.objectID.rawValue),
            action: action,
            state: .unresolved,
            detail: conflict.kind.rawValue
        )
    }
}
