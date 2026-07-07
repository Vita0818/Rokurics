//
//  CanonicalGeneratedArtifactReadProjection.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated enum CanonicalGeneratedArtifactReadProjectionSource: String, Codable, Equatable, Hashable, Sendable {
    case legacy
    case canonical
}

typealias CanonicalGeneratedArtifactReadSourceKind = CanonicalGeneratedArtifactReadProjectionSource

nonisolated enum CanonicalGeneratedArtifactReadProjectionFailureKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case snapshotMissing
    case unsupportedArtifactKind
    case unsafePathToken
    case contentLeakRisk
    case audioConfusionRisk
    case tombstonedParentResurrectionRisk
}

nonisolated struct CanonicalGeneratedArtifactReadProjectionFailure: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "", artifactID ?? "", artifactKind?.rawValue ?? ""].joined(separator: "|") }

    var kind: CanonicalGeneratedArtifactReadProjectionFailureKind
    var source: CanonicalGeneratedArtifactReadProjectionSource
    var objectID: String?
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind?
    var reason: String

    nonisolated init(
        kind: CanonicalGeneratedArtifactReadProjectionFailureKind,
        source: CanonicalGeneratedArtifactReadProjectionSource,
        objectID: String? = nil,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind? = nil,
        reason: String
    ) {
        self.kind = kind
        self.source = source
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown-recording") }
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.artifactKind = artifactKind
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? kind.rawValue
    }
}

nonisolated struct CanonicalGeneratedArtifactReadProjectionArtifactFact: Codable, Equatable, Sendable {
    var artifact: CanonicalArtifact
    var parentTombstoned: Bool
    var localAvailability: Bool
    var peerAuthoritativeAvailability: Bool
    var producerSummary: String?
    var unsafePathTokenObserved: Bool

    nonisolated init(
        artifact: CanonicalArtifact,
        parentTombstoned: Bool = false,
        localAvailability: Bool = false,
        peerAuthoritativeAvailability: Bool = false,
        producerSummary: String? = nil,
        unsafePathTokenObserved: Bool = false
    ) {
        self.artifact = artifact
        self.parentTombstoned = parentTombstoned
        self.localAvailability = localAvailability
        self.peerAuthoritativeAvailability = peerAuthoritativeAvailability
        self.producerSummary = producerSummary.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.unsafePathTokenObserved = unsafePathTokenObserved
    }
}

nonisolated struct CanonicalGeneratedArtifactReadProjectionItem: Codable, Equatable, Identifiable, Sendable {
    var id: String { [objectID, artifactKind.rawValue].joined(separator: "|") }

    var source: CanonicalGeneratedArtifactReadProjectionSource
    var objectID: String
    var artifactID: String
    var artifactKind: CanonicalArtifact.Kind
    var availability: CanonicalArtifact.Availability
    var byteSize: Int64?
    var hashPrefix: String?
    var producerSummary: String?
    var logicalNameSummary: String?
    var logicalTokenSummary: String?
    var localDownloadedState: String?
    var peerAuthoritativeState: String?
    var updatedAtSummary: String?
    var parentObjectStateSummary: String?
    var localAvailability: Bool
    var peerAuthoritativeAvailability: Bool
    var parentTombstoned: Bool
    var contentIncluded: Bool
    var unsafePathTokenObserved: Bool

    nonisolated init(
        source: CanonicalGeneratedArtifactReadProjectionSource,
        fact: CanonicalGeneratedArtifactReadProjectionArtifactFact
    ) {
        let artifact = fact.artifact
        self.source = source
        self.objectID = CanonicalProductionRedaction.safeIdentifier(artifact.objectID, fallback: "unknown-recording")
        self.artifactID = CanonicalProductionRedaction.safeIdentifier(artifact.artifactID, fallback: "artifact:unknown")
        self.artifactKind = artifact.kind
        self.availability = artifact.availability
        self.byteSize = artifact.byteSize
        self.hashPrefix = artifact.contentHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.producerSummary = fact.producerSummary
            ?? artifact.producedBy.map(\.rawValue)
            ?? artifact.producedByNodeID.map { "node:\(CanonicalProductionRedaction.safeIdentifier($0, fallback: "node"))" }
        self.logicalNameSummary = artifact.logicalName.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.logicalTokenSummary = artifact.logicalPathToken.flatMap(CanonicalProjectionContract.safeLogicalPathToken)
        self.localDownloadedState = fact.localAvailability ? "downloadedOrLocalAvailable" : "notDownloadedOrUnavailable"
        self.peerAuthoritativeState = fact.peerAuthoritativeAvailability ? "peerAuthoritativeAvailable" : "peerNotAuthoritativeOrUnavailable"
        self.updatedAtSummary = artifact.modifiedAt.map { "unixSeconds=\(Int($0.date.timeIntervalSince1970))" }
        self.parentObjectStateSummary = fact.parentTombstoned ? "parentTombstoned" : "parentActiveOrUnknown"
        self.localAvailability = fact.localAvailability
        self.peerAuthoritativeAvailability = fact.peerAuthoritativeAvailability
        self.parentTombstoned = fact.parentTombstoned
        self.contentIncluded = false
        self.unsafePathTokenObserved = fact.unsafePathTokenObserved
    }
}

nonisolated struct CanonicalGeneratedArtifactReadSnapshot: Codable, Equatable, Sendable {
    var source: CanonicalGeneratedArtifactReadProjectionSource
    var generatedAt: CanonicalTimestamp
    var items: [CanonicalGeneratedArtifactReadProjectionItem]
    var failures: [CanonicalGeneratedArtifactReadProjectionFailure]
    var contentExcludedCount: Int

    nonisolated var itemCount: Int { items.count }
    nonisolated var failureCount: Int { failures.count }
    nonisolated var contentIncludedCount: Int { items.filter(\.contentIncluded).count }

    nonisolated var diagnosticsSummary: String {
        [
            "source=\(source.rawValue)",
            "items=\(itemCount)",
            "failures=\(failureCount)",
            "contentIncluded=\(contentIncludedCount)",
            "contentExcluded=\(contentExcludedCount)"
        ].joined(separator: ",")
    }

    nonisolated init(
        source: CanonicalGeneratedArtifactReadProjectionSource,
        generatedAt: Date = Date(),
        items: [CanonicalGeneratedArtifactReadProjectionItem],
        failures: [CanonicalGeneratedArtifactReadProjectionFailure],
        contentExcludedCount: Int
    ) {
        self.source = source
        self.generatedAt = CanonicalTimestamp(generatedAt)
        self.items = items.sorted { $0.id < $1.id }
        self.failures = Self.uniqueFailures(failures)
        self.contentExcludedCount = max(0, contentExcludedCount)
    }

    private nonisolated static func uniqueFailures(
        _ failures: [CanonicalGeneratedArtifactReadProjectionFailure]
    ) -> [CanonicalGeneratedArtifactReadProjectionFailure] {
        Dictionary(failures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.id < $1.id }
    }
}

nonisolated enum CanonicalGeneratedArtifactReadProjection {
    nonisolated static func snapshot(
        source: CanonicalGeneratedArtifactReadProjectionSource,
        localManifest: CanonicalManifest?,
        peerManifest: CanonicalManifest?,
        generatedAt: Date = Date()
    ) -> CanonicalGeneratedArtifactReadSnapshot {
        var facts: [CanonicalGeneratedArtifactReadProjectionArtifactFact] = []
        var failures: [CanonicalGeneratedArtifactReadProjectionFailure] = []

        if localManifest == nil && peerManifest == nil {
            failures.append(CanonicalGeneratedArtifactReadProjectionFailure(
                kind: .snapshotMissing,
                source: source,
                reason: "generatedArtifactReadProjectionSnapshotMissing"
            ))
        }

        if let localManifest {
            appendFacts(from: localManifest, peerAuthoritative: false, into: &facts, failures: &failures, source: source)
        }
        if let peerManifest {
            appendFacts(from: peerManifest, peerAuthoritative: true, into: &facts, failures: &failures, source: source)
        }
        return snapshot(source: source, facts: facts, failures: failures, generatedAt: generatedAt)
    }

    nonisolated static func snapshot(
        source: CanonicalGeneratedArtifactReadProjectionSource,
        facts: [CanonicalGeneratedArtifactReadProjectionArtifactFact],
        failures seedFailures: [CanonicalGeneratedArtifactReadProjectionFailure] = [],
        generatedAt: Date = Date()
    ) -> CanonicalGeneratedArtifactReadSnapshot {
        var failures = seedFailures
        var items: [CanonicalGeneratedArtifactReadProjectionItem] = []

        for fact in facts {
            let artifact = fact.artifact
            if artifact.kind == .audio {
                failures.append(CanonicalGeneratedArtifactReadProjectionFailure(
                    kind: .audioConfusionRisk,
                    source: source,
                    objectID: artifact.objectID,
                    artifactID: artifact.artifactID,
                    artifactKind: artifact.kind,
                    reason: "audioArtifactExcludedFromGeneratedArtifactReadProjection"
                ))
                continue
            }
            guard CanonicalProjectionContract.generatedArtifactKinds.contains(artifact.kind) else {
                failures.append(CanonicalGeneratedArtifactReadProjectionFailure(
                    kind: .unsupportedArtifactKind,
                    source: source,
                    objectID: artifact.objectID,
                    artifactID: artifact.artifactID,
                    artifactKind: artifact.kind,
                    reason: "unsupportedArtifactKind"
                ))
                continue
            }
            if fact.unsafePathTokenObserved {
                failures.append(CanonicalGeneratedArtifactReadProjectionFailure(
                    kind: .unsafePathToken,
                    source: source,
                    objectID: artifact.objectID,
                    artifactID: artifact.artifactID,
                    artifactKind: artifact.kind,
                    reason: "unsafePathTokenObserved"
                ))
            }
            if fact.parentTombstoned && artifact.availability != .missing && artifact.tombstone != true {
                failures.append(CanonicalGeneratedArtifactReadProjectionFailure(
                    kind: .tombstonedParentResurrectionRisk,
                    source: source,
                    objectID: artifact.objectID,
                    artifactID: artifact.artifactID,
                    artifactKind: artifact.kind,
                    reason: "availableArtifactUnderTombstonedParent"
                ))
            }
            items.append(CanonicalGeneratedArtifactReadProjectionItem(source: source, fact: fact))
        }

        if items.contains(where: \.contentIncluded) {
            failures.append(CanonicalGeneratedArtifactReadProjectionFailure(
                kind: .contentLeakRisk,
                source: source,
                reason: "contentIncludedInGeneratedArtifactReadProjection"
            ))
        }
        return CanonicalGeneratedArtifactReadSnapshot(
            source: source,
            generatedAt: generatedAt,
            items: items,
            failures: failures,
            contentExcludedCount: items.count
        )
    }

    private nonisolated static func appendFacts(
        from manifest: CanonicalManifest,
        peerAuthoritative: Bool,
        into facts: inout [CanonicalGeneratedArtifactReadProjectionArtifactFact],
        failures: inout [CanonicalGeneratedArtifactReadProjectionFailure],
        source: CanonicalGeneratedArtifactReadProjectionSource
    ) {
        for object in manifest.objects {
            for artifact in object.artifacts {
                let localAvailability = !peerAuthoritative && CanonicalProjectionContract.provesGeneratedArtifactAvailability(artifact)
                let peerAvailability = peerAuthoritative && CanonicalProjectionContract.isAuthoritativeProducer(
                    artifact,
                    node: manifest.node
                )
                facts.append(CanonicalGeneratedArtifactReadProjectionArtifactFact(
                    artifact: artifact,
                    parentTombstoned: object.metadata.isDeleted || object.syncState == .deleted,
                    localAvailability: localAvailability,
                    peerAuthoritativeAvailability: peerAvailability,
                    producerSummary: artifact.producedBy?.rawValue ?? manifest.node.platform,
                    unsafePathTokenObserved: false
                ))
            }
        }
        _ = failures
        _ = source
    }
}

nonisolated enum CanonicalGeneratedArtifactReadSideDivergenceKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingCanonical
    case missingLegacy
    case availabilityMismatch
    case byteSizeMismatch
    case hashPrefixMismatch
    case producerMismatch
    case artifactKindMismatch
    case logicalTokenMismatch
    case localDownloadedStateMismatch
    case peerAuthoritativeStateMismatch
    case parentStateMismatch
    case unsafePathToken
    case contentLeakRisk
    case unsupportedArtifactKind
    case tombstonedParentResurrectionRisk
    case audioConfusionRisk
    case unknownButRequired
}

nonisolated struct CanonicalGeneratedArtifactReadSideDivergence: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "", artifactID ?? "", artifactKind?.rawValue ?? ""].joined(separator: "|") }

    var kind: CanonicalGeneratedArtifactReadSideDivergenceKind
    var objectID: String?
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind?
    var legacyValue: String?
    var canonicalValue: String?
    var fatal: Bool

    nonisolated init(
        kind: CanonicalGeneratedArtifactReadSideDivergenceKind,
        objectID: String? = nil,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind? = nil,
        legacyValue: String? = nil,
        canonicalValue: String? = nil,
        fatal: Bool = false
    ) {
        self.kind = kind
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown-recording") }
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.artifactKind = artifactKind
        self.legacyValue = legacyValue.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.canonicalValue = canonicalValue.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.fatal = fatal
    }
}

nonisolated enum CanonicalGeneratedArtifactReadSideBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingLegacySnapshot
    case missingCanonicalSnapshot
    case blockingDivergence
    case unsafePathToken
    case contentLeakRisk
    case unsupportedArtifactKind
    case tombstonedParentResurrectionRisk
    case audioConfusionRisk
}

nonisolated struct CanonicalGeneratedArtifactReadSideDiffReport: Codable, Equatable, Sendable {
    var equivalent: Bool
    var divergenceCount: Int
    var fatalDivergenceCount: Int
    var divergences: [CanonicalGeneratedArtifactReadSideDivergence]
    var blockers: [CanonicalGeneratedArtifactReadSideBlocker]
    var diagnosticsSummary: String

    nonisolated var hasFatalBlocker: Bool {
        fatalDivergenceCount > 0 || blockers.contains(where: {
            $0 == .unsafePathToken
                || $0 == .contentLeakRisk
                || $0 == .unsupportedArtifactKind
                || $0 == .tombstonedParentResurrectionRisk
                || $0 == .audioConfusionRisk
        })
    }

    nonisolated var unsupportedArtifactCount: Int {
        divergences.filter { $0.kind == .unsupportedArtifactKind }.count
    }

    nonisolated var unsafePathTokenCount: Int {
        divergences.filter { $0.kind == .unsafePathToken }.count
    }

    nonisolated var contentLeakRiskCount: Int {
        divergences.filter { $0.kind == .contentLeakRisk }.count
    }

    nonisolated var parentTombstoneBlockCount: Int {
        divergences.filter { $0.kind == .tombstonedParentResurrectionRisk || $0.kind == .parentStateMismatch }.count
    }

    nonisolated var audioConfusionRiskCount: Int {
        divergences.filter { $0.kind == .audioConfusionRisk }.count
    }

    nonisolated init(
        divergences: [CanonicalGeneratedArtifactReadSideDivergence],
        blockers: [CanonicalGeneratedArtifactReadSideBlocker]
    ) {
        let uniqueDivergences = Dictionary(divergences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.id < $1.id }
        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.equivalent = uniqueDivergences.isEmpty && uniqueBlockers.isEmpty
        self.divergenceCount = uniqueDivergences.count
        self.fatalDivergenceCount = uniqueDivergences.filter(\.fatal).count
        self.divergences = uniqueDivergences
        self.blockers = uniqueBlockers
        self.diagnosticsSummary = [
            "domain=generatedArtifacts",
            "equivalent=\(equivalent)",
            "divergences=\(divergenceCount)",
            "fatal=\(fatalDivergenceCount)",
            "blockers=\(uniqueBlockers.map(\.rawValue).joined(separator: "+"))"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalGeneratedArtifactReadSideParallelDiff {
    nonisolated static func compare(
        legacy: CanonicalGeneratedArtifactReadSnapshot?,
        canonical: CanonicalGeneratedArtifactReadSnapshot?
    ) -> CanonicalGeneratedArtifactReadSideDiffReport {
        var divergences: [CanonicalGeneratedArtifactReadSideDivergence] = []
        var blockers: [CanonicalGeneratedArtifactReadSideBlocker] = []

        guard let legacy else {
            return CanonicalGeneratedArtifactReadSideDiffReport(
                divergences: [],
                blockers: [.missingLegacySnapshot]
            )
        }
        guard let canonical else {
            return CanonicalGeneratedArtifactReadSideDiffReport(
                divergences: [],
                blockers: [.missingCanonicalSnapshot]
            )
        }

        appendFailureDivergences(legacy.failures + canonical.failures, divergences: &divergences, blockers: &blockers)

        let legacyByKey = Dictionary(legacy.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let canonicalByKey = Dictionary(canonical.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let keys = Set(legacyByKey.keys).union(canonicalByKey.keys).sorted()
        for key in keys {
            guard let legacyItem = legacyByKey[key] else {
                let canonicalItem = canonicalByKey[key]
                divergences.append(CanonicalGeneratedArtifactReadSideDivergence(
                    kind: .missingLegacy,
                    objectID: canonicalItem?.objectID,
                    artifactID: canonicalItem?.artifactID,
                    artifactKind: canonicalItem?.artifactKind,
                    canonicalValue: "present"
                ))
                continue
            }
            guard let canonicalItem = canonicalByKey[key] else {
                divergences.append(CanonicalGeneratedArtifactReadSideDivergence(
                    kind: .missingCanonical,
                    objectID: legacyItem.objectID,
                    artifactID: legacyItem.artifactID,
                    artifactKind: legacyItem.artifactKind,
                    legacyValue: "present"
                ))
                continue
            }
            compare(legacyItem, canonicalItem, divergences: &divergences)
        }
        if !divergences.isEmpty {
            blockers.append(.blockingDivergence)
        }
        return CanonicalGeneratedArtifactReadSideDiffReport(divergences: divergences, blockers: blockers)
    }

    private nonisolated static func compare(
        _ legacy: CanonicalGeneratedArtifactReadProjectionItem,
        _ canonical: CanonicalGeneratedArtifactReadProjectionItem,
        divergences: inout [CanonicalGeneratedArtifactReadSideDivergence]
    ) {
        if legacy.artifactKind != canonical.artifactKind {
            divergences.append(CanonicalGeneratedArtifactReadSideDivergence(
                kind: .artifactKindMismatch,
                objectID: legacy.objectID,
                artifactID: legacy.artifactID,
                artifactKind: legacy.artifactKind,
                legacyValue: legacy.artifactKind.rawValue,
                canonicalValue: canonical.artifactKind.rawValue
            ))
        }
        if legacy.availability != canonical.availability {
            divergences.append(CanonicalGeneratedArtifactReadSideDivergence(
                kind: .availabilityMismatch,
                objectID: legacy.objectID,
                artifactID: legacy.artifactID,
                artifactKind: legacy.artifactKind,
                legacyValue: legacy.availability.rawValue,
                canonicalValue: canonical.availability.rawValue
            ))
        }
        if legacy.byteSize != canonical.byteSize {
            divergences.append(CanonicalGeneratedArtifactReadSideDivergence(
                kind: .byteSizeMismatch,
                objectID: legacy.objectID,
                artifactID: legacy.artifactID,
                artifactKind: legacy.artifactKind,
                legacyValue: legacy.byteSize.map(String.init),
                canonicalValue: canonical.byteSize.map(String.init)
            ))
        }
        if let legacyHash = legacy.hashPrefix,
           let canonicalHash = canonical.hashPrefix,
           legacyHash != canonicalHash {
            divergences.append(CanonicalGeneratedArtifactReadSideDivergence(
                kind: .hashPrefixMismatch,
                objectID: legacy.objectID,
                artifactID: legacy.artifactID,
                artifactKind: legacy.artifactKind,
                legacyValue: legacyHash,
                canonicalValue: canonicalHash
            ))
        }
        if legacy.producerSummary != canonical.producerSummary {
            divergences.append(CanonicalGeneratedArtifactReadSideDivergence(
                kind: .producerMismatch,
                objectID: legacy.objectID,
                artifactID: legacy.artifactID,
                artifactKind: legacy.artifactKind,
                legacyValue: legacy.producerSummary,
                canonicalValue: canonical.producerSummary
            ))
        }
        if legacy.logicalTokenSummary != canonical.logicalTokenSummary {
            divergences.append(CanonicalGeneratedArtifactReadSideDivergence(
                kind: .logicalTokenMismatch,
                objectID: legacy.objectID,
                artifactID: legacy.artifactID,
                artifactKind: legacy.artifactKind,
                legacyValue: legacy.logicalTokenSummary,
                canonicalValue: canonical.logicalTokenSummary
            ))
        }
        if legacy.localAvailability != canonical.localAvailability {
            divergences.append(CanonicalGeneratedArtifactReadSideDivergence(
                kind: .localDownloadedStateMismatch,
                objectID: legacy.objectID,
                artifactID: legacy.artifactID,
                artifactKind: legacy.artifactKind,
                legacyValue: legacy.localDownloadedState,
                canonicalValue: canonical.localDownloadedState
            ))
        }
        if legacy.peerAuthoritativeAvailability != canonical.peerAuthoritativeAvailability {
            divergences.append(CanonicalGeneratedArtifactReadSideDivergence(
                kind: .peerAuthoritativeStateMismatch,
                objectID: legacy.objectID,
                artifactID: legacy.artifactID,
                artifactKind: legacy.artifactKind,
                legacyValue: legacy.peerAuthoritativeState,
                canonicalValue: canonical.peerAuthoritativeState
            ))
        }
        if legacy.parentTombstoned != canonical.parentTombstoned {
            divergences.append(CanonicalGeneratedArtifactReadSideDivergence(
                kind: .parentStateMismatch,
                objectID: legacy.objectID,
                artifactID: legacy.artifactID,
                artifactKind: legacy.artifactKind,
                legacyValue: legacy.parentObjectStateSummary,
                canonicalValue: canonical.parentObjectStateSummary
            ))
        }
    }

    private nonisolated static func appendFailureDivergences(
        _ failures: [CanonicalGeneratedArtifactReadProjectionFailure],
        divergences: inout [CanonicalGeneratedArtifactReadSideDivergence],
        blockers: inout [CanonicalGeneratedArtifactReadSideBlocker]
    ) {
        for failure in failures {
            switch failure.kind {
            case .snapshotMissing:
                continue
            case .unsupportedArtifactKind:
                blockers.append(.unsupportedArtifactKind)
                divergences.append(failureDivergence(.unsupportedArtifactKind, failure: failure, fatal: true))
            case .unsafePathToken:
                blockers.append(.unsafePathToken)
                divergences.append(failureDivergence(.unsafePathToken, failure: failure, fatal: true))
            case .contentLeakRisk:
                blockers.append(.contentLeakRisk)
                divergences.append(failureDivergence(.contentLeakRisk, failure: failure, fatal: true))
            case .audioConfusionRisk:
                blockers.append(.audioConfusionRisk)
                divergences.append(failureDivergence(.audioConfusionRisk, failure: failure, fatal: true))
            case .tombstonedParentResurrectionRisk:
                blockers.append(.tombstonedParentResurrectionRisk)
                divergences.append(failureDivergence(.tombstonedParentResurrectionRisk, failure: failure, fatal: true))
            }
        }
    }

    private nonisolated static func failureDivergence(
        _ kind: CanonicalGeneratedArtifactReadSideDivergenceKind,
        failure: CanonicalGeneratedArtifactReadProjectionFailure,
        fatal: Bool
    ) -> CanonicalGeneratedArtifactReadSideDivergence {
        CanonicalGeneratedArtifactReadSideDivergence(
            kind: kind,
            objectID: failure.objectID,
            artifactID: failure.artifactID,
            artifactKind: failure.artifactKind,
            legacyValue: failure.source == .legacy ? failure.reason : nil,
            canonicalValue: failure.source == .canonical ? failure.reason : nil,
            fatal: fatal
        )
    }
}

nonisolated enum CanonicalGeneratedArtifactReadSideMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case parallelOnly
}

nonisolated struct CanonicalGeneratedArtifactReadSidePolicy: Codable, Equatable, Sendable {
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int

    nonisolated init(recordDiagnostics: Bool = true, maxDiagnosticsEvents: Int = 200) {
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(1, maxDiagnosticsEvents)
    }
}

nonisolated struct CanonicalGeneratedArtifactReadSideConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var mode: CanonicalGeneratedArtifactReadSideMode
    var policy: CanonicalGeneratedArtifactReadSidePolicy

    nonisolated init(
        isEnabled: Bool = false,
        mode: CanonicalGeneratedArtifactReadSideMode = .disabled,
        policy: CanonicalGeneratedArtifactReadSidePolicy = CanonicalGeneratedArtifactReadSidePolicy()
    ) {
        self.isEnabled = isEnabled
        self.mode = isEnabled ? mode : .disabled
        self.policy = policy
    }

    nonisolated static let disabled = CanonicalGeneratedArtifactReadSideConfiguration()

    nonisolated static func enabled(
        mode: CanonicalGeneratedArtifactReadSideMode = .parallelOnly,
        policy: CanonicalGeneratedArtifactReadSidePolicy = CanonicalGeneratedArtifactReadSidePolicy()
    ) -> CanonicalGeneratedArtifactReadSideConfiguration {
        CanonicalGeneratedArtifactReadSideConfiguration(isEnabled: true, mode: mode, policy: policy)
    }
}

nonisolated enum CanonicalGeneratedArtifactReadSideDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalGeneratedArtifactTemplateAuditStarted
    case canonicalGeneratedArtifactTemplateAuditCompleted
    case canonicalGeneratedArtifactNextPilotCandidateReady
    case canonicalGeneratedArtifactNextPilotCandidateBlocked
    case canonicalGeneratedArtifactReadProjectionStarted
    case canonicalGeneratedArtifactReadProjectionCompleted
    case canonicalGeneratedArtifactReadSideParallelStarted
    case canonicalGeneratedArtifactReadSideParallelEquivalent
    case canonicalGeneratedArtifactReadSideParallelDivergent
    case canonicalGeneratedArtifactReadSideFatalBlocker
    case canonicalGeneratedArtifactReadSideContentExcluded
    case canonicalGeneratedArtifactReadSideNoMutationAsserted
    case canonicalGeneratedArtifactReadSourceEvaluated
    case canonicalGeneratedArtifactReadSourceLegacyReturned
    case canonicalGeneratedArtifactReadSourceCanonicalCandidateBuilt
    case canonicalGeneratedArtifactGuardedCanonicalReadAllowed
    case canonicalGeneratedArtifactGuardedCanonicalReadBlocked
    case canonicalGeneratedArtifactGuardedCanonicalReadServed
    case canonicalGeneratedArtifactGuardedCanonicalReadFallback
    case canonicalGeneratedArtifactReadCutoverGateEvaluated
    case canonicalGeneratedArtifactReadCutoverGateBlocked
    case canonicalGeneratedArtifactReadCutoverGateAllowed
    case canonicalGeneratedArtifactReadOutputEquivalent
    case canonicalGeneratedArtifactReadOutputDivergent
    case canonicalGeneratedArtifactObservationWindowStarted
    case canonicalGeneratedArtifactObservationWindowCompleted
    case canonicalGeneratedArtifactObservationWindowBlocked
    case canonicalGeneratedArtifactObservationIncomplete
    case canonicalGeneratedArtifactObservationComplete
    case canonicalGeneratedArtifactRetirementCandidateGateEvaluated
    case canonicalGeneratedArtifactRetirementCandidateReady
    case canonicalGeneratedArtifactRetirementCandidateBlocked
    case canonicalGeneratedArtifactRetirementExecutionSuppressed
    case canonicalGeneratedArtifactRetirementManualAuditRequired
    case canonicalGeneratedArtifactRuntimeSwitchDenied
    case canonicalGeneratedArtifactLegacyRetirementDenied
}

nonisolated struct CanonicalGeneratedArtifactReadSideDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, syncRunID ?? "", objectID ?? "", artifactID ?? ""].joined(separator: "|") }

    var kind: CanonicalGeneratedArtifactReadSideDiagnosticKind
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var objectID: String?
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind?
    var result: String?
    var reason: String?
    var hashPrefix: String?

    nonisolated init(
        kind: CanonicalGeneratedArtifactReadSideDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        objectID: String? = nil,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind? = nil,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil,
        hashPrefix: String? = nil
    ) {
        self.kind = kind
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown-recording") }
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.artifactKind = artifactKind
        self.result = result.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.reason = reason.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.hashPrefix = hash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
            ?? CanonicalProductionRedaction.hashPrefix(hashPrefix)
    }

    nonisolated var diagnosticsSummary: String {
        [
            "trigger=\(trigger.rawValue)",
            "nodeRole=\(nodeRole.rawValue)",
            objectID.map { "objectID=\($0)" },
            artifactID.map { "artifactID=\($0)" },
            artifactKind.map { "artifactKind=\($0.rawValue)" },
            result.map { "result=\($0)" },
            reason.map { "reason=\($0)" },
            hashPrefix.map { "hashPrefix=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }
}

nonisolated struct CanonicalGeneratedArtifactReadSideEvaluationResult: Codable, Equatable, Sendable {
    var configuration: CanonicalGeneratedArtifactReadSideConfiguration
    var diffReport: CanonicalGeneratedArtifactReadSideDiffReport?
    var diagnostics: [CanonicalGeneratedArtifactReadSideDiagnostic]
    var storeMutated: Bool
    var uiMutated: Bool
    var artifactDownloaded: Bool
    var artifactApplied: Bool
    var uploadJobCreated: Bool
    var inventoryResponseMutated: Bool
    var receiveJSONMutated: Bool
    var transcriptionOrNoteGenerationTriggered: Bool

    nonisolated var noMutationAsserted: Bool {
        !storeMutated
            && !uiMutated
            && !artifactDownloaded
            && !artifactApplied
            && !uploadJobCreated
            && !inventoryResponseMutated
            && !receiveJSONMutated
            && !transcriptionOrNoteGenerationTriggered
    }

    nonisolated static func disabled(
        configuration: CanonicalGeneratedArtifactReadSideConfiguration,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> CanonicalGeneratedArtifactReadSideEvaluationResult {
        CanonicalGeneratedArtifactReadSideEvaluationResult(
            configuration: configuration,
            diffReport: nil,
            diagnostics: [
                CanonicalGeneratedArtifactReadSideDiagnostic(
                    kind: .canonicalGeneratedArtifactRuntimeSwitchDenied,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "disabled",
                    reason: "readSideParallelDefaultOff"
                )
            ],
            storeMutated: false,
            uiMutated: false,
            artifactDownloaded: false,
            artifactApplied: false,
            uploadJobCreated: false,
            inventoryResponseMutated: false,
            receiveJSONMutated: false,
            transcriptionOrNoteGenerationTriggered: false
        )
    }

    nonisolated static func evaluated(
        configuration: CanonicalGeneratedArtifactReadSideConfiguration,
        diffReport: CanonicalGeneratedArtifactReadSideDiffReport,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> CanonicalGeneratedArtifactReadSideEvaluationResult {
        var diagnostics: [CanonicalGeneratedArtifactReadSideDiagnostic] = [
            CanonicalGeneratedArtifactReadSideDiagnostic(
                kind: .canonicalGeneratedArtifactReadSideParallelStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "started",
                reason: "mutatedUI=false,storeMutated=false"
            ),
            CanonicalGeneratedArtifactReadSideDiagnostic(
                kind: diffReport.equivalent ? .canonicalGeneratedArtifactReadSideParallelEquivalent : .canonicalGeneratedArtifactReadSideParallelDivergent,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: diffReport.equivalent ? "equivalent" : "divergent",
                reason: diffReport.diagnosticsSummary
            ),
            CanonicalGeneratedArtifactReadSideDiagnostic(
                kind: .canonicalGeneratedArtifactReadSideContentExcluded,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "true",
                reason: "metadataOnlyProjection"
            ),
            CanonicalGeneratedArtifactReadSideDiagnostic(
                kind: .canonicalGeneratedArtifactReadSideNoMutationAsserted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "true",
                reason: "noDownloadNoApplyNoStoreNoUI"
            )
        ]
        if diffReport.hasFatalBlocker {
            diagnostics.append(CanonicalGeneratedArtifactReadSideDiagnostic(
                kind: .canonicalGeneratedArtifactReadSideFatalBlocker,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "blocked",
                reason: diffReport.blockers.map(\.rawValue).joined(separator: "+")
            ))
        }
        return CanonicalGeneratedArtifactReadSideEvaluationResult(
            configuration: configuration,
            diffReport: diffReport,
            diagnostics: diagnostics,
            storeMutated: false,
            uiMutated: false,
            artifactDownloaded: false,
            artifactApplied: false,
            uploadJobCreated: false,
            inventoryResponseMutated: false,
            receiveJSONMutated: false,
            transcriptionOrNoteGenerationTriggered: false
        )
    }
}

nonisolated struct CanonicalGeneratedArtifactReadSideEvaluator: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        configuration: CanonicalGeneratedArtifactReadSideConfiguration,
        legacySnapshot: CanonicalGeneratedArtifactReadSnapshot?,
        canonicalSnapshot: CanonicalGeneratedArtifactReadSnapshot?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String?
    ) -> CanonicalGeneratedArtifactReadSideEvaluationResult {
        guard configuration.isEnabled, configuration.mode == .parallelOnly else {
            return .disabled(configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole)
        }
        let diff = CanonicalGeneratedArtifactReadSideParallelDiff.compare(
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

nonisolated struct CanonicalGeneratedArtifactWriteSideEvidenceLinkage: Codable, Equatable, Sendable {
    var canaryStageStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var latestSuccessfulStage: CanonicalGeneratedArtifactCanaryStage?
    var successfulCommitCount: Int
    var rollbackCount: Int
    var rollbackFailureCount: Int
    var legacyFallbackCount: Int
    var duplicateSuppressionCount: Int
    var unresolvedConflictCount: Int
    var unsupportedArtifactCount: Int
    var contentLeakRiskCount: Int
    var unsafePathTokenCount: Int
    var parentTombstoneBlockCount: Int
    var audioConfusionRiskCount: Int
    var readSideDivergenceCount: Int
    var writeSideDomainCutoverComplete: Bool
    var runtimeSwitchEnabled: Bool
    var generatedArtifactUploadJobCreated: Bool
    var audioAutoDownloaded: Bool

    nonisolated init(
        canaryStageStatus: CanonicalGeneratedArtifactStageEvidenceStatus = .missing,
        latestSuccessfulStage: CanonicalGeneratedArtifactCanaryStage? = nil,
        successfulCommitCount: Int = 0,
        rollbackCount: Int = 0,
        rollbackFailureCount: Int = 0,
        legacyFallbackCount: Int = 0,
        duplicateSuppressionCount: Int = 0,
        unresolvedConflictCount: Int = 0,
        unsupportedArtifactCount: Int = 0,
        contentLeakRiskCount: Int = 0,
        unsafePathTokenCount: Int = 0,
        parentTombstoneBlockCount: Int = 0,
        audioConfusionRiskCount: Int = 0,
        readSideDivergenceCount: Int = 0,
        writeSideDomainCutoverComplete: Bool = false,
        runtimeSwitchEnabled: Bool = false,
        generatedArtifactUploadJobCreated: Bool = false,
        audioAutoDownloaded: Bool = false
    ) {
        self.canaryStageStatus = canaryStageStatus
        self.latestSuccessfulStage = latestSuccessfulStage
        self.successfulCommitCount = max(0, successfulCommitCount)
        self.rollbackCount = max(0, rollbackCount)
        self.rollbackFailureCount = max(0, rollbackFailureCount)
        self.legacyFallbackCount = max(0, legacyFallbackCount)
        self.duplicateSuppressionCount = max(0, duplicateSuppressionCount)
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.unsupportedArtifactCount = max(0, unsupportedArtifactCount)
        self.contentLeakRiskCount = max(0, contentLeakRiskCount)
        self.unsafePathTokenCount = max(0, unsafePathTokenCount)
        self.parentTombstoneBlockCount = max(0, parentTombstoneBlockCount)
        self.audioConfusionRiskCount = max(0, audioConfusionRiskCount)
        self.readSideDivergenceCount = max(0, readSideDivergenceCount)
        self.writeSideDomainCutoverComplete = writeSideDomainCutoverComplete
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.generatedArtifactUploadJobCreated = generatedArtifactUploadJobCreated
        self.audioAutoDownloaded = audioAutoDownloaded
    }

    nonisolated static let missing = CanonicalGeneratedArtifactWriteSideEvidenceLinkage()

    nonisolated static func from(
        stageObservationReport report: CanonicalGeneratedArtifactCanaryStageObservationReport,
        writeSideDomainCutoverComplete: Bool = false
    ) -> CanonicalGeneratedArtifactWriteSideEvidenceLinkage {
        let clean = report.successCount > 0
            && report.failureCount == 0
            && report.rollbackFailureCount == 0
            && report.contentLeakRiskCount == 0
            && report.unsafePathTokenCount == 0
            && report.parentTombstoneBlockCount == 0
            && report.audioConfusionBlockCount == 0
            && report.fatalBlockerCount == 0
            && report.readSideParallelDivergentCount == 0
            && !report.runtimeSwitch
            && !report.artifactUploadJobCreated
            && !report.audioAutoDownloaded
        return CanonicalGeneratedArtifactWriteSideEvidenceLinkage(
            canaryStageStatus: clean ? .passed : .blocked,
            latestSuccessfulStage: clean ? report.stage : nil,
            successfulCommitCount: report.successCount,
            rollbackCount: report.rollbackCount,
            rollbackFailureCount: report.rollbackFailureCount,
            legacyFallbackCount: report.legacyFallbackCount,
            duplicateSuppressionCount: report.duplicateSuppressionCount,
            unresolvedConflictCount: report.evidenceReport.unresolvedConflictCount,
            unsupportedArtifactCount: report.evidenceReport.previousStageUnsupportedArtifactCount,
            contentLeakRiskCount: report.contentLeakRiskCount,
            unsafePathTokenCount: report.unsafePathTokenCount,
            parentTombstoneBlockCount: report.parentTombstoneBlockCount,
            audioConfusionRiskCount: report.audioConfusionBlockCount,
            readSideDivergenceCount: report.readSideParallelDivergentCount,
            writeSideDomainCutoverComplete: writeSideDomainCutoverComplete,
            runtimeSwitchEnabled: report.runtimeSwitch,
            generatedArtifactUploadJobCreated: report.artifactUploadJobCreated,
            audioAutoDownloaded: report.audioAutoDownloaded
        )
    }

    nonisolated var hasCleanStagedCanaryEvidence: Bool {
        canaryStageStatus.isPassing
            && latestSuccessfulStage != nil
            && successfulCommitCount > 0
            && rollbackFailureCount == 0
            && unresolvedConflictCount == 0
            && unsupportedArtifactCount == 0
            && contentLeakRiskCount == 0
            && unsafePathTokenCount == 0
            && parentTombstoneBlockCount == 0
            && audioConfusionRiskCount == 0
            && readSideDivergenceCount == 0
            && !runtimeSwitchEnabled
            && !generatedArtifactUploadJobCreated
            && !audioAutoDownloaded
    }

    nonisolated var diagnosticsSummary: String {
        [
            "stageStatus=\(canaryStageStatus.rawValue)",
            "latestStage=\(latestSuccessfulStage?.rawValue ?? "none")",
            "success=\(successfulCommitCount)",
            "rollbackFailure=\(rollbackFailureCount)",
            "duplicateSuppression=\(duplicateSuppressionCount)",
            "unresolvedConflict=\(unresolvedConflictCount)",
            "contentLeakRisk=\(contentLeakRiskCount)",
            "unsafePathToken=\(unsafePathTokenCount)",
            "parentTombstone=\(parentTombstoneBlockCount)",
            "audioConfusion=\(audioConfusionRiskCount)",
            "readDivergence=\(readSideDivergenceCount)",
            "domainCutover=\(writeSideDomainCutoverComplete)",
            "runtimeSwitch=\(runtimeSwitchEnabled)",
            "artifactUploadJob=\(generatedArtifactUploadJobCreated)",
            "audioAutoDownloaded=\(audioAutoDownloaded)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalGeneratedArtifactReadSourceMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case legacy
    case parallelCompare
    case canonicalCandidate
    case guardedCanonicalRead
    case blocked
}

nonisolated struct CanonicalGeneratedArtifactReadSourceConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalGeneratedArtifactReadSourceMode
    var explicitInternalTestConfiguration: Bool
    var uiCutoverGlobal: Bool
    var runtimeSwitchEnabled: Bool
    var defaultReadCutoverEnabled: Bool
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int

    nonisolated init(
        mode: CanonicalGeneratedArtifactReadSourceMode = .legacy,
        explicitInternalTestConfiguration: Bool = false,
        uiCutoverGlobal: Bool = false,
        runtimeSwitchEnabled: Bool = false,
        defaultReadCutoverEnabled: Bool = false,
        recordDiagnostics: Bool = true,
        maxDiagnosticsEvents: Int = 48
    ) {
        self.mode = mode
        self.explicitInternalTestConfiguration = explicitInternalTestConfiguration
        self.uiCutoverGlobal = uiCutoverGlobal
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.defaultReadCutoverEnabled = defaultReadCutoverEnabled
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(0, maxDiagnosticsEvents)
    }

    nonisolated static let legacy = CanonicalGeneratedArtifactReadSourceConfiguration()

    nonisolated static func explicitGuardedCanonicalRead() -> CanonicalGeneratedArtifactReadSourceConfiguration {
        CanonicalGeneratedArtifactReadSourceConfiguration(
            mode: .guardedCanonicalRead,
            explicitInternalTestConfiguration: true
        )
    }
}

nonisolated enum CanonicalGeneratedArtifactReadFallback: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case none
    case legacyDefault
    case gateBlocked
    case canonicalProjectionMissing
    case unsupportedArtifact
    case divergenceDetected
    case unsafePathToken
    case contentLeakRisk
    case parentTombstone
    case audioConfusionRisk
    case canonicalReadException
    case blockedMode
}

nonisolated struct CanonicalGeneratedArtifactReadSource: Codable, Equatable, Sendable {
    var source: CanonicalGeneratedArtifactReadProjectionSource
    var snapshot: CanonicalGeneratedArtifactReadSnapshot
    var metadataAvailabilityOnly: Bool
    var coversTranscriptArtifactMetadata: Bool
    var coversNoteArtifactMetadata: Bool
    var coversSummaryArtifactMetadata: Bool
    var excludesFullTranscriptContent: Bool
    var excludesFullNoteContent: Bool
    var excludesFullSummaryContent: Bool
    var excludesProviderResponse: Bool
    var excludesAudioBytes: Bool
    var excludesGeneratedArtifactUploadState: Bool

    nonisolated init(
        source: CanonicalGeneratedArtifactReadProjectionSource,
        snapshot: CanonicalGeneratedArtifactReadSnapshot
    ) {
        self.source = source
        self.snapshot = snapshot
        self.metadataAvailabilityOnly = true
        self.coversTranscriptArtifactMetadata = true
        self.coversNoteArtifactMetadata = true
        self.coversSummaryArtifactMetadata = true
        self.excludesFullTranscriptContent = true
        self.excludesFullNoteContent = true
        self.excludesFullSummaryContent = true
        self.excludesProviderResponse = true
        self.excludesAudioBytes = true
        self.excludesGeneratedArtifactUploadState = true
    }

    nonisolated var diagnosticsSummary: String {
        [
            "source=\(source.rawValue)",
            "metadataAvailabilityOnly=\(metadataAvailabilityOnly)",
            "items=\(snapshot.itemCount)",
            "failures=\(snapshot.failureCount)",
            "excludeTranscript=\(excludesFullTranscriptContent)",
            "excludeNote=\(excludesFullNoteContent)",
            "excludeSummary=\(excludesFullSummaryContent)",
            "excludeProviderResponse=\(excludesProviderResponse)",
            "excludeAudio=\(excludesAudioBytes)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalGeneratedArtifactReadCutoverGateState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case allowed
    case blockedByWriteSideEvidence
    case blockedByDivergence
    case blockedByUnsupportedArtifact
    case blockedByUnsafePath
    case blockedByContentLeakRisk
    case blockedByParentTombstone
    case blockedByAudioConfusion
    case blockedByFallbackMissing
    case blockedByOtherActiveDomain
    case blockedByDefaultConfig
    case blocked
}

nonisolated enum CanonicalGeneratedArtifactReadCutoverBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case activePilotNotGeneratedArtifacts
    case multipleActivePilots
    case otherDomainNotStaticOnly
    case writeSideStagedCanaryEvidenceMissing
    case writeSideRollbackFatal
    case readSideDivergence
    case unsupportedArtifact
    case unsafePathToken
    case contentLeakRisk
    case parentTombstone
    case audioConfusionRisk
    case legacyFallbackMissing
    case canonicalProjectionIncomplete
    case artifactRouteChanged
    case generatedArtifactUploadJobCreated
    case explicitInternalTestConfigMissing
    case globalUICutoverRequested
    case defaultReadCutoverEnabled
    case runtimeSwitchEnabled
}

nonisolated struct CanonicalGeneratedArtifactReadCutoverGateContext: Codable, Equatable, Sendable {
    var configuration: CanonicalGeneratedArtifactReadSourceConfiguration
    var writeSideEvidence: CanonicalGeneratedArtifactWriteSideEvidenceLinkage
    var legacyFallbackAvailable: Bool
    var canonicalProjectionComplete: Bool
    var artifactRouteChanged: Bool
    var generatedArtifactUploadJobCreated: Bool

    nonisolated init(
        configuration: CanonicalGeneratedArtifactReadSourceConfiguration,
        writeSideEvidence: CanonicalGeneratedArtifactWriteSideEvidenceLinkage,
        legacyFallbackAvailable: Bool = true,
        canonicalProjectionComplete: Bool = true,
        artifactRouteChanged: Bool = false,
        generatedArtifactUploadJobCreated: Bool = false
    ) {
        self.configuration = configuration
        self.writeSideEvidence = writeSideEvidence
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.canonicalProjectionComplete = canonicalProjectionComplete
        self.artifactRouteChanged = artifactRouteChanged
        self.generatedArtifactUploadJobCreated = generatedArtifactUploadJobCreated
    }
}

nonisolated struct CanonicalGeneratedArtifactReadCutoverGateResult: Codable, Equatable, Sendable {
    var state: CanonicalGeneratedArtifactReadCutoverGateState
    var blockers: [CanonicalGeneratedArtifactReadCutoverBlocker]
    var diagnostics: [CanonicalGeneratedArtifactReadSideDiagnostic]
    var diagnosticsSummary: String

    nonisolated var allowed: Bool {
        state == .allowed && blockers.isEmpty
    }
}

nonisolated enum CanonicalGeneratedArtifactReadCutoverGate {
    nonisolated static func evaluate(
        context: CanonicalGeneratedArtifactReadCutoverGateContext,
        diffReport: CanonicalGeneratedArtifactReadSideDiffReport,
        matrix: CanonicalMigrationDomainMatrix = .v824GeneratedArtifactsStagedCanary(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        ),
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String?
    ) -> CanonicalGeneratedArtifactReadCutoverGateResult {
        var blockers: [CanonicalGeneratedArtifactReadCutoverBlocker] = []
        let matrixReport = matrix.validate()
        if matrixReport.activePilotDomain != .generatedArtifacts {
            blockers.append(.activePilotNotGeneratedArtifacts)
        }
        if matrixReport.blockers.contains(.multipleActivePilots) {
            blockers.append(.multipleActivePilots)
        }
        if matrixReport.blockers.contains(.nonPilotDomainNotStaticOnly) {
            blockers.append(.otherDomainNotStaticOnly)
        }
        if !context.writeSideEvidence.hasCleanStagedCanaryEvidence {
            blockers.append(.writeSideStagedCanaryEvidenceMissing)
        }
        if context.writeSideEvidence.rollbackFailureCount > 0 {
            blockers.append(.writeSideRollbackFatal)
        }
        if diffReport.divergenceCount > 0 || context.writeSideEvidence.readSideDivergenceCount > 0 {
            blockers.append(.readSideDivergence)
        }
        if diffReport.unsupportedArtifactCount > 0 || context.writeSideEvidence.unsupportedArtifactCount > 0 {
            blockers.append(.unsupportedArtifact)
        }
        if diffReport.unsafePathTokenCount > 0 || context.writeSideEvidence.unsafePathTokenCount > 0 {
            blockers.append(.unsafePathToken)
        }
        if diffReport.contentLeakRiskCount > 0 || context.writeSideEvidence.contentLeakRiskCount > 0 {
            blockers.append(.contentLeakRisk)
        }
        if diffReport.parentTombstoneBlockCount > 0 || context.writeSideEvidence.parentTombstoneBlockCount > 0 {
            blockers.append(.parentTombstone)
        }
        if diffReport.audioConfusionRiskCount > 0 || context.writeSideEvidence.audioConfusionRiskCount > 0 {
            blockers.append(.audioConfusionRisk)
        }
        if !context.legacyFallbackAvailable {
            blockers.append(.legacyFallbackMissing)
        }
        if !context.canonicalProjectionComplete {
            blockers.append(.canonicalProjectionIncomplete)
        }
        if context.artifactRouteChanged {
            blockers.append(.artifactRouteChanged)
        }
        if context.generatedArtifactUploadJobCreated || context.writeSideEvidence.generatedArtifactUploadJobCreated {
            blockers.append(.generatedArtifactUploadJobCreated)
        }
        if !context.configuration.explicitInternalTestConfiguration {
            blockers.append(.explicitInternalTestConfigMissing)
        }
        if context.configuration.uiCutoverGlobal {
            blockers.append(.globalUICutoverRequested)
        }
        if context.configuration.defaultReadCutoverEnabled {
            blockers.append(.defaultReadCutoverEnabled)
        }
        if context.configuration.runtimeSwitchEnabled
            || context.writeSideEvidence.runtimeSwitchEnabled
            || matrixReport.blockers.contains(.runtimeSwitchEnabled) {
            blockers.append(.runtimeSwitchEnabled)
        }

        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let state = state(for: uniqueBlockers)
        let diagnosticsSummary = [
            "state=\(state.rawValue)",
            "domain=generatedArtifacts",
            "divergences=\(diffReport.divergenceCount)",
            "unsupported=\(diffReport.unsupportedArtifactCount)",
            "unsafePathToken=\(diffReport.unsafePathTokenCount)",
            "contentLeakRisk=\(diffReport.contentLeakRiskCount)",
            "parentTombstone=\(diffReport.parentTombstoneBlockCount)",
            "audioConfusion=\(diffReport.audioConfusionRiskCount)",
            "fallback=\(context.legacyFallbackAvailable)",
            "explicitInternal=\(context.configuration.explicitInternalTestConfiguration)",
            "runtimeSwitch=\(context.configuration.runtimeSwitchEnabled)",
            "uiGlobal=\(context.configuration.uiCutoverGlobal)",
            "defaultReadCutover=\(context.configuration.defaultReadCutoverEnabled)",
            "blockers=\(uniqueBlockers.map(\.rawValue).joined(separator: "+"))"
        ].joined(separator: ",")
        let diagnostics = [
            CanonicalGeneratedArtifactReadSideDiagnostic(
                kind: .canonicalGeneratedArtifactReadCutoverGateEvaluated,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: state.rawValue,
                reason: diagnosticsSummary
            ),
            CanonicalGeneratedArtifactReadSideDiagnostic(
                kind: uniqueBlockers.isEmpty ? .canonicalGeneratedArtifactReadCutoverGateAllowed : .canonicalGeneratedArtifactReadCutoverGateBlocked,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: uniqueBlockers.isEmpty ? "allowed" : "blocked",
                reason: uniqueBlockers.map(\.rawValue).joined(separator: "+")
            )
        ]
        return CanonicalGeneratedArtifactReadCutoverGateResult(
            state: state,
            blockers: uniqueBlockers,
            diagnostics: diagnostics,
            diagnosticsSummary: diagnosticsSummary
        )
    }

    private nonisolated static func state(
        for blockers: [CanonicalGeneratedArtifactReadCutoverBlocker]
    ) -> CanonicalGeneratedArtifactReadCutoverGateState {
        if blockers.isEmpty {
            return .allowed
        }
        if blockers.contains(.explicitInternalTestConfigMissing)
            || blockers.contains(.globalUICutoverRequested)
            || blockers.contains(.defaultReadCutoverEnabled)
            || blockers.contains(.runtimeSwitchEnabled) {
            return .blockedByDefaultConfig
        }
        if blockers.contains(.activePilotNotGeneratedArtifacts)
            || blockers.contains(.multipleActivePilots)
            || blockers.contains(.otherDomainNotStaticOnly) {
            return .blockedByOtherActiveDomain
        }
        if blockers.contains(.writeSideStagedCanaryEvidenceMissing) || blockers.contains(.writeSideRollbackFatal) {
            return .blockedByWriteSideEvidence
        }
        if blockers.contains(.contentLeakRisk) {
            return .blockedByContentLeakRisk
        }
        if blockers.contains(.unsafePathToken) {
            return .blockedByUnsafePath
        }
        if blockers.contains(.parentTombstone) {
            return .blockedByParentTombstone
        }
        if blockers.contains(.audioConfusionRisk) {
            return .blockedByAudioConfusion
        }
        if blockers.contains(.unsupportedArtifact) {
            return .blockedByUnsupportedArtifact
        }
        if blockers.contains(.legacyFallbackMissing) {
            return .blockedByFallbackMissing
        }
        if blockers.contains(.readSideDivergence) {
            return .blockedByDivergence
        }
        return .blocked
    }
}

nonisolated struct CanonicalGeneratedArtifactReadSourceResult: Codable, Equatable, Sendable {
    var mode: CanonicalGeneratedArtifactReadSourceMode
    var returnedSource: CanonicalGeneratedArtifactReadProjectionSource
    var readSource: CanonicalGeneratedArtifactReadSource
    var legacySnapshot: CanonicalGeneratedArtifactReadSnapshot
    var canonicalCandidate: CanonicalGeneratedArtifactReadSnapshot?
    var diffReport: CanonicalGeneratedArtifactReadSideDiffReport?
    var gateResult: CanonicalGeneratedArtifactReadCutoverGateResult?
    var fallback: CanonicalGeneratedArtifactReadFallback
    var fallbackCount: Int
    var canonicalReadServed: Bool
    var legacyReadReturned: Bool
    var canonicalCandidateBuilt: Bool
    var fatalForFutureStage: Bool
    var storeMutated: Bool
    var syncOrUploadTriggered: Bool
    var artifactDownloaded: Bool
    var artifactApplied: Bool
    var generatedArtifactFileWritten: Bool
    var uploadJobCreated: Bool
    var inventoryResponseMutated: Bool
    var receiveJSONMutated: Bool
    var transcriptionOrNoteGenerationTriggered: Bool
    var diagnostics: [CanonicalGeneratedArtifactReadSideDiagnostic]
    var diagnosticsSummary: String
}

nonisolated struct CanonicalGeneratedArtifactReadSourceProvider: Sendable {
    var configuration: CanonicalGeneratedArtifactReadSourceConfiguration
    var matrix: CanonicalMigrationDomainMatrix

    nonisolated init(
        configuration: CanonicalGeneratedArtifactReadSourceConfiguration = .legacy,
        matrix: CanonicalMigrationDomainMatrix = .v824GeneratedArtifactsStagedCanary(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        )
    ) {
        self.configuration = configuration
        self.matrix = matrix
    }

    nonisolated func read(
        legacySnapshot: CanonicalGeneratedArtifactReadSnapshot,
        canonicalSnapshot: CanonicalGeneratedArtifactReadSnapshot?,
        writeSideEvidence: CanonicalGeneratedArtifactWriteSideEvidenceLinkage,
        legacyFallbackAvailable: Bool = true,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String? = nil,
        canonicalReadFailureReason: String? = nil
    ) -> CanonicalGeneratedArtifactReadSourceResult {
        let canonicalProjectionComplete = canonicalSnapshot.map { snapshot in
            !snapshot.failures.contains { failure in
                failure.kind == .snapshotMissing
                    || failure.kind == .contentLeakRisk
                    || failure.kind == .unsafePathToken
                    || failure.kind == .audioConfusionRisk
            }
        } ?? false
        let diffReport = canonicalSnapshot.map {
            CanonicalGeneratedArtifactReadSideParallelDiff.compare(legacy: legacySnapshot, canonical: $0)
        }
        let evaluatedDiagnostic = diagnostic(
            .canonicalGeneratedArtifactReadSourceEvaluated,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: configuration.mode.rawValue,
            reason: "domain=generatedArtifacts"
        )

        switch configuration.mode {
        case .legacy:
            return makeResult(
                returnedSnapshot: legacySnapshot,
                legacySnapshot: legacySnapshot,
                canonicalSnapshot: canonicalSnapshot,
                diffReport: nil,
                gateResult: nil,
                fallback: .legacyDefault,
                diagnostics: [
                    evaluatedDiagnostic,
                    legacyReturnedDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "defaultLegacy")
                ],
                fatalForFutureStage: false
            )
        case .blocked:
            return makeResult(
                returnedSnapshot: legacySnapshot,
                legacySnapshot: legacySnapshot,
                canonicalSnapshot: canonicalSnapshot,
                diffReport: diffReport,
                gateResult: nil,
                fallback: .blockedMode,
                diagnostics: [
                    evaluatedDiagnostic,
                    guardedBlockedDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "blockedMode"),
                    fallbackDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "blockedMode")
                ],
                fatalForFutureStage: false
            )
        case .parallelCompare:
            let diagnostics = [
                evaluatedDiagnostic,
                canonicalCandidateDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "parallelCompare"),
                outputDiagnostic(diffReport: diffReport, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole),
                legacyReturnedDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "parallelCompareReturnsLegacy")
            ]
            return makeResult(
                returnedSnapshot: legacySnapshot,
                legacySnapshot: legacySnapshot,
                canonicalSnapshot: canonicalSnapshot,
                diffReport: diffReport,
                gateResult: nil,
                fallback: .legacyDefault,
                diagnostics: diagnostics,
                fatalForFutureStage: diffReport?.divergenceCount ?? 0 > 0
            )
        case .canonicalCandidate:
            let diagnostics = [
                evaluatedDiagnostic,
                canonicalCandidateDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "candidateBuiltNotServed"),
                outputDiagnostic(diffReport: diffReport, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole),
                legacyReturnedDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "canonicalCandidateNotServed")
            ]
            return makeResult(
                returnedSnapshot: legacySnapshot,
                legacySnapshot: legacySnapshot,
                canonicalSnapshot: canonicalSnapshot,
                diffReport: diffReport,
                gateResult: nil,
                fallback: .legacyDefault,
                diagnostics: diagnostics,
                fatalForFutureStage: diffReport?.divergenceCount ?? 0 > 0
            )
        case .guardedCanonicalRead:
            guard let canonicalSnapshot, let diffReport else {
                return makeResult(
                    returnedSnapshot: legacySnapshot,
                    legacySnapshot: legacySnapshot,
                    canonicalSnapshot: canonicalSnapshot,
                    diffReport: nil,
                    gateResult: nil,
                    fallback: .canonicalProjectionMissing,
                    diagnostics: [
                        evaluatedDiagnostic,
                        guardedBlockedDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "canonicalProjectionMissing"),
                        fallbackDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "canonicalProjectionMissing")
                    ],
                    fatalForFutureStage: true
                )
            }
            let gate = CanonicalGeneratedArtifactReadCutoverGate.evaluate(
                context: CanonicalGeneratedArtifactReadCutoverGateContext(
                    configuration: configuration,
                    writeSideEvidence: writeSideEvidence,
                    legacyFallbackAvailable: legacyFallbackAvailable,
                    canonicalProjectionComplete: canonicalProjectionComplete,
                    artifactRouteChanged: false,
                    generatedArtifactUploadJobCreated: false
                ),
                diffReport: diffReport,
                matrix: matrix,
                trigger: trigger,
                nodeRole: nodeRole,
                syncRunID: syncRunID
            )
            var diagnostics = [
                evaluatedDiagnostic,
                canonicalCandidateDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "guardedCanonicalRead")
            ] + gate.diagnostics + [
                outputDiagnostic(diffReport: diffReport, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole)
            ]
            if let canonicalReadFailureReason {
                diagnostics.append(fallbackDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: canonicalReadFailureReason))
                return makeResult(
                    returnedSnapshot: legacySnapshot,
                    legacySnapshot: legacySnapshot,
                    canonicalSnapshot: canonicalSnapshot,
                    diffReport: diffReport,
                    gateResult: gate,
                    fallback: .canonicalReadException,
                    diagnostics: diagnostics,
                    fatalForFutureStage: true
                )
            }
            guard gate.allowed else {
                diagnostics.append(guardedBlockedDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: gate.blockers.map(\.rawValue).joined(separator: "+")))
                diagnostics.append(fallbackDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: fallbackReason(for: gate)))
                return makeResult(
                    returnedSnapshot: legacySnapshot,
                    legacySnapshot: legacySnapshot,
                    canonicalSnapshot: canonicalSnapshot,
                    diffReport: diffReport,
                    gateResult: gate,
                    fallback: fallback(for: gate),
                    diagnostics: diagnostics,
                    fatalForFutureStage: diffReport.hasFatalBlocker || diffReport.divergenceCount > 0
                )
            }
            diagnostics.append(
                diagnostic(
                    .canonicalGeneratedArtifactGuardedCanonicalReadAllowed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "allowed",
                    reason: "explicitInternalTestConfig"
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalGeneratedArtifactGuardedCanonicalReadServed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "served",
                    reason: canonicalSnapshot.diagnosticsSummary
                )
            )
            return makeResult(
                returnedSnapshot: canonicalSnapshot,
                legacySnapshot: legacySnapshot,
                canonicalSnapshot: canonicalSnapshot,
                diffReport: diffReport,
                gateResult: gate,
                fallback: .none,
                diagnostics: diagnostics,
                fatalForFutureStage: false
            )
        }
    }

    private nonisolated func makeResult(
        returnedSnapshot: CanonicalGeneratedArtifactReadSnapshot,
        legacySnapshot: CanonicalGeneratedArtifactReadSnapshot,
        canonicalSnapshot: CanonicalGeneratedArtifactReadSnapshot?,
        diffReport: CanonicalGeneratedArtifactReadSideDiffReport?,
        gateResult: CanonicalGeneratedArtifactReadCutoverGateResult?,
        fallback: CanonicalGeneratedArtifactReadFallback,
        diagnostics: [CanonicalGeneratedArtifactReadSideDiagnostic],
        fatalForFutureStage: Bool
    ) -> CanonicalGeneratedArtifactReadSourceResult {
        let returnedSource = returnedSnapshot.source
        let readSource = CanonicalGeneratedArtifactReadSource(source: returnedSource, snapshot: returnedSnapshot)
        let limitedDiagnostics = configuration.recordDiagnostics
            ? Array(diagnostics.prefix(configuration.maxDiagnosticsEvents))
            : []
        return CanonicalGeneratedArtifactReadSourceResult(
            mode: configuration.mode,
            returnedSource: returnedSource,
            readSource: readSource,
            legacySnapshot: legacySnapshot,
            canonicalCandidate: canonicalSnapshot,
            diffReport: diffReport,
            gateResult: gateResult,
            fallback: fallback,
            fallbackCount: fallback == .none ? 0 : 1,
            canonicalReadServed: returnedSource == .canonical && fallback == .none,
            legacyReadReturned: returnedSource == .legacy,
            canonicalCandidateBuilt: canonicalSnapshot != nil && configuration.mode != .legacy && configuration.mode != .blocked,
            fatalForFutureStage: fatalForFutureStage,
            storeMutated: false,
            syncOrUploadTriggered: false,
            artifactDownloaded: false,
            artifactApplied: false,
            generatedArtifactFileWritten: false,
            uploadJobCreated: false,
            inventoryResponseMutated: false,
            receiveJSONMutated: false,
            transcriptionOrNoteGenerationTriggered: false,
            diagnostics: limitedDiagnostics,
            diagnosticsSummary: [
                "mode=\(configuration.mode.rawValue)",
                "returned=\(returnedSource.rawValue)",
                "fallback=\(fallback.rawValue)",
                "canonicalServed=\(returnedSource == .canonical && fallback == .none)",
                "items=\(returnedSnapshot.itemCount)",
                "failures=\(returnedSnapshot.failureCount)",
                "storeMutated=false",
                "syncOrUploadTriggered=false",
                "artifactDownloaded=false",
                "artifactApplied=false",
                "generatedArtifactFileWritten=false",
                "uploadJobCreated=false",
                "inventoryResponseMutated=false",
                "receiveJSONMutated=false",
                "transcriptionOrNoteGenerationTriggered=false"
            ].joined(separator: ",")
        )
    }

    private nonisolated func diagnostic(
        _ kind: CanonicalGeneratedArtifactReadSideDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        result: String,
        reason: String
    ) -> CanonicalGeneratedArtifactReadSideDiagnostic {
        CanonicalGeneratedArtifactReadSideDiagnostic(
            kind: kind,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: result,
            reason: reason
        )
    }

    private nonisolated func legacyReturnedDiagnostic(
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        reason: String
    ) -> CanonicalGeneratedArtifactReadSideDiagnostic {
        diagnostic(.canonicalGeneratedArtifactReadSourceLegacyReturned, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "legacy", reason: reason)
    }

    private nonisolated func canonicalCandidateDiagnostic(
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        reason: String
    ) -> CanonicalGeneratedArtifactReadSideDiagnostic {
        diagnostic(.canonicalGeneratedArtifactReadSourceCanonicalCandidateBuilt, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "candidate", reason: reason)
    }

    private nonisolated func guardedBlockedDiagnostic(
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        reason: String
    ) -> CanonicalGeneratedArtifactReadSideDiagnostic {
        diagnostic(.canonicalGeneratedArtifactGuardedCanonicalReadBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked", reason: reason)
    }

    private nonisolated func fallbackDiagnostic(
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        reason: String
    ) -> CanonicalGeneratedArtifactReadSideDiagnostic {
        diagnostic(.canonicalGeneratedArtifactGuardedCanonicalReadFallback, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "legacy", reason: reason)
    }

    private nonisolated func outputDiagnostic(
        diffReport: CanonicalGeneratedArtifactReadSideDiffReport?,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> CanonicalGeneratedArtifactReadSideDiagnostic {
        diagnostic(
            diffReport?.equivalent == true ? .canonicalGeneratedArtifactReadOutputEquivalent : .canonicalGeneratedArtifactReadOutputDivergent,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: diffReport?.equivalent == true ? "equivalent" : "divergent",
            reason: diffReport?.diagnosticsSummary ?? "canonicalCandidateMissing"
        )
    }

    private nonisolated func fallback(for gate: CanonicalGeneratedArtifactReadCutoverGateResult) -> CanonicalGeneratedArtifactReadFallback {
        if gate.blockers.contains(.contentLeakRisk) {
            return .contentLeakRisk
        }
        if gate.blockers.contains(.unsafePathToken) {
            return .unsafePathToken
        }
        if gate.blockers.contains(.parentTombstone) {
            return .parentTombstone
        }
        if gate.blockers.contains(.audioConfusionRisk) {
            return .audioConfusionRisk
        }
        if gate.blockers.contains(.unsupportedArtifact) {
            return .unsupportedArtifact
        }
        if gate.blockers.contains(.readSideDivergence) {
            return .divergenceDetected
        }
        if gate.blockers.contains(.canonicalProjectionIncomplete) {
            return .canonicalProjectionMissing
        }
        return .gateBlocked
    }

    private nonisolated func fallbackReason(for gate: CanonicalGeneratedArtifactReadCutoverGateResult) -> String {
        let reason = gate.blockers.map(\.rawValue).joined(separator: "+")
        return reason.isEmpty ? "gateBlocked" : reason
    }
}

nonisolated enum CanonicalGeneratedArtifactObservationEventKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case noCommitObserved
    case commitObserved
    case writeSideCanonicalCommit
    case rollbackObserved
    case rollbackFailureObserved
    case legacyFallbackObserved
    case duplicateSuppressionObserved
    case readSideEquivalent
    case readSideDivergent
    case readSideCanonicalServed
    case readSideLegacyFallback
    case contentLeakRisk
    case unsafePathToken
    case unsupportedArtifactKind
    case tombstonedParentBlocker
    case audioConfusionRisk
    case generatedArtifactDownloadApplySuccess
    case runtimeSwitchEnabled
    case legacyFallbackMissing
    case activePilotGeneratedArtifacts
    case otherDomainsStaticOnly
    case unsafeSideEffect
}

nonisolated struct CanonicalGeneratedArtifactObservationEvent: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "", artifactID ?? ""].joined(separator: "|") }

    var kind: CanonicalGeneratedArtifactObservationEventKind
    var objectID: String?
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind?

    nonisolated init(
        kind: CanonicalGeneratedArtifactObservationEventKind,
        objectID: String? = nil,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind? = nil
    ) {
        self.kind = kind
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown-recording") }
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.artifactKind = artifactKind
    }
}

nonisolated struct CanonicalGeneratedArtifactObservationSummary: Codable, Equatable, Sendable {
    var writeSideCanonicalCommitCount: Int
    var writeSideRollbackCount: Int
    var writeSideRollbackFailureCount: Int
    var legacyFallbackCount: Int
    var duplicateSuppressionCount: Int
    var readSideCanonicalServedCount: Int
    var readSideLegacyFallbackCount: Int
    var readSideDivergenceCount: Int
    var unsupportedArtifactCount: Int
    var contentLeakRiskCount: Int
    var unsafePathTokenCount: Int
    var parentTombstoneBlockCount: Int
    var audioConfusionRiskCount: Int
    var runtimeSwitch: Bool
    var activePilotGeneratedArtifacts: Bool
    var otherDomainsStaticOnly: Bool
    var observationComplete: Bool

    nonisolated init(
        writeSideCanonicalCommitCount: Int = 0,
        writeSideRollbackCount: Int = 0,
        writeSideRollbackFailureCount: Int = 0,
        legacyFallbackCount: Int = 0,
        duplicateSuppressionCount: Int = 0,
        readSideCanonicalServedCount: Int = 0,
        readSideLegacyFallbackCount: Int = 0,
        readSideDivergenceCount: Int = 0,
        unsupportedArtifactCount: Int = 0,
        contentLeakRiskCount: Int = 0,
        unsafePathTokenCount: Int = 0,
        parentTombstoneBlockCount: Int = 0,
        audioConfusionRiskCount: Int = 0,
        runtimeSwitch: Bool = false,
        activePilotGeneratedArtifacts: Bool = false,
        otherDomainsStaticOnly: Bool = true,
        observationComplete: Bool = false
    ) {
        self.writeSideCanonicalCommitCount = max(0, writeSideCanonicalCommitCount)
        self.writeSideRollbackCount = max(0, writeSideRollbackCount)
        self.writeSideRollbackFailureCount = max(0, writeSideRollbackFailureCount)
        self.legacyFallbackCount = max(0, legacyFallbackCount)
        self.duplicateSuppressionCount = max(0, duplicateSuppressionCount)
        self.readSideCanonicalServedCount = max(0, readSideCanonicalServedCount)
        self.readSideLegacyFallbackCount = max(0, readSideLegacyFallbackCount)
        self.readSideDivergenceCount = max(0, readSideDivergenceCount)
        self.unsupportedArtifactCount = max(0, unsupportedArtifactCount)
        self.contentLeakRiskCount = max(0, contentLeakRiskCount)
        self.unsafePathTokenCount = max(0, unsafePathTokenCount)
        self.parentTombstoneBlockCount = max(0, parentTombstoneBlockCount)
        self.audioConfusionRiskCount = max(0, audioConfusionRiskCount)
        self.runtimeSwitch = runtimeSwitch
        self.activePilotGeneratedArtifacts = activePilotGeneratedArtifacts
        self.otherDomainsStaticOnly = otherDomainsStaticOnly
        self.observationComplete = observationComplete
    }

    nonisolated var diagnosticsSummary: String {
        [
            "writeCommit=\(writeSideCanonicalCommitCount)",
            "rollback=\(writeSideRollbackCount)",
            "rollbackFailure=\(writeSideRollbackFailureCount)",
            "legacyFallback=\(legacyFallbackCount)",
            "duplicateSuppression=\(duplicateSuppressionCount)",
            "readCanonicalServed=\(readSideCanonicalServedCount)",
            "readLegacyFallback=\(readSideLegacyFallbackCount)",
            "readDivergence=\(readSideDivergenceCount)",
            "unsupported=\(unsupportedArtifactCount)",
            "contentLeakRisk=\(contentLeakRiskCount)",
            "unsafePathToken=\(unsafePathTokenCount)",
            "parentTombstone=\(parentTombstoneBlockCount)",
            "audioConfusion=\(audioConfusionRiskCount)",
            "runtimeSwitch=\(runtimeSwitch)",
            "activePilot=generatedArtifacts:\(activePilotGeneratedArtifacts)",
            "otherDomainsStaticOnly=\(otherDomainsStaticOnly)",
            "observationComplete=\(observationComplete)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalGeneratedArtifactObservationPolicy: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var allowObservationCompletion: Bool
    var requireWriteSideEvidence: Bool
    var requireReadSideCanonicalServedEvidence: Bool
    var requireReadSideEquivalence: Bool
    var requireLegacyFallback: Bool
    var requireGeneratedArtifactsActivePilot: Bool
    var requireOtherDomainsStaticOnly: Bool

    nonisolated init(
        isEnabled: Bool = false,
        allowObservationCompletion: Bool = false,
        requireWriteSideEvidence: Bool = false,
        requireReadSideCanonicalServedEvidence: Bool = false,
        requireReadSideEquivalence: Bool = true,
        requireLegacyFallback: Bool = true,
        requireGeneratedArtifactsActivePilot: Bool = false,
        requireOtherDomainsStaticOnly: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.allowObservationCompletion = allowObservationCompletion
        self.requireWriteSideEvidence = requireWriteSideEvidence
        self.requireReadSideCanonicalServedEvidence = requireReadSideCanonicalServedEvidence
        self.requireReadSideEquivalence = requireReadSideEquivalence
        self.requireLegacyFallback = requireLegacyFallback
        self.requireGeneratedArtifactsActivePilot = requireGeneratedArtifactsActivePilot
        self.requireOtherDomainsStaticOnly = requireOtherDomainsStaticOnly
    }

    nonisolated static let disabled = CanonicalGeneratedArtifactObservationPolicy()

    nonisolated static func explicitInternalTest(
        allowObservationCompletion: Bool = false,
        requireWriteSideEvidence: Bool = false,
        requireReadSideCanonicalServedEvidence: Bool = false
    ) -> CanonicalGeneratedArtifactObservationPolicy {
        CanonicalGeneratedArtifactObservationPolicy(
            isEnabled: true,
            allowObservationCompletion: allowObservationCompletion,
            requireWriteSideEvidence: requireWriteSideEvidence,
            requireReadSideCanonicalServedEvidence: requireReadSideCanonicalServedEvidence,
            requireGeneratedArtifactsActivePilot: true
        )
    }
}

nonisolated struct CanonicalGeneratedArtifactObservationWindow: Codable, Equatable, Sendable {
    var policy: CanonicalGeneratedArtifactObservationPolicy
    var events: [CanonicalGeneratedArtifactObservationEvent]

    nonisolated init(
        policy: CanonicalGeneratedArtifactObservationPolicy = .disabled,
        events: [CanonicalGeneratedArtifactObservationEvent] = []
    ) {
        self.policy = policy
        self.events = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.id < $1.id }
    }

    nonisolated func recording(_ event: CanonicalGeneratedArtifactObservationEvent) -> CanonicalGeneratedArtifactObservationWindow {
        guard policy.isEnabled else {
            return self
        }
        return CanonicalGeneratedArtifactObservationWindow(policy: policy, events: events + [event])
    }

    nonisolated func recordingReadSide(_ diffReport: CanonicalGeneratedArtifactReadSideDiffReport) -> CanonicalGeneratedArtifactObservationWindow {
        recording(CanonicalGeneratedArtifactObservationEvent(kind: diffReport.equivalent ? .readSideEquivalent : .readSideDivergent))
    }

    nonisolated func recordingReadSource(_ result: CanonicalGeneratedArtifactReadSourceResult) -> CanonicalGeneratedArtifactObservationWindow {
        var window = self
        if result.canonicalReadServed {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .readSideCanonicalServed))
        }
        if result.legacyReadReturned || result.fallback != .none {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .readSideLegacyFallback))
        }
        if let diffReport = result.diffReport {
            window = window.recordingReadSide(diffReport)
        }
        return window
    }

    nonisolated func recordingWriteSide(_ evidence: CanonicalGeneratedArtifactWriteSideEvidenceLinkage) -> CanonicalGeneratedArtifactObservationWindow {
        var window = self
        if evidence.successfulCommitCount > 0 {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .writeSideCanonicalCommit))
        }
        if evidence.rollbackCount > 0 {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .rollbackObserved))
        }
        if evidence.rollbackFailureCount > 0 {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .rollbackFailureObserved))
        }
        if evidence.legacyFallbackCount > 0 {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .legacyFallbackObserved))
        }
        if evidence.duplicateSuppressionCount > 0 {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .duplicateSuppressionObserved))
        }
        if evidence.contentLeakRiskCount > 0 {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .contentLeakRisk))
        }
        if evidence.unsafePathTokenCount > 0 {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .unsafePathToken))
        }
        if evidence.parentTombstoneBlockCount > 0 {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .tombstonedParentBlocker))
        }
        if evidence.audioConfusionRiskCount > 0 {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .audioConfusionRisk))
        }
        if evidence.runtimeSwitchEnabled {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .runtimeSwitchEnabled))
        }
        if evidence.hasCleanStagedCanaryEvidence {
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .activePilotGeneratedArtifacts))
            window = window.recording(CanonicalGeneratedArtifactObservationEvent(kind: .otherDomainsStaticOnly))
        }
        return window
    }

    nonisolated var summary: CanonicalGeneratedArtifactObservationSummary {
        let counts = Dictionary(grouping: events, by: \.kind).mapValues(\.count)
        return CanonicalGeneratedArtifactObservationSummary(
            writeSideCanonicalCommitCount: (counts[.writeSideCanonicalCommit] ?? 0) + (counts[.commitObserved] ?? 0),
            writeSideRollbackCount: counts[.rollbackObserved] ?? 0,
            writeSideRollbackFailureCount: counts[.rollbackFailureObserved] ?? 0,
            legacyFallbackCount: counts[.legacyFallbackObserved] ?? 0,
            duplicateSuppressionCount: counts[.duplicateSuppressionObserved] ?? 0,
            readSideCanonicalServedCount: counts[.readSideCanonicalServed] ?? 0,
            readSideLegacyFallbackCount: counts[.readSideLegacyFallback] ?? 0,
            readSideDivergenceCount: counts[.readSideDivergent] ?? 0,
            unsupportedArtifactCount: counts[.unsupportedArtifactKind] ?? 0,
            contentLeakRiskCount: counts[.contentLeakRisk] ?? 0,
            unsafePathTokenCount: counts[.unsafePathToken] ?? 0,
            parentTombstoneBlockCount: counts[.tombstonedParentBlocker] ?? 0,
            audioConfusionRiskCount: counts[.audioConfusionRisk] ?? 0,
            runtimeSwitch: (counts[.runtimeSwitchEnabled] ?? 0) > 0,
            activePilotGeneratedArtifacts: (counts[.activePilotGeneratedArtifacts] ?? 0) > 0,
            otherDomainsStaticOnly: (counts[.otherDomainsStaticOnly] ?? 0) > 0,
            observationComplete: false
        )
    }

    nonisolated var diagnosticsSummary: String {
        return [
            "domain=generatedArtifacts",
            "observationEnabled=\(policy.isEnabled)",
            "eventCount=\(events.count)",
            summary.diagnosticsSummary
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalGeneratedArtifactObservationGateStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case incomplete
    case observationComplete
    case blocked
}

nonisolated enum CanonicalGeneratedArtifactObservationBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case completionNotAllowed
    case missingWriteSideCommit
    case missingReadSideCanonicalServed
    case missingReadSideEquivalence
    case readSideDivergence
    case missingLegacyFallback
    case runtimeSwitchEnabled
    case activePilotNotGeneratedArtifacts
    case otherDomainsNotStaticOnly
    case rollbackFailure
    case contentLeakRisk
    case unsafePathToken
    case unsupportedArtifactKind
    case tombstonedParentResurrectionRisk
    case audioConfusionRisk
    case unsafeSideEffect
}

nonisolated struct CanonicalGeneratedArtifactObservationGate: Codable, Equatable, Sendable {
    var status: CanonicalGeneratedArtifactObservationGateStatus
    var blockers: [CanonicalGeneratedArtifactObservationBlocker]
    var diagnosticsSummary: String

    nonisolated var observationComplete: Bool {
        status == .observationComplete
    }

    nonisolated static func evaluate(
        window: CanonicalGeneratedArtifactObservationWindow
    ) -> CanonicalGeneratedArtifactObservationGate {
        var blockers: [CanonicalGeneratedArtifactObservationBlocker] = []
        guard window.policy.isEnabled else {
            return CanonicalGeneratedArtifactObservationGate(
                status: .disabled,
                blockers: [.disabled],
                diagnosticsSummary: "domain=generatedArtifacts,status=disabled"
            )
        }
        let eventKinds = Set(window.events.map(\.kind))
        let summary = window.summary
        if !window.policy.allowObservationCompletion {
            blockers.append(.completionNotAllowed)
        }
        if window.policy.requireWriteSideEvidence && summary.writeSideCanonicalCommitCount == 0 {
            blockers.append(.missingWriteSideCommit)
        }
        if window.policy.requireReadSideCanonicalServedEvidence && summary.readSideCanonicalServedCount == 0 {
            blockers.append(.missingReadSideCanonicalServed)
        }
        if window.policy.requireReadSideEquivalence && !eventKinds.contains(.readSideEquivalent) {
            blockers.append(.missingReadSideEquivalence)
        }
        if eventKinds.contains(.readSideDivergent) { blockers.append(.readSideDivergence) }
        if window.policy.requireLegacyFallback && !eventKinds.contains(.legacyFallbackObserved) {
            blockers.append(.missingLegacyFallback)
        }
        if eventKinds.contains(.runtimeSwitchEnabled) { blockers.append(.runtimeSwitchEnabled) }
        if window.policy.requireGeneratedArtifactsActivePilot && !summary.activePilotGeneratedArtifacts {
            blockers.append(.activePilotNotGeneratedArtifacts)
        }
        if window.policy.requireOtherDomainsStaticOnly && !summary.otherDomainsStaticOnly {
            blockers.append(.otherDomainsNotStaticOnly)
        }
        if summary.writeSideRollbackFailureCount > 0 { blockers.append(.rollbackFailure) }
        if eventKinds.contains(.contentLeakRisk) { blockers.append(.contentLeakRisk) }
        if eventKinds.contains(.unsafePathToken) { blockers.append(.unsafePathToken) }
        if eventKinds.contains(.unsupportedArtifactKind) { blockers.append(.unsupportedArtifactKind) }
        if eventKinds.contains(.tombstonedParentBlocker) { blockers.append(.tombstonedParentResurrectionRisk) }
        if eventKinds.contains(.audioConfusionRisk) { blockers.append(.audioConfusionRisk) }
        if eventKinds.contains(.unsafeSideEffect) { blockers.append(.unsafeSideEffect) }
        let unique = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let status: CanonicalGeneratedArtifactObservationGateStatus = unique.isEmpty ? .observationComplete : .incomplete
        return CanonicalGeneratedArtifactObservationGate(
            status: status,
            blockers: unique,
            diagnosticsSummary: "domain=generatedArtifacts,status=\(status.rawValue),blockers=\(unique.map(\.rawValue).joined(separator: "+"))"
        )
    }
}

nonisolated enum CanonicalGeneratedArtifactRetirementBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingWriteSideCanaryEvidence
    case missingReadSideCutoverEvidence
    case observationIncomplete
    case fallbackMissing
    case divergencePresent
    case unsupportedArtifactKind
    case contentLeakRisk
    case unsafePathToken
    case tombstonedParentResurrectionRisk
    case audioConfusionRisk
    case unresolvedConflict
    case unsafeSideEffect
    case activePilotNotGeneratedArtifacts
    case otherActivePilot
    case manualAuditRequired
    case runtimeSwitchEnabled
    case defaultCutoverEnabled
}

nonisolated enum CanonicalGeneratedArtifactRetirementCandidateStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case ready
    case blocked
}

nonisolated struct CanonicalGeneratedArtifactRetirementCandidateReport: Codable, Equatable, Sendable {
    var status: CanonicalGeneratedArtifactRetirementCandidateStatus
    var ready: Bool
    var blockers: [CanonicalGeneratedArtifactRetirementBlocker]
    var retirementExecutionPerformed: Bool
    var legacyDeleted: Bool
    var legacyDisabled: Bool
    var manualAuditRequired: Bool
    var diagnosticsSummary: String

    nonisolated static let blockedByDefault = CanonicalGeneratedArtifactRetirementCandidateReport(
        status: .blocked,
        ready: false,
        blockers: [.missingReadSideCutoverEvidence, .observationIncomplete],
        retirementExecutionPerformed: false,
        legacyDeleted: false,
        legacyDisabled: false,
        manualAuditRequired: true,
        diagnosticsSummary: "domain=generatedArtifacts,ready=false,manualAuditRequired=true,execution=false,legacyDeleted=false,legacyDisabled=false"
    )
}

nonisolated enum CanonicalGeneratedArtifactRetirementCandidateGate {
    nonisolated static func evaluate(
        writeSideCanarySuccessEvidence: Bool = false,
        readSideCutoverEvidence: Bool = false,
        readSideCanonicalReadEvidence: Bool = false,
        observationGate: CanonicalGeneratedArtifactObservationGate? = nil,
        fallbackAvailable: Bool = true,
        manualAuditRequired: Bool = true,
        runtimeSwitchEnabled: Bool = false,
        defaultCutoverEnabled: Bool = false,
        activePilotGeneratedArtifacts: Bool = true,
        otherActivePilot: Bool = false,
        unresolvedConflictCount: Int = 0,
        unsafeSideEffectDetected: Bool = false,
        diffReport: CanonicalGeneratedArtifactReadSideDiffReport? = nil
    ) -> CanonicalGeneratedArtifactRetirementCandidateReport {
        var blockers: [CanonicalGeneratedArtifactRetirementBlocker] = []
        let hasReadEvidence = readSideCutoverEvidence || readSideCanonicalReadEvidence
        if !writeSideCanarySuccessEvidence { blockers.append(.missingWriteSideCanaryEvidence) }
        if !hasReadEvidence { blockers.append(.missingReadSideCutoverEvidence) }
        if observationGate?.observationComplete != true { blockers.append(.observationIncomplete) }
        if !fallbackAvailable { blockers.append(.fallbackMissing) }
        if !manualAuditRequired { blockers.append(.manualAuditRequired) }
        if runtimeSwitchEnabled { blockers.append(.runtimeSwitchEnabled) }
        if defaultCutoverEnabled { blockers.append(.defaultCutoverEnabled) }
        if !activePilotGeneratedArtifacts { blockers.append(.activePilotNotGeneratedArtifacts) }
        if otherActivePilot { blockers.append(.otherActivePilot) }
        if unresolvedConflictCount > 0 { blockers.append(.unresolvedConflict) }
        if unsafeSideEffectDetected { blockers.append(.unsafeSideEffect) }
        if let diffReport, !diffReport.equivalent {
            blockers.append(.divergencePresent)
            for blocker in diffReport.blockers {
                switch blocker {
                case .unsafePathToken: blockers.append(.unsafePathToken)
                case .contentLeakRisk: blockers.append(.contentLeakRisk)
                case .unsupportedArtifactKind: blockers.append(.unsupportedArtifactKind)
                case .tombstonedParentResurrectionRisk: blockers.append(.tombstonedParentResurrectionRisk)
                case .audioConfusionRisk: blockers.append(.audioConfusionRisk)
                case .blockingDivergence, .missingLegacySnapshot, .missingCanonicalSnapshot:
                    break
                }
            }
        }
        let unique = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        return CanonicalGeneratedArtifactRetirementCandidateReport(
            status: unique.isEmpty ? .ready : .blocked,
            ready: unique.isEmpty,
            blockers: unique,
            retirementExecutionPerformed: false,
            legacyDeleted: false,
            legacyDisabled: false,
            manualAuditRequired: manualAuditRequired,
            diagnosticsSummary: [
                "domain=generatedArtifacts",
                "ready=\(unique.isEmpty)",
                "manualAuditRequired=\(manualAuditRequired)",
                "execution=false",
                "legacyDeleted=false",
                "legacyDisabled=false",
                "blockers=\(unique.map(\.rawValue).joined(separator: "+"))"
            ].joined(separator: ",")
        )
    }
}

nonisolated enum CanonicalGeneratedArtifactTemplateReadiness: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingProjection
    case missingPlanner
    case missingNoCommit
    case missingRealApplyPort
    case missingCommitExecutor
    case missingAppSeam
    case missingReadSideSeam
    case missingObservation
    case missingRetirementGate
    case readyForNextPilotN0
    case blocked
}

nonisolated enum CanonicalGeneratedArtifactTemplateBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
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
    case missingFallback
    case missingRollback
    case missingFailureInjection
    case successOnlySuppressionMissing
    case missingTests
    case missingDocs
}

nonisolated struct CanonicalGeneratedArtifactTemplateReport: Codable, Equatable, Sendable {
    var readiness: CanonicalGeneratedArtifactTemplateReadiness
    var blockers: [CanonicalGeneratedArtifactTemplateBlocker]
    var readyForNextPilotN0: Bool
    var diagnosticsSummary: String

    nonisolated static func audit(
        projection: Bool,
        planner: Bool,
        noCommit: Bool,
        realApplyPort: Bool,
        commitExecutor: Bool,
        appSeamDefaultOff: Bool,
        readSideSeam: Bool,
        observation: Bool,
        retirementGate: Bool,
        migrationMatrixStatus: Bool,
        fallback: Bool,
        rollback: Bool,
        failureInjection: Bool,
        successOnlySuppression: Bool,
        tests: Bool,
        docs: Bool
    ) -> CanonicalGeneratedArtifactTemplateReport {
        var blockers: [CanonicalGeneratedArtifactTemplateBlocker] = []
        if !projection { blockers.append(.missingProjection) }
        if !planner { blockers.append(.missingPlanner) }
        if !noCommit { blockers.append(.missingNoCommit) }
        if !realApplyPort { blockers.append(.missingRealApplyPort) }
        if !commitExecutor { blockers.append(.missingCommitExecutor) }
        if !appSeamDefaultOff { blockers.append(.missingAppSeam) }
        if !readSideSeam { blockers.append(.missingReadSideSeam) }
        if !observation { blockers.append(.missingObservation) }
        if !retirementGate { blockers.append(.missingRetirementGate) }
        if !migrationMatrixStatus { blockers.append(.missingMigrationMatrixStatus) }
        if !fallback { blockers.append(.missingFallback) }
        if !rollback { blockers.append(.missingRollback) }
        if !failureInjection { blockers.append(.missingFailureInjection) }
        if !successOnlySuppression { blockers.append(.successOnlySuppressionMissing) }
        if !tests { blockers.append(.missingTests) }
        if !docs { blockers.append(.missingDocs) }
        let unique = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let readiness: CanonicalGeneratedArtifactTemplateReadiness
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
        } else if unique.isEmpty {
            readiness = .readyForNextPilotN0
        } else {
            readiness = .blocked
        }
        return CanonicalGeneratedArtifactTemplateReport(
            readiness: readiness,
            blockers: unique,
            readyForNextPilotN0: unique.isEmpty,
            diagnosticsSummary: "domain=generatedArtifacts,readiness=\(readiness.rawValue),blockers=\(unique.map(\.rawValue).joined(separator: "+"))"
        )
    }

    nonisolated static func currentV821Audit() -> CanonicalGeneratedArtifactTemplateReport {
        audit(
            projection: true,
            planner: true,
            noCommit: true,
            realApplyPort: true,
            commitExecutor: true,
            appSeamDefaultOff: true,
            readSideSeam: true,
            observation: true,
            retirementGate: true,
            migrationMatrixStatus: true,
            fallback: true,
            rollback: true,
            failureInjection: true,
            successOnlySuppression: true,
            tests: true,
            docs: true
        )
    }
}
