//
//  CanonicalDryRunMigrationPlanner.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalLegacyEquivalenceDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingMetadata
    case recordingAudio
    case generatedArtifacts
    case folders
    case studyItems
    case standaloneNotes
    case tombstones
    case conflicts
    case apply
    case fileRuntime
    case transportRuntime
    case uploadRuntime
    case objectProjection
    case uiIntegration

    nonisolated var productionDomain: CanonicalProductionDomain {
        switch self {
        case .recordingMetadata: return .recordingMetadata
        case .recordingAudio: return .recordingAudio
        case .generatedArtifacts: return .generatedArtifacts
        case .folders: return .folders
        case .studyItems: return .studyItems
        case .standaloneNotes: return .standaloneNotes
        case .tombstones: return .tombstones
        case .conflicts: return .conflicts
        case .apply: return .apply
        case .fileRuntime: return .fileRuntime
        case .transportRuntime: return .transportRuntime
        case .uploadRuntime: return .uploadRuntime
        case .objectProjection: return .objectProjection
        case .uiIntegration: return .uiIntegration
        }
    }
}

nonisolated enum CanonicalLegacyEquivalenceStatus: String, Codable, Equatable, Sendable {
    case equivalent
    case canonicalMoreConservative
    case canonicalMoreAggressive
    case legacyOnly
    case canonicalOnly
    case unsupported
    case conflict
    case blocked
    case unknown
}

nonisolated enum CanonicalLegacyDivergenceSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case blocking
}

nonisolated struct CanonicalLegacyDivergence: Codable, Equatable, Identifiable, Sendable {
    var id: String { [domain.rawValue, status.rawValue, severity.rawValue, reason].joined(separator: "|") }

    var domain: CanonicalLegacyEquivalenceDomain
    var status: CanonicalLegacyEquivalenceStatus
    var severity: CanonicalLegacyDivergenceSeverity
    var reason: String
    var canonicalActionIDs: [String]
    var legacyActionIDs: [String]
    var hashPrefix: String?

    nonisolated init(
        domain: CanonicalLegacyEquivalenceDomain,
        status: CanonicalLegacyEquivalenceStatus,
        severity: CanonicalLegacyDivergenceSeverity,
        reason: String,
        canonicalActionIDs: [String] = [],
        legacyActionIDs: [String] = [],
        hash: CanonicalHash? = nil
    ) {
        self.domain = domain
        self.status = status
        self.severity = severity
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? status.rawValue
        self.canonicalActionIDs = Self.normalized(canonicalActionIDs)
        self.legacyActionIDs = Self.normalized(legacyActionIDs)
        self.hashPrefix = hash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
    }

    nonisolated var isBlocking: Bool {
        severity == .blocking
    }

    nonisolated private static func normalized(_ ids: [String]) -> [String] {
        Array(Set(ids.compactMap { CanonicalProductionRedaction.safeDiagnosticText($0) })).sorted()
    }
}

nonisolated struct CanonicalLegacyEquivalenceDomainReport: Codable, Equatable, Identifiable, Sendable {
    var id: String { domain.rawValue }

    var domain: CanonicalLegacyEquivalenceDomain
    var status: CanonicalLegacyEquivalenceStatus
    var canonicalActionIDs: [String]
    var legacyActionIDs: [String]
    var divergences: [CanonicalLegacyDivergence]

    nonisolated init(
        domain: CanonicalLegacyEquivalenceDomain,
        status: CanonicalLegacyEquivalenceStatus,
        canonicalActionIDs: [String] = [],
        legacyActionIDs: [String] = [],
        divergences: [CanonicalLegacyDivergence] = []
    ) {
        self.domain = domain
        self.status = status
        self.canonicalActionIDs = Self.normalized(canonicalActionIDs)
        self.legacyActionIDs = Self.normalized(legacyActionIDs)
        self.divergences = divergences
    }

    nonisolated var isBlocking: Bool {
        divergences.contains(where: \.isBlocking)
            || [.canonicalMoreAggressive, .legacyOnly, .canonicalOnly, .unsupported, .conflict, .blocked, .unknown].contains(status)
    }

    nonisolated private static func normalized(_ ids: [String]) -> [String] {
        Array(Set(ids.compactMap { CanonicalProductionRedaction.safeDiagnosticText($0) })).sorted()
    }
}

nonisolated struct CanonicalLegacyEquivalenceReport: Codable, Equatable, Sendable {
    var generatedAt: CanonicalTimestamp
    var domainReports: [CanonicalLegacyEquivalenceDomainReport]
    var divergences: [CanonicalLegacyDivergence]
    var allEquivalent: Bool
    var hasBlockingDivergence: Bool

    nonisolated init(domainReports: [CanonicalLegacyEquivalenceDomainReport], generatedAt: Date = Date()) {
        self.generatedAt = CanonicalTimestamp(generatedAt)
        self.domainReports = domainReports.sorted { $0.domain.rawValue < $1.domain.rawValue }
        self.divergences = domainReports.flatMap(\.divergences).sorted { $0.id < $1.id }
        self.allEquivalent = domainReports.allSatisfy { $0.status == .equivalent || $0.status == .canonicalMoreConservative }
        self.hasBlockingDivergence = domainReports.contains(where: \.isBlocking)
    }

    nonisolated func status(for domain: CanonicalLegacyEquivalenceDomain) -> CanonicalLegacyEquivalenceStatus {
        domainReports.first { $0.domain == domain }?.status ?? .unknown
    }
}

nonisolated struct CanonicalDryRunEquivalenceReport: Codable, Equatable, Sendable {
    var legacyEquivalence: CanonicalLegacyEquivalenceReport
    var equivalentDomains: [CanonicalLegacyEquivalenceDomain]
    var divergentDomains: [CanonicalLegacyEquivalenceDomain]

    nonisolated init(legacyEquivalence: CanonicalLegacyEquivalenceReport) {
        self.legacyEquivalence = legacyEquivalence
        self.equivalentDomains = legacyEquivalence.domainReports
            .filter { $0.status == .equivalent || $0.status == .canonicalMoreConservative }
            .map(\.domain)
            .sorted { $0.rawValue < $1.rawValue }
        self.divergentDomains = legacyEquivalence.domainReports
            .filter(\.isBlocking)
            .map(\.domain)
            .sorted { $0.rawValue < $1.rawValue }
    }
}

nonisolated enum CanonicalDryRunActionKind: String, Codable, Equatable, Sendable {
    case wouldNoOp
    case wouldUpload
    case wouldDownload
    case wouldApply
    case wouldSend
    case wouldRecordConflict
    case wouldSuppress
}

nonisolated struct CanonicalDryRunAction: Codable, Equatable, Identifiable, Sendable {
    var id: String { actionID }

    var actionID: String
    var domain: CanonicalProductionDomain
    var kind: CanonicalDryRunActionKind
    var objectID: String?
    var artifactID: String?
    var reason: String
    var suppressedBecauseDryRun: Bool

    nonisolated init(
        domain: CanonicalProductionDomain,
        kind: CanonicalDryRunActionKind,
        objectID: String? = nil,
        artifactID: String? = nil,
        reason: String
    ) {
        self.domain = domain
        self.kind = kind
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown") }
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? kind.rawValue
        self.suppressedBecauseDryRun = true
        self.actionID = [
            domain.rawValue,
            kind.rawValue,
            self.objectID ?? "",
            self.artifactID ?? "",
            self.reason
        ].joined(separator: "|")
    }
}

nonisolated enum CanonicalDryRunRiskKind: String, Codable, Equatable, Sendable {
    case dryRunOnly
    case legacyRuntimeStillOwner
    case canonicalMoreAggressive
    case canonicalOnly
    case legacyOnly
    case unresolvedConflict
    case unsupportedObject
}

nonisolated struct CanonicalDryRunRisk: Codable, Equatable, Identifiable, Sendable {
    var id: String { [domain.rawValue, kind.rawValue, reason].joined(separator: "|") }

    var domain: CanonicalProductionDomain
    var kind: CanonicalDryRunRiskKind
    var reason: String

    nonisolated init(domain: CanonicalProductionDomain, kind: CanonicalDryRunRiskKind, reason: String) {
        self.domain = domain
        self.kind = kind
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? kind.rawValue
    }
}

nonisolated enum CanonicalDryRunBlockerKind: String, Codable, Equatable, Hashable, Sendable {
    case missingProductionFilePort
    case missingProductionTransportPort
    case missingProductionUploadPort
    case missingProductionApplyPort
    case dryRunDivergence
    case unresolvedConflict
    case unsupportedObject
    case fullContentLeak
    case routeBypassRisk
    case pathEscapeRisk
    case uiLegacyRuntime
    case retryRuntimeNotMigrated
    case macPendingSyncLegacy
    case userDataMigrationNotDesigned
}

nonisolated struct CanonicalDryRunBlocker: Codable, Equatable, Identifiable, Sendable {
    var id: String { [domain.rawValue, kind.rawValue, reason].joined(separator: "|") }

    var domain: CanonicalProductionDomain
    var kind: CanonicalDryRunBlockerKind
    var reason: String

    nonisolated init(domain: CanonicalProductionDomain, kind: CanonicalDryRunBlockerKind, reason: String) {
        self.domain = domain
        self.kind = kind
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? kind.rawValue
    }
}

nonisolated struct CanonicalDryRunMigrationContext: Codable, Equatable, Sendable {
    var dryRunID: String
    var legacyRuntimeStillProductionOwner: Bool
    var retryRuntimeMigrated: Bool
    var macPendingSyncMigrated: Bool
    var userDataMigrationDesigned: Bool
    var uiIntegrationMigrated: Bool

    nonisolated init(
        dryRunID: String = UUID().uuidString,
        legacyRuntimeStillProductionOwner: Bool = true,
        retryRuntimeMigrated: Bool = false,
        macPendingSyncMigrated: Bool = false,
        userDataMigrationDesigned: Bool = false,
        uiIntegrationMigrated: Bool = false
    ) {
        self.dryRunID = CanonicalProductionRedaction.safeIdentifier(dryRunID, fallback: UUID().uuidString)
        self.legacyRuntimeStillProductionOwner = legacyRuntimeStillProductionOwner
        self.retryRuntimeMigrated = retryRuntimeMigrated
        self.macPendingSyncMigrated = macPendingSyncMigrated
        self.userDataMigrationDesigned = userDataMigrationDesigned
        self.uiIntegrationMigrated = uiIntegrationMigrated
    }
}

nonisolated struct CanonicalDryRunReadinessReport: Codable, Equatable, Sendable {
    var generatedAt: CanonicalTimestamp
    var states: [CanonicalRuntimeReadinessStatus]
    var portReadiness: CanonicalProductionPortReadiness
    var blockers: [CanonicalDryRunBlocker]
    var eligibleForRuntimeSwitch: Bool
    var retired: Bool

    nonisolated init(
        states: [CanonicalRuntimeReadinessStatus],
        portReadiness: CanonicalProductionPortReadiness,
        blockers: [CanonicalDryRunBlocker],
        eligibleForRuntimeSwitch: Bool = false,
        retired: Bool = false,
        generatedAt: Date = Date()
    ) {
        self.generatedAt = CanonicalTimestamp(generatedAt)
        self.states = Array(Set(states)).sorted { $0.rawValue < $1.rawValue }
        self.portReadiness = portReadiness
        self.blockers = blockers.sorted { $0.id < $1.id }
        self.eligibleForRuntimeSwitch = eligibleForRuntimeSwitch
        self.retired = retired
    }

    nonisolated var productionMigrationBlocked: Bool {
        states.contains(.productionBlocked) || !blockers.isEmpty || !eligibleForRuntimeSwitch
    }
}

typealias CanonicalProductionMigrationGateReport = CanonicalDryRunReadinessReport

nonisolated struct CanonicalDryRunMigrationPlan: Codable, Equatable, Sendable {
    var dryRunID: String
    var trigger: CanonicalSyncPlanTrigger
    var syncPlan: CanonicalSyncPlan
    var applyPlan: CanonicalApplyPlan
    var libraryPlan: CanonicalLibrarySyncPlan
    var actions: [CanonicalDryRunAction]
    var risks: [CanonicalDryRunRisk]
    var blockers: [CanonicalDryRunBlocker]
    var equivalenceReport: CanonicalDryRunEquivalenceReport
    var readinessReport: CanonicalDryRunReadinessReport
    var diagnostics: [CanonicalProductionDiagnosticsEvent]
}

nonisolated struct CanonicalDryRunMigrationPlanner {
    nonisolated init() {}

    nonisolated func plan(
        local: CanonicalProductionSnapshot,
        peer: CanonicalProductionSnapshot,
        ports: CanonicalProductionPortSet,
        currentRuntimeReadiness: CanonicalRuntimeReadinessReport,
        trigger: CanonicalSyncPlanTrigger,
        context: CanonicalDryRunMigrationContext = CanonicalDryRunMigrationContext(),
        generatedAt: Date = Date()
    ) throws -> CanonicalDryRunMigrationPlan {
        let resolvedTrigger = ports.syncClock?.triggerContext(defaultTrigger: trigger) ?? trigger
        let syncPlan = try CanonicalSyncPlanner().plan(
            local: local.manifest,
            peer: peer.manifest,
            trigger: resolvedTrigger
        )
        let applyPlan = CanonicalApplyPlanner().plan(
            local: local.manifest,
            peer: peer.manifest,
            syncPlan: syncPlan,
            trigger: resolvedTrigger
        )
        let libraryPlan = CanonicalLibrarySyncPlanner().plan(
            local: local.manifest,
            peer: peer.manifest,
            trigger: resolvedTrigger
        )
        let actions = Self.actions(syncPlan: syncPlan, applyPlan: applyPlan, libraryPlan: libraryPlan)
        let portReadiness = ports.readiness(generatedAt: generatedAt)
        let equivalence = Self.equivalenceReport(
            syncPlan: syncPlan,
            applyPlan: applyPlan,
            libraryPlan: libraryPlan,
            localLegacyActions: local.legacyActions,
            portReadiness: portReadiness,
            generatedAt: generatedAt
        )
        let dryRunEquivalence = CanonicalDryRunEquivalenceReport(legacyEquivalence: equivalence)
        let blockers = Self.blockers(
            portReadiness: portReadiness,
            equivalence: equivalence,
            local: local,
            peer: peer,
            applyPlan: applyPlan,
            libraryPlan: libraryPlan,
            context: context
        )
        let risks = Self.risks(equivalence: equivalence, blockers: blockers)
        let readiness = Self.readiness(
            runtimeReadiness: currentRuntimeReadiness,
            portReadiness: portReadiness,
            equivalence: equivalence,
            blockers: blockers,
            generatedAt: generatedAt
        )
        let diagnostics = Self.diagnostics(
            dryRunID: context.dryRunID,
            equivalence: equivalence,
            readiness: readiness,
            blockers: blockers,
            generatedAt: generatedAt
        )

        return CanonicalDryRunMigrationPlan(
            dryRunID: context.dryRunID,
            trigger: resolvedTrigger,
            syncPlan: syncPlan,
            applyPlan: applyPlan,
            libraryPlan: libraryPlan,
            actions: actions,
            risks: risks,
            blockers: blockers,
            equivalenceReport: dryRunEquivalence,
            readinessReport: readiness,
            diagnostics: diagnostics
        )
    }

    nonisolated static func equivalenceReport(
        syncPlan: CanonicalSyncPlan,
        applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan,
        localLegacyActions: CanonicalLegacyActionSnapshot,
        portReadiness: CanonicalProductionPortReadiness,
        generatedAt: Date = Date()
    ) -> CanonicalLegacyEquivalenceReport {
        let canonical = canonicalActionIDs(syncPlan: syncPlan, applyPlan: applyPlan, libraryPlan: libraryPlan)
        let conflictDomains: Set<CanonicalLegacyEquivalenceDomain> = [
            syncPlan.conflictRecordingMetadata.isEmpty ? nil : .recordingMetadata,
            syncPlan.conflictAudioArtifact.isEmpty ? nil : .recordingAudio,
            syncPlan.conflictGeneratedArtifact.isEmpty ? nil : .generatedArtifacts,
            applyPlan.conflicts.isEmpty && libraryPlan.conflicts.isEmpty ? nil : .conflicts
        ].compactMap { $0 }.reduce(into: Set<CanonicalLegacyEquivalenceDomain>()) { $0.insert($1) }

        let reports = CanonicalLegacyEquivalenceDomain.allCases.map { domain in
            domainReport(
                domain: domain,
                canonicalActionIDs: canonical[domain] ?? [],
                legacyActionIDs: localLegacyActions.actionIDs(for: domain.productionDomain),
                conflictDomains: conflictDomains,
                portReadiness: portReadiness
            )
        }
        return CanonicalLegacyEquivalenceReport(domainReports: reports, generatedAt: generatedAt)
    }

    nonisolated private static func domainReport(
        domain: CanonicalLegacyEquivalenceDomain,
        canonicalActionIDs: [String],
        legacyActionIDs: [String],
        conflictDomains: Set<CanonicalLegacyEquivalenceDomain>,
        portReadiness: CanonicalProductionPortReadiness
    ) -> CanonicalLegacyEquivalenceDomainReport {
        let canonicalSet = Set(canonicalActionIDs)
        let legacySet = Set(legacyActionIDs)
        if let missingPort = missingPortBlocking(domain: domain, portReadiness: portReadiness) {
            let divergence = CanonicalLegacyDivergence(
                domain: domain,
                status: .blocked,
                severity: .blocking,
                reason: "productionPortMissing:\(missingPort.rawValue)",
                canonicalActionIDs: canonicalActionIDs,
                legacyActionIDs: legacyActionIDs
            )
            return CanonicalLegacyEquivalenceDomainReport(
                domain: domain,
                status: .blocked,
                canonicalActionIDs: canonicalActionIDs,
                legacyActionIDs: legacyActionIDs,
                divergences: [divergence]
            )
        }
        if conflictDomains.contains(domain) {
            let divergence = CanonicalLegacyDivergence(
                domain: domain,
                status: .conflict,
                severity: .blocking,
                reason: "canonicalConflictRequiresManualReview",
                canonicalActionIDs: canonicalActionIDs,
                legacyActionIDs: legacyActionIDs
            )
            return CanonicalLegacyEquivalenceDomainReport(
                domain: domain,
                status: .conflict,
                canonicalActionIDs: canonicalActionIDs,
                legacyActionIDs: legacyActionIDs,
                divergences: [divergence]
            )
        }
        if canonicalSet == legacySet {
            return CanonicalLegacyEquivalenceDomainReport(
                domain: domain,
                status: .equivalent,
                canonicalActionIDs: canonicalActionIDs,
                legacyActionIDs: legacyActionIDs
            )
        }
        if canonicalSet.isEmpty && !legacySet.isEmpty {
            if domain == .recordingMetadata && legacyActionIDs.allSatisfy(isSafeMetadataChurnSuppression) {
                let divergence = CanonicalLegacyDivergence(
                    domain: domain,
                    status: .canonicalMoreConservative,
                    severity: .info,
                    reason: "legacyMetadataChurnSuppressed",
                    canonicalActionIDs: canonicalActionIDs,
                    legacyActionIDs: legacyActionIDs
                )
                return CanonicalLegacyEquivalenceDomainReport(
                    domain: domain,
                    status: .canonicalMoreConservative,
                    canonicalActionIDs: canonicalActionIDs,
                    legacyActionIDs: legacyActionIDs,
                    divergences: [divergence]
                )
            }
            let divergence = CanonicalLegacyDivergence(
                domain: domain,
                status: .legacyOnly,
                severity: .blocking,
                reason: "legacyWouldActButCanonicalNoOp",
                canonicalActionIDs: canonicalActionIDs,
                legacyActionIDs: legacyActionIDs
            )
            return CanonicalLegacyEquivalenceDomainReport(
                domain: domain,
                status: .legacyOnly,
                canonicalActionIDs: canonicalActionIDs,
                legacyActionIDs: legacyActionIDs,
                divergences: [divergence]
            )
        }
        if !canonicalSet.isEmpty && legacySet.isEmpty {
            let status: CanonicalLegacyEquivalenceStatus = domain == .recordingAudio || domain == .uploadRuntime
                ? .canonicalMoreAggressive
                : .canonicalOnly
            let divergence = CanonicalLegacyDivergence(
                domain: domain,
                status: status,
                severity: .blocking,
                reason: status == .canonicalMoreAggressive ? "canonicalWouldUploadWhereLegacyNoOp" : "canonicalOnlyAction",
                canonicalActionIDs: canonicalActionIDs,
                legacyActionIDs: legacyActionIDs
            )
            return CanonicalLegacyEquivalenceDomainReport(
                domain: domain,
                status: status,
                canonicalActionIDs: canonicalActionIDs,
                legacyActionIDs: legacyActionIDs,
                divergences: [divergence]
            )
        }
        let divergence = CanonicalLegacyDivergence(
            domain: domain,
            status: .unknown,
            severity: .blocking,
            reason: "canonicalLegacyActionSetMismatch",
            canonicalActionIDs: canonicalActionIDs,
            legacyActionIDs: legacyActionIDs
        )
        return CanonicalLegacyEquivalenceDomainReport(
            domain: domain,
            status: .unknown,
            canonicalActionIDs: canonicalActionIDs,
            legacyActionIDs: legacyActionIDs,
            divergences: [divergence]
        )
    }

    nonisolated private static func missingPortBlocking(
        domain: CanonicalLegacyEquivalenceDomain,
        portReadiness: CanonicalProductionPortReadiness
    ) -> CanonicalProductionPortKind? {
        let required: CanonicalProductionPortKind?
        switch domain {
        case .recordingMetadata, .generatedArtifacts, .folders, .studyItems, .standaloneNotes, .tombstones, .fileRuntime:
            required = .file
        case .recordingAudio, .uploadRuntime:
            required = .upload
        case .transportRuntime:
            required = .transport
        case .apply, .conflicts:
            required = .apply
        case .objectProjection, .uiIntegration:
            required = nil
        }
        guard let required, portReadiness.missingPorts.contains(required) else {
            return nil
        }
        return required
    }

    nonisolated private static func isSafeMetadataChurnSuppression(_ actionID: String) -> Bool {
        let lowercased = actionID.lowercased()
        return lowercased.contains("metadatachurn")
            || lowercased.contains("legacywoulduploadmetadatabutcanonicalnoop")
            || lowercased.contains("canonicalmetadatahashconverged")
    }

    nonisolated private static func canonicalActionIDs(
        syncPlan: CanonicalSyncPlan,
        applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan
    ) -> [CanonicalLegacyEquivalenceDomain: [String]] {
        var result: [CanonicalLegacyEquivalenceDomain: [String]] = [:]
        append(syncPlan.uploadRecordingMetadata.map { "recordingMetadataSend:\($0.objectID)" }, domain: .recordingMetadata, result: &result)
        append(syncPlan.downloadRecordingMetadata.map { "recordingMetadataApply:\($0.objectID)" }, domain: .recordingMetadata, result: &result)
        append(syncPlan.uploadAudioArtifact.map { "recordingAudioUpload:\($0.objectID):\($0.artifactID ?? "audio")" }, domain: .recordingAudio, result: &result)
        append(syncPlan.downloadGeneratedArtifact.map { "generatedArtifactDownload:\($0.objectID):\($0.artifactID ?? $0.kind?.rawValue ?? "artifact")" }, domain: .generatedArtifacts, result: &result)
        append(libraryPlan.actions.compactMap { action in
            switch action.objectKind {
            case .folder:
                return "folder:\(action.kind.rawValue):\(action.objectID.rawValue)"
            default:
                return nil
            }
        }, domain: .folders, result: &result)
        append(libraryPlan.actions.compactMap { action in
            switch action.objectKind {
            case .standaloneStudyItem, .recordingAssociatedStudyItem:
                return "studyItem:\(action.kind.rawValue):\(action.objectID.rawValue)"
            default:
                return nil
            }
        }, domain: .studyItems, result: &result)
        append(libraryPlan.actions.compactMap { action in
            action.objectKind == .standaloneNote ? "standaloneNote:\(action.kind.rawValue):\(action.objectID.rawValue)" : nil
        }, domain: .standaloneNotes, result: &result)
        append((applyPlan.tombstones.map { "tombstone:\($0.target.objectID)" } + libraryPlan.tombstones.map { "libraryTombstone:\($0.objectID.rawValue)" }), domain: .tombstones, result: &result)
        append((applyPlan.conflicts.map(\.conflictID) + libraryPlan.conflicts.map(\.conflictID)), domain: .conflicts, result: &result)
        append((applyPlan.actions.map(\.actionID) + libraryPlan.applyActions.map(\.actionID)), domain: .apply, result: &result)
        if !syncPlan.uploadAudioArtifact.isEmpty {
            append(syncPlan.uploadAudioArtifact.map { "uploadRuntime:\($0.objectID)" }, domain: .uploadRuntime, result: &result)
        }
        return Dictionary(uniqueKeysWithValues: result.map { domain, ids in
            (domain, Array(Set(ids)).sorted())
        })
    }

    nonisolated private static func append(
        _ ids: [String],
        domain: CanonicalLegacyEquivalenceDomain,
        result: inout [CanonicalLegacyEquivalenceDomain: [String]]
    ) {
        guard !ids.isEmpty else {
            return
        }
        result[domain, default: []].append(contentsOf: ids)
    }

    nonisolated private static func actions(
        syncPlan: CanonicalSyncPlan,
        applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan
    ) -> [CanonicalDryRunAction] {
        var actions: [CanonicalDryRunAction] = []
        actions += syncPlan.uploadRecordingMetadata.map {
            CanonicalDryRunAction(domain: .recordingMetadata, kind: .wouldSend, objectID: $0.objectID, reason: $0.reason.rawValue)
        }
        actions += syncPlan.downloadRecordingMetadata.map {
            CanonicalDryRunAction(domain: .recordingMetadata, kind: .wouldApply, objectID: $0.objectID, reason: $0.reason.rawValue)
        }
        actions += syncPlan.uploadAudioArtifact.map {
            CanonicalDryRunAction(domain: .recordingAudio, kind: .wouldUpload, objectID: $0.objectID, artifactID: $0.artifactID, reason: $0.reason.rawValue)
        }
        actions += syncPlan.downloadGeneratedArtifact.map {
            CanonicalDryRunAction(domain: .generatedArtifacts, kind: .wouldDownload, objectID: $0.objectID, artifactID: $0.artifactID, reason: $0.reason.rawValue)
        }
        actions += applyPlan.actions.map {
            CanonicalDryRunAction(domain: .apply, kind: $0.kind == .conflictRecord ? .wouldRecordConflict : .wouldApply, objectID: $0.target.objectID, artifactID: $0.target.artifactID, reason: $0.reason)
        }
        actions += libraryPlan.applyActions.map {
            CanonicalDryRunAction(domain: .apply, kind: $0.kind == .conflictRecord ? .wouldRecordConflict : .wouldApply, objectID: $0.target.objectID, artifactID: $0.target.artifactID, reason: $0.reason)
        }
        actions += libraryPlan.actions.map {
            let domain: CanonicalProductionDomain
            switch $0.objectKind {
            case .folder:
                domain = .folders
            case .standaloneNote:
                domain = .standaloneNotes
            default:
                domain = .studyItems
            }
            return CanonicalDryRunAction(domain: domain, kind: .wouldApply, objectID: $0.objectID.rawValue, reason: $0.reason)
        }
        return actions.sorted { $0.actionID < $1.actionID }
    }

    nonisolated private static func blockers(
        portReadiness: CanonicalProductionPortReadiness,
        equivalence: CanonicalLegacyEquivalenceReport,
        local: CanonicalProductionSnapshot,
        peer: CanonicalProductionSnapshot,
        applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan,
        context: CanonicalDryRunMigrationContext
    ) -> [CanonicalDryRunBlocker] {
        var blockers: [CanonicalDryRunBlocker] = []
        if portReadiness.missingPorts.contains(.file) {
            blockers.append(CanonicalDryRunBlocker(domain: .fileRuntime, kind: .missingProductionFilePort, reason: "filePortMissing"))
        }
        if portReadiness.missingPorts.contains(.transport) {
            blockers.append(CanonicalDryRunBlocker(domain: .transportRuntime, kind: .missingProductionTransportPort, reason: "transportPortMissing"))
        }
        if portReadiness.missingPorts.contains(.upload) {
            blockers.append(CanonicalDryRunBlocker(domain: .uploadRuntime, kind: .missingProductionUploadPort, reason: "uploadPortMissing"))
        }
        if portReadiness.missingPorts.contains(.apply) {
            blockers.append(CanonicalDryRunBlocker(domain: .apply, kind: .missingProductionApplyPort, reason: "applyPortMissing"))
        }
        blockers += equivalence.divergences.filter(\.isBlocking).map {
            CanonicalDryRunBlocker(domain: $0.domain.productionDomain, kind: .dryRunDivergence, reason: $0.reason)
        }
        if applyPlan.conflicts.isEmpty == false || libraryPlan.conflicts.isEmpty == false {
            blockers.append(CanonicalDryRunBlocker(domain: .conflicts, kind: .unresolvedConflict, reason: "manualReviewRequired"))
        }
        for fact in (local.unsupportedFacts + peer.unsupportedFacts) {
            blockers.append(CanonicalDryRunBlocker(domain: fact.domain, kind: .unsupportedObject, reason: fact.reason))
        }
        if !context.uiIntegrationMigrated {
            blockers.append(CanonicalDryRunBlocker(domain: .uiIntegration, kind: .uiLegacyRuntime, reason: "legacyUIStillRuntimeOwner"))
        }
        if !context.retryRuntimeMigrated {
            blockers.append(CanonicalDryRunBlocker(domain: .uploadRuntime, kind: .retryRuntimeNotMigrated, reason: "legacyRetryRuntimePreserved"))
        }
        if !context.macPendingSyncMigrated {
            blockers.append(CanonicalDryRunBlocker(domain: .transportRuntime, kind: .macPendingSyncLegacy, reason: "macPendingSyncStillLegacy"))
        }
        if !context.userDataMigrationDesigned {
            blockers.append(CanonicalDryRunBlocker(domain: .inventory, kind: .userDataMigrationNotDesigned, reason: "noUserDataMigrationDesign"))
        }
        return Array(Dictionary(grouping: blockers, by: \.id).compactMap { $0.value.first }).sorted { $0.id < $1.id }
    }

    nonisolated private static func risks(
        equivalence: CanonicalLegacyEquivalenceReport,
        blockers: [CanonicalDryRunBlocker]
    ) -> [CanonicalDryRunRisk] {
        var risks = [CanonicalDryRunRisk(domain: .apply, kind: .dryRunOnly, reason: "productionMutationSuppressed")]
        risks += equivalence.divergences.map { divergence in
            let kind: CanonicalDryRunRiskKind
            switch divergence.status {
            case .canonicalMoreAggressive:
                kind = .canonicalMoreAggressive
            case .canonicalOnly:
                kind = .canonicalOnly
            case .legacyOnly:
                kind = .legacyOnly
            case .conflict:
                kind = .unresolvedConflict
            case .unsupported:
                kind = .unsupportedObject
            default:
                kind = .legacyRuntimeStillOwner
            }
            return CanonicalDryRunRisk(domain: divergence.domain.productionDomain, kind: kind, reason: divergence.reason)
        }
        risks += blockers.map { CanonicalDryRunRisk(domain: $0.domain, kind: .legacyRuntimeStillOwner, reason: $0.reason) }
        return Array(Dictionary(grouping: risks, by: \.id).compactMap { $0.value.first }).sorted { $0.id < $1.id }
    }

    nonisolated private static func readiness(
        runtimeReadiness: CanonicalRuntimeReadinessReport,
        portReadiness: CanonicalProductionPortReadiness,
        equivalence: CanonicalLegacyEquivalenceReport,
        blockers: [CanonicalDryRunBlocker],
        generatedAt: Date
    ) -> CanonicalDryRunReadinessReport {
        var states: [CanonicalRuntimeReadinessStatus] = [.notEvaluated]
        let offlineDomains: [CanonicalRuntimeReadinessDomain] = [
            .fileRuntime,
            .transportRuntime,
            .uploadRuntime,
            .applyExecutor,
            .conflictResolver,
            .simulationHarness
        ]
        if offlineDomains.allSatisfy({ runtimeReadiness.status(for: $0) == .offlineRuntimeComplete }) {
            states.append(.offlineKernelReady)
        }
        if portReadiness.missingPorts.isEmpty {
            states.append(.productionPortsDeclared)
            states.append(.dryRunAvailable)
        } else {
            states.append(.productionAdapterMissing)
        }
        if !equivalence.hasBlockingDivergence {
            states.append(.dryRunEquivalent)
        }
        states.append(.productionBlocked)
        if portReadiness.hasAllRequiredDryRunPorts && !equivalence.hasBlockingDivergence {
            states.append(.eligibleForManualMigrationDesign)
        }
        return CanonicalDryRunReadinessReport(
            states: states,
            portReadiness: portReadiness,
            blockers: blockers,
            eligibleForRuntimeSwitch: false,
            retired: false,
            generatedAt: generatedAt
        )
    }

    nonisolated private static func diagnostics(
        dryRunID: String,
        equivalence: CanonicalLegacyEquivalenceReport,
        readiness: CanonicalDryRunReadinessReport,
        blockers: [CanonicalDryRunBlocker],
        generatedAt: Date
    ) -> [CanonicalProductionDiagnosticsEvent] {
        var events: [CanonicalProductionDiagnosticsEvent] = [
            CanonicalProductionDiagnosticsEvent(kind: .canonicalDryRunStarted, action: dryRunID, reason: "dryRunMigrationPlanner", generatedAt: generatedAt),
            CanonicalProductionDiagnosticsEvent(kind: .canonicalProductionPortsDeclared, reason: "declared=\(readiness.portReadiness.declaredPorts.filter { $0.value }.map { $0.key.rawValue }.sorted().joined(separator: ","))", generatedAt: generatedAt)
        ]
        for missing in readiness.portReadiness.missingPorts {
            events.append(
                CanonicalProductionDiagnosticsEvent(
                    kind: .canonicalPortMissing,
                    domain: domain(forMissingPort: missing),
                    blocker: missing.rawValue,
                    reason: "portMissing",
                    generatedAt: generatedAt
                )
            )
        }
        for report in equivalence.domainReports {
            events.append(
                CanonicalProductionDiagnosticsEvent(
                    kind: report.isBlocking ? .canonicalLegacyDivergent : .canonicalLegacyEquivalent,
                    domain: report.domain.productionDomain,
                    action: report.status.rawValue,
                    reason: report.divergences.first?.reason ?? "equivalent",
                    generatedAt: generatedAt
                )
            )
        }
        for blocker in blockers {
            events.append(
                CanonicalProductionDiagnosticsEvent(
                    kind: .canonicalDryRunBlocked,
                    domain: blocker.domain,
                    blocker: blocker.kind.rawValue,
                    reason: blocker.reason,
                    generatedAt: generatedAt
                )
            )
        }
        if equivalence.hasBlockingDivergence {
            events.append(CanonicalProductionDiagnosticsEvent(kind: .canonicalDryRunDivergenceDetected, reason: "blockingDivergence", generatedAt: generatedAt))
        }
        if readiness.productionMigrationBlocked {
            events.append(CanonicalProductionDiagnosticsEvent(kind: .canonicalProductionMigrationBlocked, reason: "runtimeSwitchFalse", generatedAt: generatedAt))
        }
        if readiness.states.contains(.eligibleForManualMigrationDesign) {
            events.append(CanonicalProductionDiagnosticsEvent(kind: .canonicalEligibleForManualMigrationDesign, reason: "manualDesignOnly", generatedAt: generatedAt))
        }
        events.append(CanonicalProductionDiagnosticsEvent(kind: .canonicalDryRunCompleted, reason: "dryRunOnly", generatedAt: generatedAt))
        return events
    }

    nonisolated private static func domain(forMissingPort port: CanonicalProductionPortKind) -> CanonicalProductionDomain {
        switch port {
        case .file:
            return .fileRuntime
        case .transport:
            return .transportRuntime
        case .upload:
            return .uploadRuntime
        case .apply:
            return .apply
        case .syncClock, .diagnostics, .capability:
            return .inventory
        }
    }
}
