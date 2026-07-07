//
//  CanonicalRetirementReadiness.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalRetirementDomain: String, Codable, Equatable, CaseIterable, Sendable {
    case recordingMetadata
    case recordingAudio
    case generatedArtifacts
    case folders
    case studyItems
    case tombstones
    case conflicts
    case apply
    case transferState
    case objectProjection
    case inventory
    case transport
    case uploadRuntime
    case physicalStorage
}

nonisolated enum CanonicalRetirementStatus: String, Codable, Equatable, Sendable {
    case notStarted
    case shadowOnly
    case planningOnly
    case applyBridged
    case semanticsComplete
    case runtimeComplete
    case readyToRetireLegacy
    case blocked
}

nonisolated enum CanonicalRetirementBlockerKind: String, Codable, Equatable, Sendable {
    case missingCanonicalManifest
    case unsupportedObjectKinds
    case fallbackUsed
    case conflictsUnresolved
    case applyBridgeMissing
    case transferStateUnmapped
    case uiStillReadsLegacyStatus
    case routeStillLegacy
    case physicalStoreStillLegacy
}

nonisolated struct CanonicalRetirementBlocker: Codable, Equatable, Identifiable, Sendable {
    var id: String { [domain.rawValue, kind.rawValue, detail ?? ""].joined(separator: "|") }
    var domain: CanonicalRetirementDomain
    var kind: CanonicalRetirementBlockerKind
    var detail: String?
}

nonisolated struct CanonicalRetirementReadinessReport: Codable, Equatable, Sendable {
    var generatedAt: CanonicalTimestamp
    var statuses: [CanonicalRetirementDomain: CanonicalRetirementStatus]
    var blockers: [CanonicalRetirementBlocker]

    nonisolated func status(for domain: CanonicalRetirementDomain) -> CanonicalRetirementStatus {
        statuses[domain] ?? .notStarted
    }
}

nonisolated struct CanonicalRetirementReadinessEvaluator {
    nonisolated init() {}

    nonisolated func evaluate(
        manifest: CanonicalManifest?,
        libraryPlan: CanonicalLibrarySyncPlan?,
        applyPlan: CanonicalApplyPlan?,
        transferProjection: CanonicalTransferProjection?,
        inventoryCoverage: CanonicalInventoryCoverageReport?,
        fallbackUsed: Bool,
        generatedAt: Date = Date()
    ) -> CanonicalRetirementReadinessReport {
        var statuses = Dictionary(uniqueKeysWithValues: CanonicalRetirementDomain.allCases.map { ($0, CanonicalRetirementStatus.notStarted) })
        var blockers: [CanonicalRetirementBlocker] = []

        if manifest == nil {
            add(.inventory, .missingCanonicalManifest, "manifestMissing", statuses: &statuses, blockers: &blockers)
        } else {
            statuses[.recordingMetadata] = applyPlan == nil ? .planningOnly : .applyBridged
            statuses[.recordingAudio] = .planningOnly
            statuses[.generatedArtifacts] = applyPlan == nil ? .planningOnly : .applyBridged
            statuses[.folders] = libraryPlan == nil ? .shadowOnly : .applyBridged
            statuses[.studyItems] = libraryPlan == nil ? .shadowOnly : .applyBridged
            statuses[.tombstones] = applyPlan?.tombstones.isEmpty == false || libraryPlan?.tombstones.isEmpty == false ? .applyBridged : .planningOnly
            statuses[.conflicts] = (applyPlan?.conflicts.isEmpty == false || libraryPlan?.conflicts.isEmpty == false) ? .blocked : .semanticsComplete
            statuses[.apply] = applyPlan == nil ? .planningOnly : .applyBridged
            statuses[.transferState] = transferProjection == nil ? .planningOnly : .semanticsComplete
            statuses[.objectProjection] = .semanticsComplete
            statuses[.inventory] = inventoryCoverage == nil ? .shadowOnly : .semanticsComplete
            statuses[.transport] = .blocked
            statuses[.uploadRuntime] = .blocked
            statuses[.physicalStorage] = .blocked
        }

        if fallbackUsed || (libraryPlan?.fallbackRequiredObjectIDs.isEmpty == false) || (inventoryCoverage?.fallbackRequiredCount ?? 0) > 0 {
            for domain in [CanonicalRetirementDomain.folders, .studyItems, .inventory, .apply] {
                add(domain, .fallbackUsed, "legacyFallbackPreserved", statuses: &statuses, blockers: &blockers)
            }
        }
        if (inventoryCoverage?.unsupportedLegacyObjectCount ?? 0) > 0 {
            add(.inventory, .unsupportedObjectKinds, "unsupported=\(inventoryCoverage?.unsupportedLegacyObjectCount ?? 0)", statuses: &statuses, blockers: &blockers)
        }
        if applyPlan?.conflicts.isEmpty == false || libraryPlan?.conflicts.isEmpty == false {
            add(.conflicts, .conflictsUnresolved, "manualReviewRequired", statuses: &statuses, blockers: &blockers)
        }
        if transferProjection == nil {
            add(.transferState, .transferStateUnmapped, "projectionMissing", statuses: &statuses, blockers: &blockers)
        }
        add(.objectProjection, .uiStillReadsLegacyStatus, "objectProjectionNotUIDriving", statuses: &statuses, blockers: &blockers)
        add(.transport, .routeStillLegacy, "signedHTTPRoutesStillLegacy", statuses: &statuses, blockers: &blockers)
        add(.uploadRuntime, .routeStillLegacy, "RecordingUploadCoordinatorStillRuntime", statuses: &statuses, blockers: &blockers)
        add(.physicalStorage, .physicalStoreStillLegacy, "legacyStoresStillOwnFiles", statuses: &statuses, blockers: &blockers)

        return CanonicalRetirementReadinessReport(
            generatedAt: CanonicalTimestamp(generatedAt),
            statuses: statuses,
            blockers: blockers
        )
    }

    nonisolated private func add(
        _ domain: CanonicalRetirementDomain,
        _ kind: CanonicalRetirementBlockerKind,
        _ detail: String,
        statuses: inout [CanonicalRetirementDomain: CanonicalRetirementStatus],
        blockers: inout [CanonicalRetirementBlocker]
    ) {
        statuses[domain] = .blocked
        blockers.append(CanonicalRetirementBlocker(domain: domain, kind: kind, detail: detail))
    }
}
