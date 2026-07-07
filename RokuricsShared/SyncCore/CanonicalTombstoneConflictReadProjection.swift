//
//  CanonicalTombstoneConflictReadProjection.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated enum CanonicalTombstoneConflictReadProjectionSource: String, Codable, Equatable, Hashable, Sendable {
    case legacy
    case canonical
}

nonisolated enum CanonicalTombstoneConflictDeletedDisplayState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case active
    case deleted
    case trashed
    case tombstoned
    case unknown
}

nonisolated enum CanonicalTombstoneConflictStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case none
    case recorded
    case unresolved
    case manualReviewRequired
}

nonisolated enum CanonicalTombstoneConflictAntiResurrectionStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case notTriggered
    case blocked
    case risk
    case explicitRestoreRequired
}

nonisolated enum CanonicalTombstoneConflictReadProjectionFailureKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case snapshotMissing
    case unsupportedObjectKind
    case pathLeakRisk
    case fullMetadataRejected
    case fullContentRejected
    case physicalDeleteRisk
    case permanentDeleteRisk
    case tombstoneGCRisk
    case staleLiveResurrectionRisk
    case autoConflictResolutionRisk
}

nonisolated struct CanonicalTombstoneConflictReadProjectionFailure: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "run", objectKind?.rawValue ?? "unknown", reason].joined(separator: "|") }

    var kind: CanonicalTombstoneConflictReadProjectionFailureKind
    var source: CanonicalTombstoneConflictReadProjectionSource
    var objectID: String?
    var objectKind: CanonicalObjectKind?
    var reason: String

    nonisolated init(
        kind: CanonicalTombstoneConflictReadProjectionFailureKind,
        source: CanonicalTombstoneConflictReadProjectionSource,
        objectID: String? = nil,
        objectKind: CanonicalObjectKind? = nil,
        reason: String
    ) {
        self.kind = kind
        self.source = source
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "tombstone-object") }
        self.objectKind = objectKind
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? kind.rawValue
    }
}

nonisolated struct CanonicalTombstoneConflictReadProjectionFact: Codable, Equatable, Sendable {
    var objectID: String
    var objectKind: CanonicalObjectKind
    var tombstoneState: CanonicalTombstoneState
    var deletedDisplayState: CanonicalTombstoneConflictDeletedDisplayState
    var tombstoneTimestamp: CanonicalTimestamp?
    var conflictKind: String?
    var conflictStatus: CanonicalTombstoneConflictStatus
    var activeVsTombstoneState: String
    var antiResurrectionStatus: CanonicalTombstoneConflictAntiResurrectionStatus
    var parentObjectTombstoned: Bool
    var generatedArtifactResurrectionBlocked: Bool
    var softDeleteMarkerPresent: Bool
    var hashPrefix: String?
    var unsupportedObjectKind: Bool
    var pathLeakRisk: Bool
    var fullMetadataIncluded: Bool
    var fullContentIncluded: Bool
    var physicalDeleteRisk: Bool
    var permanentDeleteRisk: Bool
    var tombstoneGCRisk: Bool
    var staleLiveResurrectionRisk: Bool
    var autoConflictResolutionRisk: Bool

    nonisolated init(
        objectID: String,
        objectKind: CanonicalObjectKind,
        tombstoneState: CanonicalTombstoneState = .active,
        deletedDisplayState: CanonicalTombstoneConflictDeletedDisplayState = .active,
        tombstoneTimestamp: CanonicalTimestamp? = nil,
        conflictKind: String? = nil,
        conflictStatus: CanonicalTombstoneConflictStatus = .none,
        activeVsTombstoneState: String = "activeOnly",
        antiResurrectionStatus: CanonicalTombstoneConflictAntiResurrectionStatus = .notTriggered,
        parentObjectTombstoned: Bool = false,
        generatedArtifactResurrectionBlocked: Bool = false,
        softDeleteMarkerPresent: Bool = false,
        hashPrefix: String? = nil,
        unsupportedObjectKind: Bool = false,
        pathLeakRisk: Bool = false,
        fullMetadataIncluded: Bool = false,
        fullContentIncluded: Bool = false,
        physicalDeleteRisk: Bool = false,
        permanentDeleteRisk: Bool = false,
        tombstoneGCRisk: Bool = false,
        staleLiveResurrectionRisk: Bool = false,
        autoConflictResolutionRisk: Bool = false
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "tombstone-object")
        self.objectKind = objectKind
        self.tombstoneState = tombstoneState
        self.deletedDisplayState = deletedDisplayState
        self.tombstoneTimestamp = tombstoneTimestamp
        self.conflictKind = conflictKind.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.conflictStatus = conflictStatus
        self.activeVsTombstoneState = CanonicalProductionRedaction.safeDiagnosticText(activeVsTombstoneState) ?? "activeOnly"
        self.antiResurrectionStatus = antiResurrectionStatus
        self.parentObjectTombstoned = parentObjectTombstoned
        self.generatedArtifactResurrectionBlocked = generatedArtifactResurrectionBlocked
        self.softDeleteMarkerPresent = softDeleteMarkerPresent
        self.hashPrefix = CanonicalProductionRedaction.hashPrefix(hashPrefix)
        self.unsupportedObjectKind = unsupportedObjectKind
        self.pathLeakRisk = pathLeakRisk
        self.fullMetadataIncluded = fullMetadataIncluded
        self.fullContentIncluded = fullContentIncluded
        self.physicalDeleteRisk = physicalDeleteRisk
        self.permanentDeleteRisk = permanentDeleteRisk
        self.tombstoneGCRisk = tombstoneGCRisk
        self.staleLiveResurrectionRisk = staleLiveResurrectionRisk
        self.autoConflictResolutionRisk = autoConflictResolutionRisk
    }
}

nonisolated struct CanonicalTombstoneConflictReadProjectionItem: Codable, Equatable, Identifiable, Sendable {
    var id: String { [objectID, objectKind.rawValue].joined(separator: "|") }

    var source: CanonicalTombstoneConflictReadProjectionSource
    var objectID: String
    var objectKind: CanonicalObjectKind
    var tombstoneState: CanonicalTombstoneState
    var deletedDisplayState: CanonicalTombstoneConflictDeletedDisplayState
    var tombstoneTimestampSummary: String
    var conflictKind: String
    var conflictStatus: CanonicalTombstoneConflictStatus
    var activeVsTombstoneState: String
    var antiResurrectionStatus: CanonicalTombstoneConflictAntiResurrectionStatus
    var parentObjectStateSummary: String
    var generatedArtifactResurrectionBlocked: Bool
    var softDeleteMarkerPresent: Bool
    var hashPrefix: String?
    var fullMetadataIncluded: Bool
    var fullContentIncluded: Bool
    var absolutePathIncluded: Bool
    var physicalDeleteTargetPathIncluded: Bool
    var physicalDeleteRisk: Bool
    var permanentDeleteRisk: Bool
    var tombstoneGCRisk: Bool
    var autoConflictResolutionRisk: Bool
    var staleLiveResurrectionRisk: Bool

    nonisolated init(source: CanonicalTombstoneConflictReadProjectionSource, fact: CanonicalTombstoneConflictReadProjectionFact) {
        self.source = source
        self.objectID = fact.objectID
        self.objectKind = fact.objectKind
        self.tombstoneState = fact.tombstoneState
        self.deletedDisplayState = fact.deletedDisplayState
        self.tombstoneTimestampSummary = Self.timestampSummary(fact.tombstoneTimestamp)
        self.conflictKind = fact.conflictKind ?? "none"
        self.conflictStatus = fact.conflictStatus
        self.activeVsTombstoneState = fact.activeVsTombstoneState
        self.antiResurrectionStatus = fact.antiResurrectionStatus
        self.parentObjectStateSummary = fact.parentObjectTombstoned ? "parentTombstoned" : "parentActiveOrUnknown"
        self.generatedArtifactResurrectionBlocked = fact.generatedArtifactResurrectionBlocked
        self.softDeleteMarkerPresent = fact.softDeleteMarkerPresent || fact.tombstoneState == .tombstoned
        self.hashPrefix = fact.hashPrefix
        self.fullMetadataIncluded = false
        self.fullContentIncluded = false
        self.absolutePathIncluded = false
        self.physicalDeleteTargetPathIncluded = false
        self.physicalDeleteRisk = fact.physicalDeleteRisk
        self.permanentDeleteRisk = fact.permanentDeleteRisk
        self.tombstoneGCRisk = fact.tombstoneGCRisk
        self.autoConflictResolutionRisk = fact.autoConflictResolutionRisk
        self.staleLiveResurrectionRisk = fact.staleLiveResurrectionRisk
    }

    private nonisolated static func timestampSummary(_ timestamp: CanonicalTimestamp?) -> String {
        guard let timestamp else {
            return "tombstoneTimestamp=missing"
        }
        let seconds = String(Int(timestamp.date.timeIntervalSince1970))
        let prefix = CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(seconds).value) ?? "missing"
        return "tombstoneTimestampHash=\(prefix)"
    }
}

nonisolated struct CanonicalTombstoneConflictReadSnapshot: Codable, Equatable, Sendable {
    var source: CanonicalTombstoneConflictReadProjectionSource
    var generatedAt: CanonicalTimestamp
    var items: [CanonicalTombstoneConflictReadProjectionItem]
    var failures: [CanonicalTombstoneConflictReadProjectionFailure]
    var metadataExcludedCount: Int
    var contentExcludedCount: Int

    nonisolated var itemCount: Int { items.count }
    nonisolated var failureCount: Int { failures.count }
    nonisolated var unsupportedObjectCount: Int { failures.filter { $0.kind == .unsupportedObjectKind }.count }
    nonisolated var pathLeakRiskCount: Int { failures.filter { $0.kind == .pathLeakRisk }.count }
    nonisolated var physicalDeleteRiskCount: Int { failures.filter { $0.kind == .physicalDeleteRisk }.count + items.filter(\.physicalDeleteRisk).count }
    nonisolated var permanentDeleteRiskCount: Int { failures.filter { $0.kind == .permanentDeleteRisk }.count + items.filter(\.permanentDeleteRisk).count }
    nonisolated var tombstoneGCRiskCount: Int { failures.filter { $0.kind == .tombstoneGCRisk }.count + items.filter(\.tombstoneGCRisk).count }
    nonisolated var staleLiveResurrectionRiskCount: Int { failures.filter { $0.kind == .staleLiveResurrectionRisk }.count + items.filter(\.staleLiveResurrectionRisk).count }
    nonisolated var autoConflictResolutionRiskCount: Int { failures.filter { $0.kind == .autoConflictResolutionRisk }.count + items.filter(\.autoConflictResolutionRisk).count }
    nonisolated var fullMetadataIncludedCount: Int { items.filter(\.fullMetadataIncluded).count }
    nonisolated var fullContentIncludedCount: Int { items.filter(\.fullContentIncluded).count }
    nonisolated var absolutePathIncludedCount: Int { items.filter(\.absolutePathIncluded).count }

    nonisolated var diagnosticsSummary: String {
        [
            "source=\(source.rawValue)",
            "items=\(itemCount)",
            "failures=\(failureCount)",
            "metadataIncluded=\(fullMetadataIncludedCount)",
            "contentIncluded=\(fullContentIncludedCount)",
            "metadataExcluded=\(metadataExcludedCount)",
            "contentExcluded=\(contentExcludedCount)",
            "pathLeakRisk=\(pathLeakRiskCount)"
        ].joined(separator: ",")
    }

    nonisolated init(
        source: CanonicalTombstoneConflictReadProjectionSource,
        generatedAt: Date = Date(),
        items: [CanonicalTombstoneConflictReadProjectionItem],
        failures: [CanonicalTombstoneConflictReadProjectionFailure],
        metadataExcludedCount: Int,
        contentExcludedCount: Int
    ) {
        self.source = source
        self.generatedAt = CanonicalTimestamp(generatedAt)
        self.items = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.id < $1.id }
        self.failures = Dictionary(failures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.id < $1.id }
        self.metadataExcludedCount = max(0, metadataExcludedCount)
        self.contentExcludedCount = max(0, contentExcludedCount)
    }
}

nonisolated enum CanonicalTombstoneConflictReadProjection {
    nonisolated static func snapshot(
        source: CanonicalTombstoneConflictReadProjectionSource,
        facts: [CanonicalTombstoneConflictReadProjectionFact],
        failures seedFailures: [CanonicalTombstoneConflictReadProjectionFailure] = [],
        generatedAt: Date = Date()
    ) -> CanonicalTombstoneConflictReadSnapshot {
        var failures = seedFailures
        var items: [CanonicalTombstoneConflictReadProjectionItem] = []
        for fact in facts.sorted(by: { $0.objectID < $1.objectID }) {
            if fact.unsupportedObjectKind {
                failures.append(.init(kind: .unsupportedObjectKind, source: source, objectID: fact.objectID, objectKind: fact.objectKind, reason: "unsupportedTombstoneConflictObjectKind"))
                continue
            }
            if fact.pathLeakRisk {
                failures.append(.init(kind: .pathLeakRisk, source: source, objectID: fact.objectID, objectKind: fact.objectKind, reason: "unsafePathTokenObserved"))
            }
            if fact.fullMetadataIncluded {
                failures.append(.init(kind: .fullMetadataRejected, source: source, objectID: fact.objectID, objectKind: fact.objectKind, reason: "fullMetadataExcludedFromProjection"))
            }
            if fact.fullContentIncluded {
                failures.append(.init(kind: .fullContentRejected, source: source, objectID: fact.objectID, objectKind: fact.objectKind, reason: "fullGeneratedContentExcludedFromProjection"))
            }
            if fact.physicalDeleteRisk {
                failures.append(.init(kind: .physicalDeleteRisk, source: source, objectID: fact.objectID, objectKind: fact.objectKind, reason: "physicalDeleteForbidden"))
            }
            if fact.permanentDeleteRisk {
                failures.append(.init(kind: .permanentDeleteRisk, source: source, objectID: fact.objectID, objectKind: fact.objectKind, reason: "permanentDeleteForbidden"))
            }
            if fact.tombstoneGCRisk {
                failures.append(.init(kind: .tombstoneGCRisk, source: source, objectID: fact.objectID, objectKind: fact.objectKind, reason: "tombstoneGCForbidden"))
            }
            if fact.staleLiveResurrectionRisk {
                failures.append(.init(kind: .staleLiveResurrectionRisk, source: source, objectID: fact.objectID, objectKind: fact.objectKind, reason: "staleLiveMetadataResurrectionForbidden"))
            }
            if fact.autoConflictResolutionRisk {
                failures.append(.init(kind: .autoConflictResolutionRisk, source: source, objectID: fact.objectID, objectKind: fact.objectKind, reason: "autoConflictResolutionForbidden"))
            }
            items.append(CanonicalTombstoneConflictReadProjectionItem(source: source, fact: fact))
        }
        return CanonicalTombstoneConflictReadSnapshot(
            source: source,
            generatedAt: generatedAt,
            items: items,
            failures: failures,
            metadataExcludedCount: items.count,
            contentExcludedCount: items.count
        )
    }

    nonisolated static func snapshot(
        source: CanonicalTombstoneConflictReadProjectionSource,
        localManifest: CanonicalManifest?,
        peerManifest: CanonicalManifest?,
        applyPlan: CanonicalApplyPlan? = nil,
        libraryPlan: CanonicalLibrarySyncPlan? = nil,
        generatedAt: Date = Date()
    ) -> CanonicalTombstoneConflictReadSnapshot {
        var facts: [CanonicalTombstoneConflictReadProjectionFact] = []
        var failures: [CanonicalTombstoneConflictReadProjectionFailure] = []
        if localManifest == nil && peerManifest == nil && applyPlan == nil && libraryPlan == nil {
            failures.append(.init(kind: .snapshotMissing, source: source, reason: "tombstoneConflictReadSnapshotMissing"))
        }
        if let localManifest {
            appendManifestFacts(localManifest, peer: false, into: &facts)
        }
        if let peerManifest {
            appendManifestFacts(peerManifest, peer: true, into: &facts)
        }
        if let applyPlan {
            appendApplyPlanFacts(applyPlan, into: &facts)
        }
        if let libraryPlan {
            appendLibraryPlanFacts(libraryPlan, into: &facts)
        }
        return snapshot(source: source, facts: facts, failures: failures, generatedAt: generatedAt)
    }

    private nonisolated static func appendManifestFacts(
        _ manifest: CanonicalManifest,
        peer: Bool,
        into facts: inout [CanonicalTombstoneConflictReadProjectionFact]
    ) {
        for object in manifest.objects {
            let tombstoned = object.metadata.isDeleted || object.syncState == .deleted
            let conflict = object.syncState == .conflict
            facts.append(CanonicalTombstoneConflictReadProjectionFact(
                objectID: object.objectID,
                objectKind: .recording,
                tombstoneState: tombstoned ? .tombstoned : .active,
                deletedDisplayState: tombstoned ? .tombstoned : .active,
                tombstoneTimestamp: object.metadata.deletedAt,
                conflictKind: conflict ? "recordingConflict" : nil,
                conflictStatus: conflict ? .unresolved : .none,
                activeVsTombstoneState: tombstoned ? (peer ? "peerTombstone" : "localTombstone") : "activeOnly",
                antiResurrectionStatus: tombstoned ? .blocked : .notTriggered,
                generatedArtifactResurrectionBlocked: tombstoned,
                softDeleteMarkerPresent: tombstoned,
                hashPrefix: CanonicalProductionRedaction.hashPrefix(object.metadataHash.value)
            ))
        }
        for object in manifest.libraryObjects {
            let tombstoned = object.isDeleted
            facts.append(CanonicalTombstoneConflictReadProjectionFact(
                objectID: object.objectID.rawValue,
                objectKind: object.kind,
                tombstoneState: tombstoned ? .tombstoned : .active,
                deletedDisplayState: tombstoned ? .tombstoned : .active,
                tombstoneTimestamp: object.deletedAt,
                conflictKind: nil,
                conflictStatus: .none,
                activeVsTombstoneState: tombstoned ? (peer ? "peerLibraryTombstone" : "localLibraryTombstone") : "activeOnly",
                antiResurrectionStatus: tombstoned ? .blocked : .notTriggered,
                generatedArtifactResurrectionBlocked: tombstoned,
                softDeleteMarkerPresent: tombstoned,
                hashPrefix: CanonicalProductionRedaction.hashPrefix(object.metadataHash.value)
            ))
        }
        for tombstone in manifest.libraryTombstones {
            facts.append(CanonicalTombstoneConflictReadProjectionFact(
                objectID: tombstone.objectID.rawValue,
                objectKind: tombstone.objectKind,
                tombstoneState: .tombstoned,
                deletedDisplayState: .tombstoned,
                tombstoneTimestamp: tombstone.deletedAt,
                activeVsTombstoneState: peer ? "peerLibraryTombstone" : "localLibraryTombstone",
                antiResurrectionStatus: .blocked,
                generatedArtifactResurrectionBlocked: true,
                softDeleteMarkerPresent: true
            ))
        }
    }

    private nonisolated static func appendApplyPlanFacts(
        _ plan: CanonicalApplyPlan,
        into facts: inout [CanonicalTombstoneConflictReadProjectionFact]
    ) {
        let tombstones = Dictionary(uniqueKeysWithValues: plan.tombstones.map { ($0.tombstoneID, $0) })
        let conflicts = Dictionary(uniqueKeysWithValues: plan.conflicts.map { ($0.conflictID, $0) })
        for action in plan.actions {
            switch action.kind {
            case .objectTombstoneApply, .objectTombstoneSend, .artifactTombstoneApply:
                let tombstone = action.tombstoneID.flatMap { tombstones[$0] }
                facts.append(CanonicalTombstoneConflictReadProjectionFact(
                    objectID: action.target.objectID,
                    objectKind: action.target.artifactKind == nil ? .recording : .generatedArtifactEnvelope,
                    tombstoneState: .tombstoned,
                    deletedDisplayState: .tombstoned,
                    tombstoneTimestamp: tombstone?.deletedAt,
                    activeVsTombstoneState: action.kind == .artifactTombstoneApply ? "artifactTombstoneUnsupported" : "objectTombstone",
                    antiResurrectionStatus: .blocked,
                    generatedArtifactResurrectionBlocked: true,
                    softDeleteMarkerPresent: true,
                    physicalDeleteRisk: action.kind == .artifactTombstoneApply
                ))
            case .conflictRecord:
                let conflict = action.conflictID.flatMap { conflicts[$0] }
                facts.append(CanonicalTombstoneConflictReadProjectionFact(
                    objectID: action.target.objectID,
                    objectKind: action.target.artifactKind == nil ? .recording : .generatedArtifactEnvelope,
                    conflictKind: conflict?.kind.rawValue ?? action.reason,
                    conflictStatus: .manualReviewRequired,
                    activeVsTombstoneState: conflict?.kind == .activeVsTombstone ? "activeVsTombstone" : "conflict",
                    antiResurrectionStatus: conflict?.kind == .activeVsTombstone ? .blocked : .notTriggered,
                    generatedArtifactResurrectionBlocked: conflict?.kind == .activeVsTombstone,
                    hashPrefix: conflict?.localHashPrefix
                ))
            case .deferredUnsupported where action.failureReason == .tombstoneBlocksResurrection:
                facts.append(CanonicalTombstoneConflictReadProjectionFact(
                    objectID: action.target.objectID,
                    objectKind: .generatedArtifactEnvelope,
                    tombstoneState: .tombstoned,
                    deletedDisplayState: .tombstoned,
                    conflictKind: "tombstoneBlocksResurrection",
                    conflictStatus: .manualReviewRequired,
                    activeVsTombstoneState: "generatedArtifactBlockedByTombstone",
                    antiResurrectionStatus: .blocked,
                    generatedArtifactResurrectionBlocked: true,
                    staleLiveResurrectionRisk: false
                ))
            default:
                break
            }
        }
    }

    private nonisolated static func appendLibraryPlanFacts(
        _ plan: CanonicalLibrarySyncPlan,
        into facts: inout [CanonicalTombstoneConflictReadProjectionFact]
    ) {
        let tombstones = Dictionary(uniqueKeysWithValues: plan.tombstones.map { ($0.tombstoneID, $0) })
        let conflicts = Dictionary(uniqueKeysWithValues: plan.conflicts.map { ($0.conflictID, $0) })
        for action in plan.applyActions {
            switch action.kind {
            case .libraryTombstoneApply, .libraryTombstoneSend:
                let tombstone = action.tombstoneID.flatMap { tombstones[$0] }
                facts.append(CanonicalTombstoneConflictReadProjectionFact(
                    objectID: action.target.objectID,
                    objectKind: tombstone?.objectKind ?? .unknownUnsupported,
                    tombstoneState: .tombstoned,
                    deletedDisplayState: .tombstoned,
                    tombstoneTimestamp: tombstone?.deletedAt,
                    activeVsTombstoneState: "libraryTombstone",
                    antiResurrectionStatus: .blocked,
                    generatedArtifactResurrectionBlocked: true,
                    softDeleteMarkerPresent: true
                ))
            case .conflictRecord:
                let conflict = action.conflictID.flatMap { conflicts[$0] }
                facts.append(CanonicalTombstoneConflictReadProjectionFact(
                    objectID: action.target.objectID,
                    objectKind: conflict?.objectKind ?? .unknownUnsupported,
                    conflictKind: conflict?.kind.rawValue ?? action.reason,
                    conflictStatus: .manualReviewRequired,
                    activeVsTombstoneState: conflict?.kind == .activeVsTombstone ? "activeVsTombstone" : "conflict",
                    antiResurrectionStatus: conflict?.kind == .activeVsTombstone ? .blocked : .notTriggered,
                    generatedArtifactResurrectionBlocked: conflict?.kind == .activeVsTombstone,
                    hashPrefix: conflict?.localHashPrefix
                ))
            default:
                break
            }
        }
    }
}

nonisolated enum CanonicalTombstoneConflictReadSideDivergenceKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingInCanonical
    case missingInLegacy
    case tombstoneStateMismatch
    case tombstoneTimestampMismatch
    case conflictRecordMismatch
    case activeVsTombstoneMismatch
    case resurrectionBlockMismatch
    case softDeleteMarkerMismatch
    case physicalDeleteRisk
    case permanentDeleteRisk
    case tombstoneGCRisk
    case autoConflictResolutionRisk
    case staleLiveResurrectionRisk
    case unsupportedObjectKind
    case pathLeakRisk
}

nonisolated struct CanonicalTombstoneConflictReadSideDivergence: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID, objectKind?.rawValue ?? "", field ?? ""].joined(separator: "|") }

    var kind: CanonicalTombstoneConflictReadSideDivergenceKind
    var objectID: String
    var objectKind: CanonicalObjectKind?
    var field: String?
    var legacyValue: String?
    var canonicalValue: String?
    var fatal: Bool

    nonisolated init(
        kind: CanonicalTombstoneConflictReadSideDivergenceKind,
        objectID: String,
        objectKind: CanonicalObjectKind? = nil,
        field: String? = nil,
        legacyValue: String? = nil,
        canonicalValue: String? = nil,
        fatal: Bool = false
    ) {
        self.kind = kind
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "tombstone-object")
        self.objectKind = objectKind
        self.field = field.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.legacyValue = legacyValue.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.canonicalValue = canonicalValue.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.fatal = fatal || Self.fatalKinds.contains(kind)
    }

    private nonisolated static let fatalKinds: Set<CanonicalTombstoneConflictReadSideDivergenceKind> = [
        .physicalDeleteRisk,
        .permanentDeleteRisk,
        .tombstoneGCRisk,
        .autoConflictResolutionRisk,
        .staleLiveResurrectionRisk,
        .pathLeakRisk
    ]
}

nonisolated struct CanonicalTombstoneConflictReadSideEquivalence: Codable, Equatable, Sendable {
    var equivalent: Bool
    var objectCount: Int
    var tombstoneCount: Int
    var conflictCount: Int
    var diagnosticsSummary: String
}

nonisolated enum CanonicalTombstoneConflictReadSideBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingLegacySnapshot
    case missingCanonicalSnapshot
    case blockingDivergence
    case physicalDeleteRisk
    case permanentDeleteRisk
    case tombstoneGCRisk
    case staleLiveResurrectionRisk
    case autoConflictResolutionRisk
    case unsupportedObjectKind
    case pathLeakRisk
}

nonisolated struct CanonicalTombstoneConflictReadSideDiffReport: Codable, Equatable, Sendable {
    var equivalence: CanonicalTombstoneConflictReadSideEquivalence
    var divergences: [CanonicalTombstoneConflictReadSideDivergence]
    var blockers: [CanonicalTombstoneConflictReadSideBlocker]
    var legacySnapshotSummary: String
    var canonicalSnapshotSummary: String
    var diagnosticsSummary: String

    nonisolated var equivalent: Bool { blockers.isEmpty && divergences.isEmpty }
    nonisolated var divergenceCount: Int { divergences.count }
    nonisolated var fatalDivergenceCount: Int { divergences.filter(\.fatal).count }
    nonisolated var unsupportedObjectCount: Int { divergences.filter { $0.kind == .unsupportedObjectKind }.count }
    nonisolated var pathLeakRiskCount: Int { divergences.filter { $0.kind == .pathLeakRisk }.count }
    nonisolated var physicalDeleteRiskCount: Int { divergences.filter { $0.kind == .physicalDeleteRisk }.count }
    nonisolated var permanentDeleteRiskCount: Int { divergences.filter { $0.kind == .permanentDeleteRisk }.count }
    nonisolated var tombstoneGCRiskCount: Int { divergences.filter { $0.kind == .tombstoneGCRisk }.count }
    nonisolated var staleLiveResurrectionRiskCount: Int { divergences.filter { $0.kind == .staleLiveResurrectionRisk }.count }
    nonisolated var autoConflictResolutionRiskCount: Int { divergences.filter { $0.kind == .autoConflictResolutionRisk }.count }
}

nonisolated enum CanonicalTombstoneConflictReadSideParallelDiff {
    nonisolated static func compare(
        legacy: CanonicalTombstoneConflictReadSnapshot?,
        canonical: CanonicalTombstoneConflictReadSnapshot?
    ) -> CanonicalTombstoneConflictReadSideDiffReport {
        var divergences: [CanonicalTombstoneConflictReadSideDivergence] = []
        var blockers: [CanonicalTombstoneConflictReadSideBlocker] = []
        guard let legacy else {
            return report(legacy: nil, canonical: canonical, divergences: [], blockers: [.missingLegacySnapshot])
        }
        guard let canonical else {
            return report(legacy: legacy, canonical: nil, divergences: [], blockers: [.missingCanonicalSnapshot])
        }

        appendFailureDivergences(legacy.failures + canonical.failures, divergences: &divergences, blockers: &blockers)
        let legacyByID = Dictionary(uniqueKeysWithValues: legacy.items.map { ($0.id, $0) })
        let canonicalByID = Dictionary(uniqueKeysWithValues: canonical.items.map { ($0.id, $0) })
        for id in Set(legacyByID.keys).union(canonicalByID.keys).sorted() {
            guard let legacyItem = legacyByID[id] else {
                let canonicalItem = canonicalByID[id]
                divergences.append(.init(kind: .missingInLegacy, objectID: canonicalItem?.objectID ?? id, objectKind: canonicalItem?.objectKind, canonicalValue: "present"))
                continue
            }
            guard let canonicalItem = canonicalByID[id] else {
                divergences.append(.init(kind: .missingInCanonical, objectID: legacyItem.objectID, objectKind: legacyItem.objectKind, legacyValue: "present"))
                continue
            }
            compare(legacyItem, canonicalItem, divergences: &divergences)
        }
        if !divergences.isEmpty {
            blockers.append(.blockingDivergence)
        }
        return report(legacy: legacy, canonical: canonical, divergences: divergences, blockers: blockers)
    }

    private nonisolated static func compare(
        _ legacy: CanonicalTombstoneConflictReadProjectionItem,
        _ canonical: CanonicalTombstoneConflictReadProjectionItem,
        divergences: inout [CanonicalTombstoneConflictReadSideDivergence]
    ) {
        appendMismatch(.tombstoneStateMismatch, legacy, canonical, "tombstoneState", legacy.tombstoneState.rawValue, canonical.tombstoneState.rawValue, into: &divergences)
        appendMismatch(.tombstoneTimestampMismatch, legacy, canonical, "tombstoneTimestamp", legacy.tombstoneTimestampSummary, canonical.tombstoneTimestampSummary, into: &divergences)
        appendMismatch(.conflictRecordMismatch, legacy, canonical, "conflictKind", legacy.conflictKind, canonical.conflictKind, into: &divergences)
        appendMismatch(.conflictRecordMismatch, legacy, canonical, "conflictStatus", legacy.conflictStatus.rawValue, canonical.conflictStatus.rawValue, into: &divergences)
        appendMismatch(.activeVsTombstoneMismatch, legacy, canonical, "activeVsTombstone", legacy.activeVsTombstoneState, canonical.activeVsTombstoneState, into: &divergences)
        appendMismatch(.resurrectionBlockMismatch, legacy, canonical, "antiResurrection", legacy.antiResurrectionStatus.rawValue, canonical.antiResurrectionStatus.rawValue, into: &divergences)
        appendMismatch(.resurrectionBlockMismatch, legacy, canonical, "generatedArtifactBlock", String(legacy.generatedArtifactResurrectionBlocked), String(canonical.generatedArtifactResurrectionBlocked), into: &divergences)
        appendMismatch(.softDeleteMarkerMismatch, legacy, canonical, "softDeleteMarker", String(legacy.softDeleteMarkerPresent), String(canonical.softDeleteMarkerPresent), into: &divergences)
        appendRiskDivergences(legacy, into: &divergences)
        appendRiskDivergences(canonical, into: &divergences)
    }

    private nonisolated static func appendMismatch(
        _ kind: CanonicalTombstoneConflictReadSideDivergenceKind,
        _ legacy: CanonicalTombstoneConflictReadProjectionItem,
        _ canonical: CanonicalTombstoneConflictReadProjectionItem,
        _ field: String,
        _ legacyValue: String,
        _ canonicalValue: String,
        into divergences: inout [CanonicalTombstoneConflictReadSideDivergence]
    ) {
        guard legacyValue != canonicalValue else {
            return
        }
        divergences.append(.init(kind: kind, objectID: legacy.objectID, objectKind: legacy.objectKind, field: field, legacyValue: legacyValue, canonicalValue: canonicalValue))
    }

    private nonisolated static func appendRiskDivergences(
        _ item: CanonicalTombstoneConflictReadProjectionItem,
        into divergences: inout [CanonicalTombstoneConflictReadSideDivergence]
    ) {
        if item.physicalDeleteRisk {
            divergences.append(.init(kind: .physicalDeleteRisk, objectID: item.objectID, objectKind: item.objectKind, field: "physicalDelete", canonicalValue: "true", fatal: true))
        }
        if item.permanentDeleteRisk {
            divergences.append(.init(kind: .permanentDeleteRisk, objectID: item.objectID, objectKind: item.objectKind, field: "permanentDelete", canonicalValue: "true", fatal: true))
        }
        if item.tombstoneGCRisk {
            divergences.append(.init(kind: .tombstoneGCRisk, objectID: item.objectID, objectKind: item.objectKind, field: "tombstoneGC", canonicalValue: "true", fatal: true))
        }
        if item.staleLiveResurrectionRisk {
            divergences.append(.init(kind: .staleLiveResurrectionRisk, objectID: item.objectID, objectKind: item.objectKind, field: "staleLiveMetadata", canonicalValue: "true", fatal: true))
        }
        if item.autoConflictResolutionRisk {
            divergences.append(.init(kind: .autoConflictResolutionRisk, objectID: item.objectID, objectKind: item.objectKind, field: "autoConflictResolution", canonicalValue: "true", fatal: true))
        }
    }

    private nonisolated static func appendFailureDivergences(
        _ failures: [CanonicalTombstoneConflictReadProjectionFailure],
        divergences: inout [CanonicalTombstoneConflictReadSideDivergence],
        blockers: inout [CanonicalTombstoneConflictReadSideBlocker]
    ) {
        for failure in failures {
            switch failure.kind {
            case .snapshotMissing:
                continue
            case .unsupportedObjectKind:
                blockers.append(.unsupportedObjectKind)
                divergences.append(failureDivergence(.unsupportedObjectKind, failure: failure))
            case .pathLeakRisk:
                blockers.append(.pathLeakRisk)
                divergences.append(failureDivergence(.pathLeakRisk, failure: failure, fatal: true))
            case .fullMetadataRejected, .fullContentRejected:
                continue
            case .physicalDeleteRisk:
                blockers.append(.physicalDeleteRisk)
                divergences.append(failureDivergence(.physicalDeleteRisk, failure: failure, fatal: true))
            case .permanentDeleteRisk:
                blockers.append(.permanentDeleteRisk)
                divergences.append(failureDivergence(.permanentDeleteRisk, failure: failure, fatal: true))
            case .tombstoneGCRisk:
                blockers.append(.tombstoneGCRisk)
                divergences.append(failureDivergence(.tombstoneGCRisk, failure: failure, fatal: true))
            case .staleLiveResurrectionRisk:
                blockers.append(.staleLiveResurrectionRisk)
                divergences.append(failureDivergence(.staleLiveResurrectionRisk, failure: failure, fatal: true))
            case .autoConflictResolutionRisk:
                blockers.append(.autoConflictResolutionRisk)
                divergences.append(failureDivergence(.autoConflictResolutionRisk, failure: failure, fatal: true))
            }
        }
    }

    private nonisolated static func failureDivergence(
        _ kind: CanonicalTombstoneConflictReadSideDivergenceKind,
        failure: CanonicalTombstoneConflictReadProjectionFailure,
        fatal: Bool = false
    ) -> CanonicalTombstoneConflictReadSideDivergence {
        CanonicalTombstoneConflictReadSideDivergence(
            kind: kind,
            objectID: failure.objectID ?? "run",
            objectKind: failure.objectKind,
            field: "projectionFailure",
            legacyValue: failure.source == .legacy ? failure.reason : nil,
            canonicalValue: failure.source == .canonical ? failure.reason : nil,
            fatal: fatal
        )
    }

    private nonisolated static func report(
        legacy: CanonicalTombstoneConflictReadSnapshot?,
        canonical: CanonicalTombstoneConflictReadSnapshot?,
        divergences: [CanonicalTombstoneConflictReadSideDivergence],
        blockers: [CanonicalTombstoneConflictReadSideBlocker]
    ) -> CanonicalTombstoneConflictReadSideDiffReport {
        let uniqueDivergences = Dictionary(divergences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.id < $1.id }
        var uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        if uniqueDivergences.contains(where: { $0.kind == .physicalDeleteRisk }) { uniqueBlockers.append(.physicalDeleteRisk) }
        if uniqueDivergences.contains(where: { $0.kind == .permanentDeleteRisk }) { uniqueBlockers.append(.permanentDeleteRisk) }
        if uniqueDivergences.contains(where: { $0.kind == .tombstoneGCRisk }) { uniqueBlockers.append(.tombstoneGCRisk) }
        if uniqueDivergences.contains(where: { $0.kind == .staleLiveResurrectionRisk }) { uniqueBlockers.append(.staleLiveResurrectionRisk) }
        if uniqueDivergences.contains(where: { $0.kind == .autoConflictResolutionRisk }) { uniqueBlockers.append(.autoConflictResolutionRisk) }
        uniqueBlockers = Array(Set(uniqueBlockers)).sorted { $0.rawValue < $1.rawValue }
        let equivalent = uniqueDivergences.isEmpty && uniqueBlockers.isEmpty
        let objectCount = canonical?.items.count ?? legacy?.items.count ?? 0
        let tombstoneCount = (canonical ?? legacy)?.items.filter { $0.tombstoneState == .tombstoned }.count ?? 0
        let conflictCount = (canonical ?? legacy)?.items.filter { $0.conflictStatus != .none }.count ?? 0
        let equivalence = CanonicalTombstoneConflictReadSideEquivalence(
            equivalent: equivalent,
            objectCount: objectCount,
            tombstoneCount: tombstoneCount,
            conflictCount: conflictCount,
            diagnosticsSummary: "equivalent=\(equivalent),objects=\(objectCount),tombstones=\(tombstoneCount),conflicts=\(conflictCount)"
        )
        return CanonicalTombstoneConflictReadSideDiffReport(
            equivalence: equivalence,
            divergences: uniqueDivergences,
            blockers: uniqueBlockers,
            legacySnapshotSummary: legacy?.diagnosticsSummary ?? "legacySnapshot=missing",
            canonicalSnapshotSummary: canonical?.diagnosticsSummary ?? "canonicalSnapshot=missing",
            diagnosticsSummary: "domain=tombstoneConflict,equivalent=\(equivalent),divergences=\(uniqueDivergences.count),fatal=\(uniqueDivergences.filter(\.fatal).count),blockers=\(uniqueBlockers.map(\.rawValue).joined(separator: "+"))"
        )
    }
}

nonisolated enum CanonicalTombstoneConflictReadSideMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case parallelOnly
}

nonisolated struct CanonicalTombstoneConflictReadSidePolicy: Codable, Equatable, Sendable {
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int

    nonisolated init(recordDiagnostics: Bool = true, maxDiagnosticsEvents: Int = 200) {
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(1, maxDiagnosticsEvents)
    }
}

nonisolated struct CanonicalTombstoneConflictReadSideConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var mode: CanonicalTombstoneConflictReadSideMode
    var policy: CanonicalTombstoneConflictReadSidePolicy

    nonisolated init(
        isEnabled: Bool = false,
        mode: CanonicalTombstoneConflictReadSideMode = .disabled,
        policy: CanonicalTombstoneConflictReadSidePolicy = CanonicalTombstoneConflictReadSidePolicy()
    ) {
        self.isEnabled = isEnabled
        self.mode = isEnabled ? mode : .disabled
        self.policy = policy
    }

    nonisolated static let disabled = CanonicalTombstoneConflictReadSideConfiguration()

    nonisolated static func enabled(
        mode: CanonicalTombstoneConflictReadSideMode = .parallelOnly,
        policy: CanonicalTombstoneConflictReadSidePolicy = CanonicalTombstoneConflictReadSidePolicy()
    ) -> CanonicalTombstoneConflictReadSideConfiguration {
        CanonicalTombstoneConflictReadSideConfiguration(isEnabled: true, mode: mode, policy: policy)
    }
}

nonisolated enum CanonicalTombstoneConflictReadSideDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalTombstoneConflictTemplateAuditStarted
    case canonicalTombstoneConflictTemplateAuditCompleted
    case canonicalTombstoneConflictTemplateBlocked
    case canonicalTombstoneConflictReadSideParallelStarted
    case canonicalTombstoneConflictReadSideParallelCompleted
    case canonicalTombstoneConflictReadSideDivergent
    case canonicalTombstoneConflictReadSideEquivalent
    case canonicalTombstoneConflictPhysicalDeleteRiskBlocked
    case canonicalTombstoneConflictPermanentDeleteRiskBlocked
    case canonicalTombstoneConflictGCRiskBlocked
    case canonicalTombstoneConflictStaleLiveResurrectionBlocked
    case canonicalTombstoneConflictAutoResolutionBlocked
    case canonicalTombstoneConflictObservationWindowStarted
    case canonicalTombstoneConflictObservationWindowBlocked
    case canonicalTombstoneConflictRetirementCandidateEvaluated
    case canonicalTombstoneConflictRetirementCandidateBlocked
    case canonicalTombstoneConflictNextPilotCandidateEvaluated
    case canonicalTombstoneConflictNextPilotCandidateBlocked
    case canonicalTombstoneConflictNextPilotCandidateReady
    case canonicalTombstoneConflictRuntimeSwitchDenied
    case canonicalTombstoneConflictNoMutationAsserted
}

nonisolated struct CanonicalTombstoneConflictReadSideDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, syncRunID ?? "", objectID ?? "", result ?? "", reason ?? ""].joined(separator: "|") }

    var kind: CanonicalTombstoneConflictReadSideDiagnosticKind
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var objectID: String?
    var objectKind: CanonicalObjectKind?
    var result: String?
    var reason: String?
    var hashPrefix: String?

    nonisolated init(
        kind: CanonicalTombstoneConflictReadSideDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        objectID: String? = nil,
        objectKind: CanonicalObjectKind? = nil,
        result: String? = nil,
        reason: String? = nil,
        hashPrefix: String? = nil
    ) {
        self.kind = kind
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "tombstone-object") }
        self.objectKind = objectKind
        self.result = result.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.reason = reason.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.hashPrefix = CanonicalProductionRedaction.hashPrefix(hashPrefix)
    }
}

nonisolated struct CanonicalTombstoneConflictReadSideEvaluationResult: Codable, Equatable, Sendable {
    var configuration: CanonicalTombstoneConflictReadSideConfiguration
    var diffReport: CanonicalTombstoneConflictReadSideDiffReport?
    var diagnostics: [CanonicalTombstoneConflictReadSideDiagnostic]
    var storeMutated: Bool
    var uiMutated: Bool
    var uploadJobCreated: Bool
    var receiveJSONMutated: Bool
    var inventoryResponseMutated: Bool
    var audioInboxWritten: Bool
    var transcriptionOrNoteGenerationTriggered: Bool
    var deleteAttempted: Bool
    var restoreAttempted: Bool
    var tombstoneCleared: Bool
    var conflictResolved: Bool

    nonisolated var noMutationAsserted: Bool {
        !storeMutated
            && !uiMutated
            && !uploadJobCreated
            && !receiveJSONMutated
            && !inventoryResponseMutated
            && !audioInboxWritten
            && !transcriptionOrNoteGenerationTriggered
            && !deleteAttempted
            && !restoreAttempted
            && !tombstoneCleared
            && !conflictResolved
    }

    nonisolated static func disabled(
        configuration: CanonicalTombstoneConflictReadSideConfiguration,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> CanonicalTombstoneConflictReadSideEvaluationResult {
        CanonicalTombstoneConflictReadSideEvaluationResult(
            configuration: configuration,
            diffReport: nil,
            diagnostics: [
                CanonicalTombstoneConflictReadSideDiagnostic(
                    kind: .canonicalTombstoneConflictRuntimeSwitchDenied,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "disabled",
                    reason: "tombstoneConflictReadSideDefaultOff"
                )
            ],
            storeMutated: false,
            uiMutated: false,
            uploadJobCreated: false,
            receiveJSONMutated: false,
            inventoryResponseMutated: false,
            audioInboxWritten: false,
            transcriptionOrNoteGenerationTriggered: false,
            deleteAttempted: false,
            restoreAttempted: false,
            tombstoneCleared: false,
            conflictResolved: false
        )
    }

    nonisolated static func evaluated(
        configuration: CanonicalTombstoneConflictReadSideConfiguration,
        diffReport: CanonicalTombstoneConflictReadSideDiffReport,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> CanonicalTombstoneConflictReadSideEvaluationResult {
        var diagnostics: [CanonicalTombstoneConflictReadSideDiagnostic] = [
            .init(kind: .canonicalTombstoneConflictReadSideParallelStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "started", reason: "metadataOnlyNoMutation"),
            .init(kind: diffReport.equivalent ? .canonicalTombstoneConflictReadSideEquivalent : .canonicalTombstoneConflictReadSideDivergent, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: diffReport.equivalent ? "equivalent" : "divergent", reason: diffReport.diagnosticsSummary),
            .init(kind: .canonicalTombstoneConflictReadSideParallelCompleted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: diffReport.equivalent ? "equivalent" : "divergent", reason: "divergenceCount=\(diffReport.divergenceCount)"),
            .init(kind: .canonicalTombstoneConflictNoMutationAsserted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "true", reason: "noDeleteNoRestoreNoStoreNoUI")
        ]
        if diffReport.blockers.contains(.physicalDeleteRisk) {
            diagnostics.append(.init(kind: .canonicalTombstoneConflictPhysicalDeleteRiskBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if diffReport.blockers.contains(.permanentDeleteRisk) {
            diagnostics.append(.init(kind: .canonicalTombstoneConflictPermanentDeleteRiskBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if diffReport.blockers.contains(.tombstoneGCRisk) {
            diagnostics.append(.init(kind: .canonicalTombstoneConflictGCRiskBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if diffReport.blockers.contains(.staleLiveResurrectionRisk) {
            diagnostics.append(.init(kind: .canonicalTombstoneConflictStaleLiveResurrectionBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if diffReport.blockers.contains(.autoConflictResolutionRisk) {
            diagnostics.append(.init(kind: .canonicalTombstoneConflictAutoResolutionBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        return CanonicalTombstoneConflictReadSideEvaluationResult(
            configuration: configuration,
            diffReport: diffReport,
            diagnostics: Array(diagnostics.prefix(configuration.policy.maxDiagnosticsEvents)),
            storeMutated: false,
            uiMutated: false,
            uploadJobCreated: false,
            receiveJSONMutated: false,
            inventoryResponseMutated: false,
            audioInboxWritten: false,
            transcriptionOrNoteGenerationTriggered: false,
            deleteAttempted: false,
            restoreAttempted: false,
            tombstoneCleared: false,
            conflictResolved: false
        )
    }
}

nonisolated struct CanonicalTombstoneConflictReadSideEvaluator: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        configuration: CanonicalTombstoneConflictReadSideConfiguration,
        legacySnapshot: CanonicalTombstoneConflictReadSnapshot?,
        canonicalSnapshot: CanonicalTombstoneConflictReadSnapshot?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String?
    ) -> CanonicalTombstoneConflictReadSideEvaluationResult {
        guard configuration.isEnabled, configuration.mode == .parallelOnly else {
            return .disabled(configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole)
        }
        let diff = CanonicalTombstoneConflictReadSideParallelDiff.compare(
            legacy: legacySnapshot,
            canonical: canonicalSnapshot
        )
        return .evaluated(
            configuration: configuration,
            diffReport: diff,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole
        )
    }
}

nonisolated enum CanonicalAntiResurrectionTemplateBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case staleLiveMetadataCanRestoreTombstone
    case absenceOfTombstoneInterpretedAsRestore
    case missingExplicitRestoreSignalRequirement
    case generatedArtifactApplyAllowedForTombstone
    case libraryMetadataApplyAllowedForTombstone
    case activeVsTombstoneNotConservative
    case newerTombstonePolicyMissing
    case physicalDeleteAllowed
    case permanentDeleteAllowed
    case tombstoneGCAllowed
    case autoConflictResolutionAllowed
}

nonisolated struct CanonicalAntiResurrectionTemplateResult: Codable, Equatable, Sendable {
    var allowed: Bool
    var blockers: [CanonicalAntiResurrectionTemplateBlocker]
    var reportOnly: Bool
    var diagnosticsSummary: String
}

nonisolated struct CanonicalAntiResurrectionTemplateGate: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        tombstonedObjectCannotBeRestoredByStaleLiveMetadata: Bool = true,
        absenceOfTombstoneIsNotRestore: Bool = true,
        restoreRequiresExplicitSignal: Bool = true,
        generatedArtifactApplyBlockedForTombstone: Bool = true,
        libraryMetadataApplyBlockedForTombstone: Bool = true,
        activeVsTombstoneConservativeByDefault: Bool = true,
        newerTombstonePolicyExplicit: Bool = true,
        physicalDeleteForbidden: Bool = true,
        permanentDeleteForbidden: Bool = true,
        tombstoneGCForbidden: Bool = true,
        autoConflictResolutionForbidden: Bool = true
    ) -> CanonicalAntiResurrectionTemplateResult {
        var blockers: [CanonicalAntiResurrectionTemplateBlocker] = []
        if !tombstonedObjectCannotBeRestoredByStaleLiveMetadata { blockers.append(.staleLiveMetadataCanRestoreTombstone) }
        if !absenceOfTombstoneIsNotRestore { blockers.append(.absenceOfTombstoneInterpretedAsRestore) }
        if !restoreRequiresExplicitSignal { blockers.append(.missingExplicitRestoreSignalRequirement) }
        if !generatedArtifactApplyBlockedForTombstone { blockers.append(.generatedArtifactApplyAllowedForTombstone) }
        if !libraryMetadataApplyBlockedForTombstone { blockers.append(.libraryMetadataApplyAllowedForTombstone) }
        if !activeVsTombstoneConservativeByDefault { blockers.append(.activeVsTombstoneNotConservative) }
        if !newerTombstonePolicyExplicit { blockers.append(.newerTombstonePolicyMissing) }
        if !physicalDeleteForbidden { blockers.append(.physicalDeleteAllowed) }
        if !permanentDeleteForbidden { blockers.append(.permanentDeleteAllowed) }
        if !tombstoneGCForbidden { blockers.append(.tombstoneGCAllowed) }
        if !autoConflictResolutionForbidden { blockers.append(.autoConflictResolutionAllowed) }
        let unique = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        return CanonicalAntiResurrectionTemplateResult(
            allowed: unique.isEmpty,
            blockers: unique,
            reportOnly: true,
            diagnosticsSummary: "domain=tombstoneConflict,antiResurrectionAllowed=\(unique.isEmpty),blockers=\(unique.map(\.rawValue).joined(separator: "+")),reportOnly=true"
        )
    }
}

nonisolated enum CanonicalTombstoneConflictObservationEventKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case noCommit
    case commit
    case rollback
    case legacyFallback
    case readSideEquivalent
    case readSideDivergent
    case physicalDeleteRisk
    case permanentDeleteRisk
    case tombstoneGCRisk
    case staleLiveResurrectionRisk
    case autoConflictResolutionRisk
    case unsupportedObject
}

nonisolated struct CanonicalTombstoneConflictObservationEvent: Codable, Equatable, Sendable {
    var kind: CanonicalTombstoneConflictObservationEventKind
    var count: Int

    nonisolated init(kind: CanonicalTombstoneConflictObservationEventKind, count: Int = 1) {
        self.kind = kind
        self.count = max(0, count)
    }
}

nonisolated struct CanonicalTombstoneConflictObservationPolicy: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var requireRuntimeSwitchFalse: Bool
    var requireLegacyFallbackAvailable: Bool

    nonisolated init(
        isEnabled: Bool = false,
        requireRuntimeSwitchFalse: Bool = true,
        requireLegacyFallbackAvailable: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.requireRuntimeSwitchFalse = requireRuntimeSwitchFalse
        self.requireLegacyFallbackAvailable = requireLegacyFallbackAvailable
    }

    nonisolated static let disabled = CanonicalTombstoneConflictObservationPolicy()
    nonisolated static let explicitInternal = CanonicalTombstoneConflictObservationPolicy(isEnabled: true)
}

nonisolated struct CanonicalTombstoneConflictObservationSummary: Codable, Equatable, Sendable {
    var noCommitEventCount: Int
    var commitEventCount: Int
    var rollbackEventCount: Int
    var legacyFallbackCount: Int
    var readSideEquivalentCount: Int
    var readSideDivergenceCount: Int
    var physicalDeleteRiskCount: Int
    var permanentDeleteRiskCount: Int
    var tombstoneGCRiskCount: Int
    var staleLiveResurrectionRiskCount: Int
    var autoConflictResolutionRiskCount: Int
    var unsupportedObjectCount: Int
    var runtimeSwitch: Bool
    var legacyFallbackAvailable: Bool
    var observationComplete: Bool
}

nonisolated struct CanonicalTombstoneConflictObservationWindow: Codable, Equatable, Sendable {
    var policy: CanonicalTombstoneConflictObservationPolicy
    var events: [CanonicalTombstoneConflictObservationEvent]
    var runtimeSwitch: Bool
    var legacyFallbackAvailable: Bool

    nonisolated init(
        policy: CanonicalTombstoneConflictObservationPolicy = .disabled,
        events: [CanonicalTombstoneConflictObservationEvent] = [],
        runtimeSwitch: Bool = false,
        legacyFallbackAvailable: Bool = true
    ) {
        self.policy = policy
        self.events = events
        self.runtimeSwitch = runtimeSwitch
        self.legacyFallbackAvailable = legacyFallbackAvailable
    }

    nonisolated func recording(_ event: CanonicalTombstoneConflictObservationEvent) -> CanonicalTombstoneConflictObservationWindow {
        CanonicalTombstoneConflictObservationWindow(
            policy: policy,
            events: events + [event],
            runtimeSwitch: runtimeSwitch,
            legacyFallbackAvailable: legacyFallbackAvailable
        )
    }

    nonisolated func recordingReadSide(_ report: CanonicalTombstoneConflictReadSideDiffReport) -> CanonicalTombstoneConflictObservationWindow {
        var window = recording(.init(kind: report.equivalent ? .readSideEquivalent : .readSideDivergent))
        if report.physicalDeleteRiskCount > 0 { window = window.recording(.init(kind: .physicalDeleteRisk, count: report.physicalDeleteRiskCount)) }
        if report.permanentDeleteRiskCount > 0 { window = window.recording(.init(kind: .permanentDeleteRisk, count: report.permanentDeleteRiskCount)) }
        if report.tombstoneGCRiskCount > 0 { window = window.recording(.init(kind: .tombstoneGCRisk, count: report.tombstoneGCRiskCount)) }
        if report.staleLiveResurrectionRiskCount > 0 { window = window.recording(.init(kind: .staleLiveResurrectionRisk, count: report.staleLiveResurrectionRiskCount)) }
        if report.autoConflictResolutionRiskCount > 0 { window = window.recording(.init(kind: .autoConflictResolutionRisk, count: report.autoConflictResolutionRiskCount)) }
        if report.unsupportedObjectCount > 0 { window = window.recording(.init(kind: .unsupportedObject, count: report.unsupportedObjectCount)) }
        return window
    }

    nonisolated var summary: CanonicalTombstoneConflictObservationSummary {
        let grouped = Dictionary(grouping: events, by: \.kind).mapValues { $0.reduce(0) { $0 + $1.count } }
        let complete = policy.isEnabled
            && (grouped[.readSideEquivalent] ?? 0) > 0
            && (grouped[.readSideDivergent] ?? 0) == 0
            && (grouped[.physicalDeleteRisk] ?? 0) == 0
            && (grouped[.permanentDeleteRisk] ?? 0) == 0
            && (grouped[.tombstoneGCRisk] ?? 0) == 0
            && (grouped[.staleLiveResurrectionRisk] ?? 0) == 0
            && (grouped[.autoConflictResolutionRisk] ?? 0) == 0
            && !runtimeSwitch
            && legacyFallbackAvailable
        return CanonicalTombstoneConflictObservationSummary(
            noCommitEventCount: grouped[.noCommit] ?? 0,
            commitEventCount: grouped[.commit] ?? 0,
            rollbackEventCount: grouped[.rollback] ?? 0,
            legacyFallbackCount: grouped[.legacyFallback] ?? 0,
            readSideEquivalentCount: grouped[.readSideEquivalent] ?? 0,
            readSideDivergenceCount: grouped[.readSideDivergent] ?? 0,
            physicalDeleteRiskCount: grouped[.physicalDeleteRisk] ?? 0,
            permanentDeleteRiskCount: grouped[.permanentDeleteRisk] ?? 0,
            tombstoneGCRiskCount: grouped[.tombstoneGCRisk] ?? 0,
            staleLiveResurrectionRiskCount: grouped[.staleLiveResurrectionRisk] ?? 0,
            autoConflictResolutionRiskCount: grouped[.autoConflictResolutionRisk] ?? 0,
            unsupportedObjectCount: grouped[.unsupportedObject] ?? 0,
            runtimeSwitch: runtimeSwitch,
            legacyFallbackAvailable: legacyFallbackAvailable,
            observationComplete: complete
        )
    }
}

nonisolated enum CanonicalTombstoneConflictObservationGateState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case incomplete
    case blocked
    case complete
}

nonisolated struct CanonicalTombstoneConflictObservationGate: Codable, Equatable, Sendable {
    var state: CanonicalTombstoneConflictObservationGateState
    var summary: CanonicalTombstoneConflictObservationSummary
    var blockers: [CanonicalTombstoneConflictReadSideBlocker]
    var diagnostics: [CanonicalTombstoneConflictReadSideDiagnostic]

    nonisolated var observationComplete: Bool { summary.observationComplete && state == .complete }

    nonisolated static func evaluate(
        window: CanonicalTombstoneConflictObservationWindow,
        trigger: CanonicalSyncPlanTrigger = .periodic,
        nodeRole: CanonicalProductionExecutionDomainRole = .testHarness,
        syncRunID: String? = nil
    ) -> CanonicalTombstoneConflictObservationGate {
        let summary = window.summary
        var blockers: [CanonicalTombstoneConflictReadSideBlocker] = []
        if summary.physicalDeleteRiskCount > 0 { blockers.append(.physicalDeleteRisk) }
        if summary.permanentDeleteRiskCount > 0 { blockers.append(.permanentDeleteRisk) }
        if summary.tombstoneGCRiskCount > 0 { blockers.append(.tombstoneGCRisk) }
        if summary.staleLiveResurrectionRiskCount > 0 { blockers.append(.staleLiveResurrectionRisk) }
        if summary.autoConflictResolutionRiskCount > 0 { blockers.append(.autoConflictResolutionRisk) }
        if summary.readSideDivergenceCount > 0 { blockers.append(.blockingDivergence) }
        if summary.unsupportedObjectCount > 0 { blockers.append(.unsupportedObjectKind) }
        let unique = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let state: CanonicalTombstoneConflictObservationGateState
        if !window.policy.isEnabled {
            state = .disabled
        } else if !unique.isEmpty || summary.runtimeSwitch || !summary.legacyFallbackAvailable {
            state = .blocked
        } else if summary.observationComplete {
            state = .complete
        } else {
            state = .incomplete
        }
        return CanonicalTombstoneConflictObservationGate(
            state: state,
            summary: summary,
            blockers: unique,
            diagnostics: [
                .init(kind: .canonicalTombstoneConflictObservationWindowStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: window.policy.isEnabled ? "enabled" : "disabled"),
                .init(kind: state == .complete ? .canonicalTombstoneConflictReadSideEquivalent : .canonicalTombstoneConflictObservationWindowBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: state.rawValue, reason: unique.map(\.rawValue).joined(separator: "+"))
            ]
        )
    }
}

nonisolated enum CanonicalTombstoneConflictRetirementBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingWriteSideCanarySuccess
    case missingReadSideCutoverEvidence
    case observationIncomplete
    case fallbackMissing
    case divergencePresent
    case unsupportedObjectPresent
    case physicalDeleteRiskPresent
    case permanentDeleteRiskPresent
    case tombstoneGCRiskPresent
    case staleLiveResurrectionRiskPresent
    case autoConflictResolutionRiskPresent
    case unresolvedConflictPresent
    case manualAuditRequired
}

nonisolated struct CanonicalTombstoneConflictRetirementCandidateReport: Codable, Equatable, Sendable {
    var retirementCandidateReady: Bool
    var retirementExecutionPerformed: Bool
    var legacyDeleted: Bool
    var legacyDisabled: Bool
    var manualAuditRequired: Bool
    var blockers: [CanonicalTombstoneConflictRetirementBlocker]
    var diagnostics: [CanonicalTombstoneConflictReadSideDiagnostic]
}

nonisolated enum CanonicalTombstoneConflictRetirementCandidateGate {
    nonisolated static func evaluate(
        writeSideCanarySuccessEvidence: Bool = false,
        readSideCutoverEvidence: Bool = false,
        observationGate: CanonicalTombstoneConflictObservationGate,
        fallbackAvailable: Bool = true,
        divergenceCount: Int = 0,
        unsupportedCount: Int = 0,
        unresolvedConflictCount: Int = 0,
        manualAuditCompleted: Bool = false,
        trigger: CanonicalSyncPlanTrigger = .periodic,
        nodeRole: CanonicalProductionExecutionDomainRole = .testHarness,
        syncRunID: String? = nil
    ) -> CanonicalTombstoneConflictRetirementCandidateReport {
        var blockers: [CanonicalTombstoneConflictRetirementBlocker] = []
        if !writeSideCanarySuccessEvidence { blockers.append(.missingWriteSideCanarySuccess) }
        if !readSideCutoverEvidence { blockers.append(.missingReadSideCutoverEvidence) }
        if !observationGate.observationComplete { blockers.append(.observationIncomplete) }
        if !fallbackAvailable { blockers.append(.fallbackMissing) }
        if divergenceCount > 0 || observationGate.summary.readSideDivergenceCount > 0 { blockers.append(.divergencePresent) }
        if unsupportedCount > 0 || observationGate.summary.unsupportedObjectCount > 0 { blockers.append(.unsupportedObjectPresent) }
        if observationGate.summary.physicalDeleteRiskCount > 0 { blockers.append(.physicalDeleteRiskPresent) }
        if observationGate.summary.permanentDeleteRiskCount > 0 { blockers.append(.permanentDeleteRiskPresent) }
        if observationGate.summary.tombstoneGCRiskCount > 0 { blockers.append(.tombstoneGCRiskPresent) }
        if observationGate.summary.staleLiveResurrectionRiskCount > 0 { blockers.append(.staleLiveResurrectionRiskPresent) }
        if observationGate.summary.autoConflictResolutionRiskCount > 0 { blockers.append(.autoConflictResolutionRiskPresent) }
        if unresolvedConflictCount > 0 { blockers.append(.unresolvedConflictPresent) }
        if !manualAuditCompleted { blockers.append(.manualAuditRequired) }
        let unique = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        return CanonicalTombstoneConflictRetirementCandidateReport(
            retirementCandidateReady: unique.isEmpty,
            retirementExecutionPerformed: false,
            legacyDeleted: false,
            legacyDisabled: false,
            manualAuditRequired: true,
            blockers: unique,
            diagnostics: [
                .init(kind: .canonicalTombstoneConflictRetirementCandidateEvaluated, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: unique.isEmpty ? "ready" : "blocked"),
                .init(kind: .canonicalTombstoneConflictRetirementCandidateBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "reportOnly", reason: unique.map(\.rawValue).joined(separator: "+"))
            ]
        )
    }
}

nonisolated enum CanonicalTombstoneConflictTemplateReadiness: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingProjection
    case missingPlanner
    case missingNoCommit
    case missingRealApplyPort
    case missingCommitExecutor
    case missingAppSeam
    case missingReadSideSeam
    case missingObservation
    case missingRetirementGate
    case missingAntiResurrectionGuard
    case missingPhysicalDeleteGuard
    case readyForNextPilotN0
    case blocked
}

nonisolated enum CanonicalTombstoneConflictTemplateBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingProjection
    case missingPlanner
    case missingNoCommit
    case missingRealApplyPort
    case missingCommitExecutor
    case missingAppSeam
    case missingReadSideSeam
    case missingObservation
    case missingRetirementGate
    case missingMigrationMatrixStatus
    case missingLegacyFallback
    case missingRollbackPlan
    case missingFailureInjection
    case duplicateSuppressionBeforeSuccess
    case missingAntiResurrectionGuard
    case missingPhysicalDeleteGuard
    case missingPermanentDeleteGuard
    case missingTombstoneGCGuard
    case missingConflictConservativePolicy
    case missingTests
    case missingDocs
}

nonisolated struct CanonicalTombstoneConflictTemplateReport: Codable, Equatable, Sendable {
    var readiness: CanonicalTombstoneConflictTemplateReadiness
    var blockers: [CanonicalTombstoneConflictTemplateBlocker]
    var readyForNextPilotN0: Bool
    var diagnostics: [CanonicalTombstoneConflictReadSideDiagnostic]
    var diagnosticsSummary: String

    nonisolated static func audit(
        canonicalProjection: Bool,
        planner: Bool,
        noCommitExecutor: Bool,
        realApplyPort: Bool,
        commitExecutor: Bool,
        appSeamDefaultOff: Bool,
        readSideSeam: Bool,
        observationWindow: Bool,
        retirementCandidateGate: Bool,
        migrationMatrixStatus: Bool,
        legacyFallback: Bool,
        rollbackPlan: Bool,
        failureInjection: Bool,
        duplicateSuppressionAfterSuccessOnly: Bool,
        antiResurrectionGuard: Bool,
        physicalDeleteGuard: Bool,
        permanentDeleteGuard: Bool,
        tombstoneGCGuard: Bool,
        conflictConservativePolicy: Bool,
        tests: Bool,
        docs: Bool
    ) -> CanonicalTombstoneConflictTemplateReport {
        var blockers: [CanonicalTombstoneConflictTemplateBlocker] = []
        if !canonicalProjection { blockers.append(.missingProjection) }
        if !planner { blockers.append(.missingPlanner) }
        if !noCommitExecutor { blockers.append(.missingNoCommit) }
        if !realApplyPort { blockers.append(.missingRealApplyPort) }
        if !commitExecutor { blockers.append(.missingCommitExecutor) }
        if !appSeamDefaultOff { blockers.append(.missingAppSeam) }
        if !readSideSeam { blockers.append(.missingReadSideSeam) }
        if !observationWindow { blockers.append(.missingObservation) }
        if !retirementCandidateGate { blockers.append(.missingRetirementGate) }
        if !migrationMatrixStatus { blockers.append(.missingMigrationMatrixStatus) }
        if !legacyFallback { blockers.append(.missingLegacyFallback) }
        if !rollbackPlan { blockers.append(.missingRollbackPlan) }
        if !failureInjection { blockers.append(.missingFailureInjection) }
        if !duplicateSuppressionAfterSuccessOnly { blockers.append(.duplicateSuppressionBeforeSuccess) }
        if !antiResurrectionGuard { blockers.append(.missingAntiResurrectionGuard) }
        if !physicalDeleteGuard { blockers.append(.missingPhysicalDeleteGuard) }
        if !permanentDeleteGuard { blockers.append(.missingPermanentDeleteGuard) }
        if !tombstoneGCGuard { blockers.append(.missingTombstoneGCGuard) }
        if !conflictConservativePolicy { blockers.append(.missingConflictConservativePolicy) }
        if !tests { blockers.append(.missingTests) }
        if !docs { blockers.append(.missingDocs) }
        let unique = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let readiness: CanonicalTombstoneConflictTemplateReadiness
        if unique.contains(.missingProjection) {
            readiness = .missingProjection
        } else if unique.contains(.missingPlanner) {
            readiness = .missingPlanner
        } else if unique.contains(.missingNoCommit) {
            readiness = .missingNoCommit
        } else if unique.contains(.missingRealApplyPort) {
            readiness = .missingRealApplyPort
        } else if unique.contains(.missingCommitExecutor) {
            readiness = .missingCommitExecutor
        } else if unique.contains(.missingAppSeam) {
            readiness = .missingAppSeam
        } else if unique.contains(.missingReadSideSeam) {
            readiness = .missingReadSideSeam
        } else if unique.contains(.missingObservation) {
            readiness = .missingObservation
        } else if unique.contains(.missingRetirementGate) {
            readiness = .missingRetirementGate
        } else if unique.contains(.missingAntiResurrectionGuard) {
            readiness = .missingAntiResurrectionGuard
        } else if unique.contains(.missingPhysicalDeleteGuard) || unique.contains(.missingPermanentDeleteGuard) || unique.contains(.missingTombstoneGCGuard) {
            readiness = .missingPhysicalDeleteGuard
        } else if unique.isEmpty {
            readiness = .readyForNextPilotN0
        } else {
            readiness = .blocked
        }
        let ready = readiness == .readyForNextPilotN0
        let diagnostics: [CanonicalTombstoneConflictReadSideDiagnostic] = [
            .init(kind: .canonicalTombstoneConflictTemplateAuditStarted, syncRunID: nil, trigger: .periodic, nodeRole: .testHarness, result: "started"),
            .init(kind: ready ? .canonicalTombstoneConflictTemplateAuditCompleted : .canonicalTombstoneConflictTemplateBlocked, syncRunID: nil, trigger: .periodic, nodeRole: .testHarness, result: readiness.rawValue, reason: unique.map(\.rawValue).joined(separator: "+"))
        ]
        return CanonicalTombstoneConflictTemplateReport(
            readiness: readiness,
            blockers: unique,
            readyForNextPilotN0: ready,
            diagnostics: diagnostics,
            diagnosticsSummary: "domain=tombstoneConflict,readiness=\(readiness.rawValue),blockers=\(unique.map(\.rawValue).joined(separator: "+")),readyForNextPilotN0=\(ready)"
        )
    }

    nonisolated static func currentV826Audit() -> CanonicalTombstoneConflictTemplateReport {
        audit(
            canonicalProjection: true,
            planner: true,
            noCommitExecutor: true,
            realApplyPort: true,
            commitExecutor: true,
            appSeamDefaultOff: true,
            readSideSeam: true,
            observationWindow: true,
            retirementCandidateGate: true,
            migrationMatrixStatus: true,
            legacyFallback: true,
            rollbackPlan: true,
            failureInjection: true,
            duplicateSuppressionAfterSuccessOnly: true,
            antiResurrectionGuard: true,
            physicalDeleteGuard: true,
            permanentDeleteGuard: true,
            tombstoneGCGuard: true,
            conflictConservativePolicy: true,
            tests: true,
            docs: true
        )
    }
}
