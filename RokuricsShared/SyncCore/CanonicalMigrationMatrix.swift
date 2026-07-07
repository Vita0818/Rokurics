//
//  CanonicalMigrationMatrix.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated enum CanonicalMigrationDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingMetadata
    case generatedArtifacts
    case libraryMetadata
    case tombstoneConflict
    case audioUpload
    case uiProjection
    case legacyRetirement
}

nonisolated enum CanonicalMigrationStageStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case notStarted
    case evidenceMissing
    case complete
    case activePilot
    case nextPilotCandidate
    case staticOnly
    case blocked
    case writeSideCanaryObserved
    case readSideObserved
    case observationComplete
    case retirementCandidateReady
    case retirementBlocked

    nonisolated var isReached: Bool {
        switch self {
        case .complete, .activePilot, .nextPilotCandidate, .writeSideCanaryObserved, .readSideObserved, .observationComplete, .retirementCandidateReady:
            return true
        case .notStarted, .evidenceMissing, .staticOnly, .blocked, .retirementBlocked:
            return false
        }
    }
}

nonisolated enum CanonicalMigrationDomainBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingExplicitPilot
    case multipleActivePilots
    case nonLibraryMetadataActivePilot
    case nonPilotDomainNotStaticOnly
    case stageSkipped
    case canaryWithoutPreviousStageEvidence
    case readSideCutoverWithoutWriteSideCutover
    case retiredWithoutReadSideCutover
    case retiredWithoutObservation
    case retiredWithoutFallbackReadiness
    case audioUploadBlockedUntilLibraryMetadataPilotComplete
    case generatedArtifactsNextPilotBeforeLibraryMetadataObservation
    case generatedArtifactsActivePilotDeniedV821
    case generatedArtifactsActivePilotBeforeNextPilotCandidate
    case generatedArtifactsActivePilotBeforeLibraryMetadataObservation
    case generatedArtifactsStagedCanaryBeforeN1
    case tombstoneConflictNextPilotBeforeGeneratedArtifactsObservation
    case audioUploadActivePilotDeniedV821
    case tombstoneConflictActivePilotDeniedV821
    case tombstoneConflictActivePilotDeniedV826
    case tombstoneConflictActivePilotBeforeNextPilotCandidate
    case tombstoneConflictActivePilotBeforeGeneratedArtifactsObservation
    case legacyRetirementEnabledDeniedV821
    case releaseDefaultCutoverEnabled
    case runtimeSwitchEnabled
    case legacyRetirementBeforeReadSideCutover
    case diagnosticsNotRedacted
    case missingMachineParts
    case missingAppSeam
    case cutoverNotDefaultOff
    case productionInjectionPresent
    case readPathNotLegacy
    case testsMissing
}

nonisolated struct CanonicalMigrationDomainPolicy: Codable, Equatable, Sendable {
    var domain: CanonicalMigrationDomain
    var stageStatuses: [CanonicalMigrationStage: CanonicalMigrationStageStatus]
    var activePilot: Bool
    var activePilotExplicit: Bool
    var staticOnly: Bool
    var blockedForRealMigration: Bool
    var defaultCutoverEnabled: Bool
    var releaseDefaultEnabledCutover: Bool
    var runtimeSwitchEnabled: Bool
    var legacySuppressionAllowed: Bool
    var noProductionInjection: Bool
    var readPathLegacy: Bool
    var writeSideCutoverSucceeded: Bool
    var observationComplete: Bool
    var fallbackReady: Bool

    nonisolated init(
        domain: CanonicalMigrationDomain,
        stageStatuses: [CanonicalMigrationStage: CanonicalMigrationStageStatus] = [:],
        activePilot: Bool = false,
        activePilotExplicit: Bool = false,
        staticOnly: Bool = true,
        blockedForRealMigration: Bool = true,
        defaultCutoverEnabled: Bool = false,
        releaseDefaultEnabledCutover: Bool = false,
        runtimeSwitchEnabled: Bool = false,
        legacySuppressionAllowed: Bool = false,
        noProductionInjection: Bool = true,
        readPathLegacy: Bool = true,
        writeSideCutoverSucceeded: Bool = false,
        observationComplete: Bool = false,
        fallbackReady: Bool = true
    ) {
        self.domain = domain
        self.stageStatuses = stageStatuses
        self.activePilot = activePilot
        self.activePilotExplicit = activePilotExplicit
        self.staticOnly = staticOnly
        self.blockedForRealMigration = blockedForRealMigration
        self.defaultCutoverEnabled = defaultCutoverEnabled
        self.releaseDefaultEnabledCutover = releaseDefaultEnabledCutover
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.legacySuppressionAllowed = legacySuppressionAllowed
        self.noProductionInjection = noProductionInjection
        self.readPathLegacy = readPathLegacy
        self.writeSideCutoverSucceeded = writeSideCutoverSucceeded
        self.observationComplete = observationComplete
        self.fallbackReady = fallbackReady
    }

    nonisolated func status(for stage: CanonicalMigrationStage) -> CanonicalMigrationStageStatus {
        if stage == .notStarted {
            return .complete
        }
        return stageStatuses[stage] ?? .notStarted
    }

    nonisolated func hasReached(_ stage: CanonicalMigrationStage) -> Bool {
        status(for: stage).isReached
    }

    nonisolated var hasActiveCanaryOrCutover: Bool {
        activePilot
            || hasReached(.canaryN1)
            || hasReached(.expandedCanary)
            || hasReached(.domainCutover)
            || hasReached(.readSideCutover)
    }

    nonisolated var diagnosticsSummary: String {
        [
            "domain=\(domain.rawValue)",
            "activePilot=\(activePilot)",
            "explicit=\(activePilotExplicit)",
            "staticOnly=\(staticOnly)",
            "blockedForRealMigration=\(blockedForRealMigration)",
            "defaultCutoverEnabled=\(defaultCutoverEnabled)",
            "runtimeSwitchEnabled=\(runtimeSwitchEnabled)",
            "readPathLegacy=\(readPathLegacy)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalMigrationMatrixReport: Codable, Equatable, Sendable {
    var policies: [CanonicalMigrationDomainPolicy]
    var activePilotDomain: CanonicalMigrationDomain?
    var blockers: [CanonicalMigrationDomainBlocker]
    var diagnosticsSummary: String
    var diagnosticsRedacted: Bool

    nonisolated var allowed: Bool {
        blockers.isEmpty
    }
}

nonisolated struct CanonicalMigrationDomainMatrix: Codable, Equatable, Sendable {
    var policies: [CanonicalMigrationDomainPolicy]
    var libraryMetadataPilotComplete: Bool
    var libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool
    var generatedArtifactsTemplateCompleteOrObservationReady: Bool

    nonisolated init(
        policies: [CanonicalMigrationDomainPolicy],
        libraryMetadataPilotComplete: Bool = false,
        libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool = false,
        generatedArtifactsTemplateCompleteOrObservationReady: Bool = false
    ) {
        self.policies = policies.sorted { $0.domain.rawValue < $1.domain.rawValue }
        self.libraryMetadataPilotComplete = libraryMetadataPilotComplete
        self.libraryMetadataObservationCompleteOrRetirementCandidateReady = libraryMetadataObservationCompleteOrRetirementCandidateReady
        self.generatedArtifactsTemplateCompleteOrObservationReady = generatedArtifactsTemplateCompleteOrObservationReady
    }

    nonisolated static let orderedStages: [CanonicalMigrationStage] = [
        .notStarted,
        .projected,
        .planned,
        .noCommit,
        .realApplyPort,
        .commitExecutor,
        .appSeamDefaultOff,
        .nextPilotCandidate,
        .canaryN0,
        .canaryN1,
        .expandedCanary,
        .domainCutover,
        .readSideParallel,
        .readSideCutover,
        .retirementCandidate,
        .retired
    ]

    nonisolated static func defaultV813() -> CanonicalMigrationDomainMatrix {
        CanonicalMigrationDomainMatrix(
            policies: [
                CanonicalMigrationDomainPolicy.v813RecordingMetadata(),
                CanonicalMigrationDomainPolicy.v813GeneratedArtifacts(),
                CanonicalMigrationDomainPolicy.v813LibraryMetadataPilot(),
                CanonicalMigrationDomainPolicy.v813TombstoneConflict(),
                CanonicalMigrationDomainPolicy.v813AudioUpload(),
                CanonicalMigrationDomainPolicy.v813UIProjection(),
                CanonicalMigrationDomainPolicy.v813LegacyRetirement()
            ],
            libraryMetadataPilotComplete: false
        )
    }

    nonisolated static func v821GeneratedArtifactsNextPilotCandidate(
        libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool,
        templateReport: CanonicalGeneratedArtifactTemplateReport = .currentV821Audit()
    ) -> CanonicalMigrationDomainMatrix {
        let base = defaultV813()
        let policies = base.policies.map { policy -> CanonicalMigrationDomainPolicy in
            guard policy.domain == .generatedArtifacts else {
                return policy
            }
            return .v821GeneratedArtifactsNextPilotCandidate(templateReport: templateReport)
        }
        return CanonicalMigrationDomainMatrix(
            policies: policies,
            libraryMetadataPilotComplete: base.libraryMetadataPilotComplete,
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            generatedArtifactsTemplateCompleteOrObservationReady: templateReport.readyForNextPilotN0
        )
    }

    nonisolated static func v822GeneratedArtifactsActivePilot(
        libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool,
        templateReport: CanonicalGeneratedArtifactTemplateReport = .currentV821Audit()
    ) -> CanonicalMigrationDomainMatrix {
        let base = v821GeneratedArtifactsNextPilotCandidate(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            templateReport: templateReport
        )
        let policies = base.policies.map { policy -> CanonicalMigrationDomainPolicy in
            switch policy.domain {
            case .generatedArtifacts:
                return .v822GeneratedArtifactsActivePilot(templateReport: templateReport)
            case .libraryMetadata:
                var completed = policy
                completed.activePilot = false
                completed.activePilotExplicit = false
                completed.staticOnly = true
                completed.blockedForRealMigration = true
                completed.observationComplete = libraryMetadataObservationCompleteOrRetirementCandidateReady
                completed.legacySuppressionAllowed = false
                completed.defaultCutoverEnabled = false
                completed.releaseDefaultEnabledCutover = false
                completed.runtimeSwitchEnabled = false
                completed.readPathLegacy = true
                completed.noProductionInjection = true
                return completed
            default:
                var staticPolicy = policy
                staticPolicy.activePilot = false
                staticPolicy.activePilotExplicit = false
                staticPolicy.staticOnly = true
                staticPolicy.blockedForRealMigration = true
                staticPolicy.legacySuppressionAllowed = false
                staticPolicy.defaultCutoverEnabled = false
                staticPolicy.releaseDefaultEnabledCutover = false
                staticPolicy.runtimeSwitchEnabled = false
                staticPolicy.readPathLegacy = true
                staticPolicy.noProductionInjection = true
                return staticPolicy
            }
        }
        return CanonicalMigrationDomainMatrix(
            policies: policies,
            libraryMetadataPilotComplete: false,
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            generatedArtifactsTemplateCompleteOrObservationReady: templateReport.readyForNextPilotN0
        )
    }

    nonisolated static func v824GeneratedArtifactsStagedCanary(
        libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool,
        templateReport: CanonicalGeneratedArtifactTemplateReport = .currentV821Audit()
    ) -> CanonicalMigrationDomainMatrix {
        let base = v822GeneratedArtifactsActivePilot(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            templateReport: templateReport
        )
        let policies = base.policies.map { policy -> CanonicalMigrationDomainPolicy in
            guard policy.domain == .generatedArtifacts else {
                return policy
            }
            return .v824GeneratedArtifactsStagedCanary(templateReport: templateReport)
        }
        return CanonicalMigrationDomainMatrix(
            policies: policies,
            libraryMetadataPilotComplete: false,
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            generatedArtifactsTemplateCompleteOrObservationReady: templateReport.readyForNextPilotN0
        )
    }

    nonisolated static func v826TombstoneConflictNextPilotCandidate(
        libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool,
        generatedArtifactsTemplateCompleteOrObservationReady: Bool,
        templateReport: CanonicalTombstoneConflictTemplateReport = .currentV826Audit()
    ) -> CanonicalMigrationDomainMatrix {
        let base: CanonicalMigrationDomainMatrix = generatedArtifactsTemplateCompleteOrObservationReady
            ? .v824GeneratedArtifactsStagedCanary(
                libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady
            )
            : .v821GeneratedArtifactsNextPilotCandidate(
                libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady
            )
        let policies = base.policies.map { policy -> CanonicalMigrationDomainPolicy in
            guard policy.domain == .tombstoneConflict else {
                return policy
            }
            return .v826TombstoneConflictNextPilotCandidate(
                templateReport: templateReport,
                generatedArtifactsTemplateCompleteOrObservationReady: generatedArtifactsTemplateCompleteOrObservationReady
            )
        }
        return CanonicalMigrationDomainMatrix(
            policies: policies,
            libraryMetadataPilotComplete: false,
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            generatedArtifactsTemplateCompleteOrObservationReady: generatedArtifactsTemplateCompleteOrObservationReady
        )
    }

    nonisolated static func v827TombstoneConflictActivePilot(
        libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool,
        generatedArtifactsTemplateCompleteOrObservationReady: Bool,
        templateReport: CanonicalTombstoneConflictTemplateReport = .currentV826Audit()
    ) -> CanonicalMigrationDomainMatrix {
        let base = v826TombstoneConflictNextPilotCandidate(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            generatedArtifactsTemplateCompleteOrObservationReady: generatedArtifactsTemplateCompleteOrObservationReady,
            templateReport: templateReport
        )
        let policies = base.policies.map { policy -> CanonicalMigrationDomainPolicy in
            switch policy.domain {
            case .tombstoneConflict:
                return .v827TombstoneConflictActivePilot(
                    templateReport: templateReport,
                    generatedArtifactsTemplateCompleteOrObservationReady: generatedArtifactsTemplateCompleteOrObservationReady
                )
            case .generatedArtifacts:
                return staticV827Policy(
                    policy,
                    acceptedTemplateSource: generatedArtifactsTemplateCompleteOrObservationReady,
                    observationComplete: generatedArtifactsTemplateCompleteOrObservationReady
                )
            case .libraryMetadata:
                return staticV827Policy(
                    policy,
                    acceptedTemplateSource: libraryMetadataObservationCompleteOrRetirementCandidateReady,
                    observationComplete: libraryMetadataObservationCompleteOrRetirementCandidateReady
                )
            default:
                return staticV827Policy(policy)
            }
        }
        return CanonicalMigrationDomainMatrix(
            policies: policies,
            libraryMetadataPilotComplete: false,
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            generatedArtifactsTemplateCompleteOrObservationReady: generatedArtifactsTemplateCompleteOrObservationReady
        )
    }

    nonisolated func policy(for domain: CanonicalMigrationDomain) -> CanonicalMigrationDomainPolicy? {
        policies.first { $0.domain == domain }
    }

    nonisolated func validate() -> CanonicalMigrationMatrixReport {
        var blockers: [CanonicalMigrationDomainBlocker] = []
        let activePilotPolicies = policies.filter(\.activePilot)
        if activePilotPolicies.isEmpty {
            blockers.append(.missingExplicitPilot)
        }
        if activePilotPolicies.count > 1 {
            blockers.append(.multipleActivePilots)
        }
        for policy in activePilotPolicies {
            if !policy.activePilotExplicit {
                blockers.append(.missingExplicitPilot)
            }
            if policy.domain != .libraryMetadata
                && !isGeneratedArtifactsV822ActivePilotAllowed(policy)
                && !isTombstoneConflictV827ActivePilotAllowed(policy) {
                blockers.append(.nonLibraryMetadataActivePilot)
            }
        }
        for policy in policies where !policy.activePilot {
            if !policy.staticOnly && !policy.blockedForRealMigration {
                blockers.append(.nonPilotDomainNotStaticOnly)
            }
        }
        for policy in policies {
            blockers.append(contentsOf: stageBlockers(for: policy))
            if policy.releaseDefaultEnabledCutover || policy.defaultCutoverEnabled {
                blockers.append(.releaseDefaultCutoverEnabled)
            }
            if policy.runtimeSwitchEnabled {
                blockers.append(.runtimeSwitchEnabled)
            }
            if policy.domain == .audioUpload, policy.activePilot, !libraryMetadataPilotComplete {
                blockers.append(.audioUploadBlockedUntilLibraryMetadataPilotComplete)
            }
            if policy.domain == .generatedArtifacts {
                if policy.activePilot && !isGeneratedArtifactsV822ActivePilotAllowed(policy) {
                    blockers.append(.generatedArtifactsActivePilotDeniedV821)
                }
                if policy.activePilot && !policy.hasReached(.nextPilotCandidate) {
                    blockers.append(.generatedArtifactsActivePilotBeforeNextPilotCandidate)
                }
                if policy.activePilot && !libraryMetadataObservationCompleteOrRetirementCandidateReady {
                    blockers.append(.generatedArtifactsActivePilotBeforeLibraryMetadataObservation)
                }
                if policy.hasReached(.expandedCanary), !policy.hasReached(.canaryN1) {
                    blockers.append(.generatedArtifactsStagedCanaryBeforeN1)
                }
                if policy.hasReached(.nextPilotCandidate),
                   !libraryMetadataObservationCompleteOrRetirementCandidateReady {
                    blockers.append(.generatedArtifactsNextPilotBeforeLibraryMetadataObservation)
                }
            }
            if policy.domain == .audioUpload, policy.activePilot {
                blockers.append(.audioUploadActivePilotDeniedV821)
            }
            if policy.domain == .tombstoneConflict, policy.activePilot, !isTombstoneConflictV827ActivePilotAllowed(policy) {
                blockers.append(.tombstoneConflictActivePilotDeniedV821)
                blockers.append(.tombstoneConflictActivePilotDeniedV826)
            }
            if policy.domain == .tombstoneConflict,
               policy.activePilot,
               !policy.hasReached(.nextPilotCandidate) {
                blockers.append(.tombstoneConflictActivePilotBeforeNextPilotCandidate)
            }
            if policy.domain == .tombstoneConflict,
               policy.activePilot,
               !generatedArtifactsTemplateCompleteOrObservationReady {
                blockers.append(.tombstoneConflictActivePilotBeforeGeneratedArtifactsObservation)
            }
            if policy.domain == .tombstoneConflict,
               policy.hasReached(.nextPilotCandidate),
               !generatedArtifactsTemplateCompleteOrObservationReady {
                blockers.append(.tombstoneConflictNextPilotBeforeGeneratedArtifactsObservation)
            }
            if policy.domain == .legacyRetirement,
               (policy.hasReached(.retirementCandidate) || policy.hasReached(.retired)),
               !policy.hasReached(.readSideCutover) {
                blockers.append(.legacyRetirementBeforeReadSideCutover)
            }
            if policy.domain == .legacyRetirement,
               (policy.activePilot || policy.hasReached(.retirementCandidate) || policy.hasReached(.retired)) {
                blockers.append(.legacyRetirementEnabledDeniedV821)
            }
        }
        let summary = diagnosticsSummary(for: policies, blockers: blockers)
        if !CanonicalMigrationDomainMatrix.isRedacted(summary) {
            blockers.append(.diagnosticsNotRedacted)
        }
        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        return CanonicalMigrationMatrixReport(
            policies: policies,
            activePilotDomain: activePilotPolicies.count == 1 ? activePilotPolicies.first?.domain : nil,
            blockers: uniqueBlockers,
            diagnosticsSummary: summary,
            diagnosticsRedacted: CanonicalMigrationDomainMatrix.isRedacted(summary)
        )
    }

    nonisolated private func stageBlockers(for policy: CanonicalMigrationDomainPolicy) -> [CanonicalMigrationDomainBlocker] {
        var blockers: [CanonicalMigrationDomainBlocker] = []
        for index in CanonicalMigrationDomainMatrix.orderedStages.indices {
            let stage = CanonicalMigrationDomainMatrix.orderedStages[index]
            guard policy.hasReached(stage) else {
                continue
            }
            for prior in CanonicalMigrationDomainMatrix.orderedStages[..<index] where prior != .notStarted {
                if !policy.hasReached(prior) {
                    blockers.append(.stageSkipped)
                    break
                }
            }
        }
        if policy.hasReached(.canaryN0), !policy.hasReached(.appSeamDefaultOff) {
            blockers.append(.canaryWithoutPreviousStageEvidence)
        }
        if policy.hasReached(.canaryN1), !policy.hasReached(.canaryN0) {
            blockers.append(.canaryWithoutPreviousStageEvidence)
        }
        if policy.hasReached(.expandedCanary), !policy.hasReached(.canaryN1) {
            blockers.append(.canaryWithoutPreviousStageEvidence)
        }
        if policy.hasReached(.readSideCutover) && !policy.writeSideCutoverSucceeded && !policy.hasReached(.domainCutover) {
            blockers.append(.readSideCutoverWithoutWriteSideCutover)
        }
        if policy.hasReached(.retired) {
            if !policy.hasReached(.readSideCutover) {
                blockers.append(.retiredWithoutReadSideCutover)
            }
            if !policy.observationComplete {
                blockers.append(.retiredWithoutObservation)
            }
            if !policy.fallbackReady {
                blockers.append(.retiredWithoutFallbackReadiness)
            }
        }
        return blockers
    }

    nonisolated private func diagnosticsSummary(
        for policies: [CanonicalMigrationDomainPolicy],
        blockers: [CanonicalMigrationDomainBlocker]
    ) -> String {
        let domainSummary = policies.map {
            "\($0.domain.rawValue):active=\($0.activePilot):static=\($0.staticOnly):runtimeSwitch=\($0.runtimeSwitchEnabled)"
        }.joined(separator: "|")
        let blockerSummary = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }.map(\.rawValue).joined(separator: "+")
        return "v8.13,matrixDomains=\(policies.count),\(domainSummary),blockers=\(blockerSummary)"
    }

    nonisolated static func isRedacted(_ text: String) -> Bool {
        CanonicalProductionRedaction.containsSensitivePathSignal(text) == false
            && !text.contains("-----BEGIN")
            && !text.contains("sharedSecret")
            && !text.contains("apiKey")
    }

    nonisolated private func isGeneratedArtifactsV822ActivePilotAllowed(
        _ policy: CanonicalMigrationDomainPolicy
    ) -> Bool {
        policy.domain == .generatedArtifacts
            && policy.activePilot
            && policy.activePilotExplicit
            && policy.hasReached(.nextPilotCandidate)
            && policy.hasReached(.canaryN0)
            && libraryMetadataObservationCompleteOrRetirementCandidateReady
            && !policy.defaultCutoverEnabled
            && !policy.releaseDefaultEnabledCutover
            && !policy.runtimeSwitchEnabled
            && policy.readPathLegacy
            && policy.noProductionInjection
            && !policy.legacySuppressionAllowed
    }

    nonisolated private func isTombstoneConflictV827ActivePilotAllowed(
        _ policy: CanonicalMigrationDomainPolicy
    ) -> Bool {
        policy.domain == .tombstoneConflict
            && policy.activePilot
            && policy.activePilotExplicit
            && policy.hasReached(.nextPilotCandidate)
            && policy.hasReached(.canaryN0)
            && !policy.hasReached(.canaryN1)
            && generatedArtifactsTemplateCompleteOrObservationReady
            && libraryMetadataObservationCompleteOrRetirementCandidateReady
            && !policy.defaultCutoverEnabled
            && !policy.releaseDefaultEnabledCutover
            && !policy.runtimeSwitchEnabled
            && policy.readPathLegacy
            && policy.noProductionInjection
            && !policy.legacySuppressionAllowed
    }

    nonisolated private static func staticV827Policy(
        _ policy: CanonicalMigrationDomainPolicy,
        acceptedTemplateSource: Bool = false,
        observationComplete: Bool = false
    ) -> CanonicalMigrationDomainPolicy {
        var next = policy
        next.activePilot = false
        next.activePilotExplicit = false
        next.staticOnly = true
        next.blockedForRealMigration = true
        next.defaultCutoverEnabled = false
        next.releaseDefaultEnabledCutover = false
        next.runtimeSwitchEnabled = false
        next.legacySuppressionAllowed = false
        next.noProductionInjection = true
        next.readPathLegacy = true
        next.writeSideCutoverSucceeded = false
        next.observationComplete = observationComplete
        next.fallbackReady = true
        next.stageStatuses = next.stageStatuses.mapValues { status in
            status == .activePilot ? .complete : status
        }
        if acceptedTemplateSource {
            next.stageStatuses[.nextPilotCandidate] = .complete
        }
        next.stageStatuses[.canaryN0] = nil
        next.stageStatuses[.canaryN1] = nil
        next.stageStatuses[.expandedCanary] = nil
        next.stageStatuses[.domainCutover] = nil
        next.stageStatuses[.readSideCutover] = nil
        next.stageStatuses[.retired] = nil
        return next
    }
}

extension CanonicalMigrationDomainPolicy {
    nonisolated static func v813RecordingMetadata() -> CanonicalMigrationDomainPolicy {
        CanonicalMigrationDomainPolicy(
            domain: .recordingMetadata,
            stageStatuses: completedThroughAppSeam(),
            activePilot: false,
            activePilotExplicit: false,
            staticOnly: true,
            blockedForRealMigration: true
        )
    }

    nonisolated static func v813GeneratedArtifacts() -> CanonicalMigrationDomainPolicy {
        CanonicalMigrationDomainPolicy(
            domain: .generatedArtifacts,
            stageStatuses: completedThroughAppSeam(),
            activePilot: false,
            activePilotExplicit: false,
            staticOnly: true,
            blockedForRealMigration: true
        )
    }

    nonisolated static func v821GeneratedArtifactsNextPilotCandidate(
        templateReport: CanonicalGeneratedArtifactTemplateReport = .currentV821Audit()
    ) -> CanonicalMigrationDomainPolicy {
        var statuses = completedThroughAppSeam()
        if templateReport.readyForNextPilotN0 {
            statuses[.nextPilotCandidate] = .nextPilotCandidate
        } else {
            statuses[.nextPilotCandidate] = .blocked
        }
        return CanonicalMigrationDomainPolicy(
            domain: .generatedArtifacts,
            stageStatuses: statuses,
            activePilot: false,
            activePilotExplicit: false,
            staticOnly: true,
            blockedForRealMigration: true,
            defaultCutoverEnabled: false,
            releaseDefaultEnabledCutover: false,
            runtimeSwitchEnabled: false,
            legacySuppressionAllowed: false,
            noProductionInjection: true,
            readPathLegacy: true,
            writeSideCutoverSucceeded: false,
            observationComplete: false,
            fallbackReady: true
        )
    }

    nonisolated static func v822GeneratedArtifactsActivePilot(
        templateReport: CanonicalGeneratedArtifactTemplateReport = .currentV821Audit()
    ) -> CanonicalMigrationDomainPolicy {
        var statuses = completedThroughAppSeam()
        let ready = templateReport.readyForNextPilotN0
        statuses[.nextPilotCandidate] = ready ? .complete : .blocked
        statuses[.canaryN0] = ready ? .activePilot : .blocked
        return CanonicalMigrationDomainPolicy(
            domain: .generatedArtifacts,
            stageStatuses: statuses,
            activePilot: ready,
            activePilotExplicit: ready,
            staticOnly: !ready,
            blockedForRealMigration: !ready,
            defaultCutoverEnabled: false,
            releaseDefaultEnabledCutover: false,
            runtimeSwitchEnabled: false,
            legacySuppressionAllowed: false,
            noProductionInjection: true,
            readPathLegacy: true,
            writeSideCutoverSucceeded: false,
            observationComplete: false,
            fallbackReady: true
        )
    }

    nonisolated static func v824GeneratedArtifactsStagedCanary(
        templateReport: CanonicalGeneratedArtifactTemplateReport = .currentV821Audit()
    ) -> CanonicalMigrationDomainPolicy {
        var statuses = completedThroughAppSeam()
        let ready = templateReport.readyForNextPilotN0
        statuses[.nextPilotCandidate] = ready ? .complete : .blocked
        statuses[.canaryN0] = ready ? .complete : .blocked
        statuses[.canaryN1] = ready ? .complete : .blocked
        statuses[.expandedCanary] = ready ? .activePilot : .blocked
        return CanonicalMigrationDomainPolicy(
            domain: .generatedArtifacts,
            stageStatuses: statuses,
            activePilot: ready,
            activePilotExplicit: ready,
            staticOnly: !ready,
            blockedForRealMigration: !ready,
            defaultCutoverEnabled: false,
            releaseDefaultEnabledCutover: false,
            runtimeSwitchEnabled: false,
            legacySuppressionAllowed: false,
            noProductionInjection: true,
            readPathLegacy: true,
            writeSideCutoverSucceeded: false,
            observationComplete: false,
            fallbackReady: true
        )
    }

    nonisolated static func v813LibraryMetadataPilot() -> CanonicalMigrationDomainPolicy {
        CanonicalMigrationDomainPolicy(
            domain: .libraryMetadata,
            stageStatuses: completedThroughAppSeam(activeStage: .appSeamDefaultOff),
            activePilot: true,
            activePilotExplicit: true,
            staticOnly: false,
            blockedForRealMigration: false
        )
    }

    nonisolated static func v813TombstoneConflict() -> CanonicalMigrationDomainPolicy {
        CanonicalMigrationDomainPolicy(
            domain: .tombstoneConflict,
            stageStatuses: [
                .projected: .complete,
                .planned: .complete,
                .noCommit: .complete,
                .realApplyPort: .complete,
                .commitExecutor: .complete
            ],
            activePilot: false,
            activePilotExplicit: false,
            staticOnly: true,
            blockedForRealMigration: true
        )
    }

    nonisolated static func v826TombstoneConflictNextPilotCandidate(
        templateReport: CanonicalTombstoneConflictTemplateReport = .currentV826Audit(),
        generatedArtifactsTemplateCompleteOrObservationReady: Bool
    ) -> CanonicalMigrationDomainPolicy {
        var statuses = completedThroughAppSeam()
        let ready = templateReport.readyForNextPilotN0 && generatedArtifactsTemplateCompleteOrObservationReady
        statuses[.nextPilotCandidate] = ready ? .nextPilotCandidate : .blocked
        return CanonicalMigrationDomainPolicy(
            domain: .tombstoneConflict,
            stageStatuses: statuses,
            activePilot: false,
            activePilotExplicit: false,
            staticOnly: true,
            blockedForRealMigration: true,
            defaultCutoverEnabled: false,
            releaseDefaultEnabledCutover: false,
            runtimeSwitchEnabled: false,
            legacySuppressionAllowed: false,
            noProductionInjection: true,
            readPathLegacy: true,
            writeSideCutoverSucceeded: false,
            observationComplete: false,
            fallbackReady: true
        )
    }

    nonisolated static func v827TombstoneConflictActivePilot(
        templateReport: CanonicalTombstoneConflictTemplateReport = .currentV826Audit(),
        generatedArtifactsTemplateCompleteOrObservationReady: Bool
    ) -> CanonicalMigrationDomainPolicy {
        var statuses = completedThroughAppSeam()
        let ready = templateReport.readyForNextPilotN0 && generatedArtifactsTemplateCompleteOrObservationReady
        statuses[.nextPilotCandidate] = ready ? .complete : .blocked
        statuses[.canaryN0] = ready ? .activePilot : .blocked
        return CanonicalMigrationDomainPolicy(
            domain: .tombstoneConflict,
            stageStatuses: statuses,
            activePilot: ready,
            activePilotExplicit: ready,
            staticOnly: !ready,
            blockedForRealMigration: !ready,
            defaultCutoverEnabled: false,
            releaseDefaultEnabledCutover: false,
            runtimeSwitchEnabled: false,
            legacySuppressionAllowed: false,
            noProductionInjection: true,
            readPathLegacy: true,
            writeSideCutoverSucceeded: false,
            observationComplete: false,
            fallbackReady: true
        )
    }

    nonisolated static func v813AudioUpload() -> CanonicalMigrationDomainPolicy {
        CanonicalMigrationDomainPolicy(
            domain: .audioUpload,
            stageStatuses: [
                .projected: .complete,
                .planned: .complete,
                .noCommit: .complete
            ],
            activePilot: false,
            activePilotExplicit: false,
            staticOnly: true,
            blockedForRealMigration: true
        )
    }

    nonisolated static func v813UIProjection() -> CanonicalMigrationDomainPolicy {
        CanonicalMigrationDomainPolicy(
            domain: .uiProjection,
            stageStatuses: [.projected: .staticOnly],
            activePilot: false,
            activePilotExplicit: false,
            staticOnly: true,
            blockedForRealMigration: true
        )
    }

    nonisolated static func v813LegacyRetirement() -> CanonicalMigrationDomainPolicy {
        CanonicalMigrationDomainPolicy(
            domain: .legacyRetirement,
            stageStatuses: [:],
            activePilot: false,
            activePilotExplicit: false,
            staticOnly: true,
            blockedForRealMigration: true
        )
    }

    nonisolated private static func completedThroughAppSeam(
        activeStage: CanonicalMigrationStage? = nil
    ) -> [CanonicalMigrationStage: CanonicalMigrationStageStatus] {
        [
            .projected: activeStage == .projected ? .activePilot : .complete,
            .planned: activeStage == .planned ? .activePilot : .complete,
            .noCommit: activeStage == .noCommit ? .activePilot : .complete,
            .realApplyPort: activeStage == .realApplyPort ? .activePilot : .complete,
            .commitExecutor: activeStage == .commitExecutor ? .activePilot : .complete,
            .appSeamDefaultOff: activeStage == .appSeamDefaultOff ? .activePilot : .complete
        ]
    }
}

nonisolated enum CanonicalMigrationConfigViolation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case multipleActiveCanaryDomains
    case activeDomainNotLibraryMetadata
    case audioUploadActiveBeforePilotComplete
    case tombstoneConflictActiveBeforePilotComplete
    case generatedArtifactsActiveBeforePilotComplete
    case generatedArtifactsNextPilotBeforeLibraryMetadataObservation
    case releaseDefaultEnabledCutover
    case runtimeSwitchEnabled
    case legacyRetirementBeforeReadSideCutover
}

nonisolated struct CanonicalMigrationConfigValidationResult: Codable, Equatable, Sendable {
    var violations: [CanonicalMigrationConfigViolation]
    var diagnosticsSummary: String

    nonisolated var valid: Bool {
        violations.isEmpty
    }
}

nonisolated struct CanonicalMigrationGlobalConfigValidator: Sendable {
    nonisolated init() {}

    nonisolated func validate(_ matrix: CanonicalMigrationDomainMatrix) -> CanonicalMigrationConfigValidationResult {
        var violations: [CanonicalMigrationConfigViolation] = []
        let activeDomains = matrix.policies.filter(\.hasActiveCanaryOrCutover)
        if activeDomains.count > 1 {
            violations.append(.multipleActiveCanaryDomains)
        }
        for policy in activeDomains {
            if policy.domain != .libraryMetadata
                && !Self.generatedArtifactsV822ActivePilotAllowed(policy, in: matrix)
                && !Self.tombstoneConflictV827ActivePilotAllowed(policy, in: matrix) {
                violations.append(.activeDomainNotLibraryMetadata)
            }
        }
        if matrix.policy(for: .audioUpload)?.hasActiveCanaryOrCutover == true, !matrix.libraryMetadataPilotComplete {
            violations.append(.audioUploadActiveBeforePilotComplete)
        }
        if let tombstone = matrix.policy(for: .tombstoneConflict),
           tombstone.hasActiveCanaryOrCutover,
           !Self.tombstoneConflictV827ActivePilotAllowed(tombstone, in: matrix),
           !matrix.libraryMetadataPilotComplete {
            violations.append(.tombstoneConflictActiveBeforePilotComplete)
        }
        if let generated = matrix.policy(for: .generatedArtifacts),
           generated.hasActiveCanaryOrCutover,
           !generated.staticOnly,
           !Self.generatedArtifactsV822ActivePilotAllowed(generated, in: matrix) {
            violations.append(.generatedArtifactsActiveBeforePilotComplete)
        }
        if let generated = matrix.policy(for: .generatedArtifacts),
           generated.hasReached(.nextPilotCandidate),
           !matrix.libraryMetadataObservationCompleteOrRetirementCandidateReady {
            violations.append(.generatedArtifactsNextPilotBeforeLibraryMetadataObservation)
        }
        if matrix.policies.contains(where: { $0.releaseDefaultEnabledCutover || $0.defaultCutoverEnabled }) {
            violations.append(.releaseDefaultEnabledCutover)
        }
        if matrix.policies.contains(where: \.runtimeSwitchEnabled) {
            violations.append(.runtimeSwitchEnabled)
        }
        if let legacy = matrix.policy(for: .legacyRetirement),
           (legacy.hasReached(.retirementCandidate) || legacy.hasReached(.retired)),
           !legacy.hasReached(.readSideCutover) {
            violations.append(.legacyRetirementBeforeReadSideCutover)
        }
        let uniqueViolations = Array(Set(violations)).sorted { $0.rawValue < $1.rawValue }
        return CanonicalMigrationConfigValidationResult(
            violations: uniqueViolations,
            diagnosticsSummary: "v8.13,globalConfig,violations=\(uniqueViolations.map(\.rawValue).joined(separator: "+"))"
        )
    }

    nonisolated private static func generatedArtifactsV822ActivePilotAllowed(
        _ policy: CanonicalMigrationDomainPolicy,
        in matrix: CanonicalMigrationDomainMatrix
    ) -> Bool {
        policy.domain == .generatedArtifacts
            && policy.activePilot
            && policy.activePilotExplicit
            && policy.hasReached(.nextPilotCandidate)
            && policy.hasReached(.canaryN0)
            && matrix.libraryMetadataObservationCompleteOrRetirementCandidateReady
            && !policy.defaultCutoverEnabled
            && !policy.releaseDefaultEnabledCutover
            && !policy.runtimeSwitchEnabled
            && policy.readPathLegacy
            && policy.noProductionInjection
            && !policy.legacySuppressionAllowed
    }

    nonisolated private static func tombstoneConflictV827ActivePilotAllowed(
        _ policy: CanonicalMigrationDomainPolicy,
        in matrix: CanonicalMigrationDomainMatrix
    ) -> Bool {
        policy.domain == .tombstoneConflict
            && policy.activePilot
            && policy.activePilotExplicit
            && policy.hasReached(.nextPilotCandidate)
            && policy.hasReached(.canaryN0)
            && !policy.hasReached(.canaryN1)
            && matrix.generatedArtifactsTemplateCompleteOrObservationReady
            && matrix.libraryMetadataObservationCompleteOrRetirementCandidateReady
            && !policy.defaultCutoverEnabled
            && !policy.releaseDefaultEnabledCutover
            && !policy.runtimeSwitchEnabled
            && policy.readPathLegacy
            && policy.noProductionInjection
            && !policy.legacySuppressionAllowed
    }
}

nonisolated enum CanonicalLibraryMetadataPilotReadiness: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readyForN0
    case readyForN1
    case missingNoCommit
    case missingRealApplyPort
    case missingCommitExecutor
    case missingAppSeam
    case missingReadSideParallel
    case missingTests
    case blocked
}

nonisolated enum CanonicalLibraryMetadataPilotBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingCanonicalProjection
    case missingPlanner
    case missingApplyPlanBridge
    case missingNoCommit
    case missingRealApplyPort
    case missingCommitExecutor
    case missingAppSeam
    case missingCanaryPolicy
    case missingRollbackPlan
    case missingFailureInjection
    case missingLegacyFallback
    case duplicateSuppressionBeforeSuccess
    case missingReadSideParallel
    case resourceMoveGuardMissing
    case physicalDeleteGuardMissing
    case missingTests
    case missingDocs

    nonisolated var blocksN0: Bool {
        switch self {
        case .missingReadSideParallel, .missingDocs:
            return false
        default:
            return true
        }
    }
}

nonisolated struct CanonicalLibraryMetadataPilotReport: Codable, Equatable, Sendable {
    var readiness: CanonicalLibraryMetadataPilotReadiness
    var blockers: [CanonicalLibraryMetadataPilotBlocker]
    var readyForN0: Bool
    var readyForN1: Bool
    var diagnosticsSummary: String

    nonisolated static func audit(
        canonicalProjection: Bool,
        planner: Bool,
        applyPlanBridge: Bool,
        noCommitExecutor: Bool,
        realApplyPort: Bool,
        commitExecutor: Bool,
        appSeamDefaultOff: Bool,
        canaryPolicy: Bool,
        rollbackPlan: Bool,
        failureInjection: Bool,
        legacyFallback: Bool,
        duplicateSuppressionAfterSuccessOnly: Bool,
        readSideParallelProjection: Bool,
        noResourceMoveGuard: Bool,
        noPhysicalDeleteGuard: Bool,
        tests: Bool,
        docs: Bool
    ) -> CanonicalLibraryMetadataPilotReport {
        var blockers: [CanonicalLibraryMetadataPilotBlocker] = []
        if !canonicalProjection { blockers.append(.missingCanonicalProjection) }
        if !planner { blockers.append(.missingPlanner) }
        if !applyPlanBridge { blockers.append(.missingApplyPlanBridge) }
        if !noCommitExecutor { blockers.append(.missingNoCommit) }
        if !realApplyPort { blockers.append(.missingRealApplyPort) }
        if !commitExecutor { blockers.append(.missingCommitExecutor) }
        if !appSeamDefaultOff { blockers.append(.missingAppSeam) }
        if !canaryPolicy { blockers.append(.missingCanaryPolicy) }
        if !rollbackPlan { blockers.append(.missingRollbackPlan) }
        if !failureInjection { blockers.append(.missingFailureInjection) }
        if !legacyFallback { blockers.append(.missingLegacyFallback) }
        if !duplicateSuppressionAfterSuccessOnly { blockers.append(.duplicateSuppressionBeforeSuccess) }
        if !readSideParallelProjection { blockers.append(.missingReadSideParallel) }
        if !noResourceMoveGuard { blockers.append(.resourceMoveGuardMissing) }
        if !noPhysicalDeleteGuard { blockers.append(.physicalDeleteGuardMissing) }
        if !tests { blockers.append(.missingTests) }
        if !docs { blockers.append(.missingDocs) }
        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let n0Ready = uniqueBlockers.allSatisfy { !$0.blocksN0 }
        let n1Ready = uniqueBlockers.isEmpty
        let readiness: CanonicalLibraryMetadataPilotReadiness
        if uniqueBlockers.contains(.missingNoCommit) {
            readiness = .missingNoCommit
        } else if uniqueBlockers.contains(.missingRealApplyPort) {
            readiness = .missingRealApplyPort
        } else if uniqueBlockers.contains(.missingCommitExecutor) {
            readiness = .missingCommitExecutor
        } else if uniqueBlockers.contains(.missingAppSeam) {
            readiness = .missingAppSeam
        } else if uniqueBlockers.contains(.missingReadSideParallel) {
            readiness = .missingReadSideParallel
        } else if uniqueBlockers.contains(.missingTests) {
            readiness = .missingTests
        } else if n1Ready {
            readiness = .readyForN1
        } else if n0Ready {
            readiness = .readyForN0
        } else {
            readiness = .blocked
        }
        return CanonicalLibraryMetadataPilotReport(
            readiness: readiness,
            blockers: uniqueBlockers,
            readyForN0: n0Ready,
            readyForN1: n1Ready,
            diagnosticsSummary: "domain=libraryMetadata,readiness=\(readiness.rawValue),blockers=\(uniqueBlockers.map(\.rawValue).joined(separator: "+"))"
        )
    }

    nonisolated static func currentV813Audit(readSideParallelProjection: Bool = true) -> CanonicalLibraryMetadataPilotReport {
        audit(
            canonicalProjection: true,
            planner: true,
            applyPlanBridge: true,
            noCommitExecutor: true,
            realApplyPort: true,
            commitExecutor: true,
            appSeamDefaultOff: true,
            canaryPolicy: true,
            rollbackPlan: true,
            failureInjection: true,
            legacyFallback: true,
            duplicateSuppressionAfterSuccessOnly: true,
            readSideParallelProjection: readSideParallelProjection,
            noResourceMoveGuard: true,
            noPhysicalDeleteGuard: true,
            tests: true,
            docs: true
        )
    }
}

nonisolated struct CanonicalMigrationStaticDomainAudit: Codable, Equatable, Sendable {
    var domain: CanonicalMigrationDomain
    var machinePartsPresent: Bool
    var appSeamPresent: Bool
    var defaultOff: Bool
    var noProductionInjection: Bool
    var readPathLegacy: Bool
    var testsPresent: Bool
    var blockers: [CanonicalMigrationDomainBlocker]
    var staticReviewRecommended: Bool
    var realMigrationBlocked: Bool
    var diagnosticsSummary: String

    nonisolated init(
        domain: CanonicalMigrationDomain,
        machinePartsPresent: Bool,
        appSeamPresent: Bool,
        defaultOff: Bool,
        noProductionInjection: Bool,
        readPathLegacy: Bool,
        testsPresent: Bool,
        staticReviewRecommended: Bool = true,
        realMigrationBlocked: Bool = true
    ) {
        var blockers: [CanonicalMigrationDomainBlocker] = []
        if !machinePartsPresent { blockers.append(.missingMachineParts) }
        if !appSeamPresent { blockers.append(.missingAppSeam) }
        if !defaultOff { blockers.append(.cutoverNotDefaultOff) }
        if !noProductionInjection { blockers.append(.productionInjectionPresent) }
        if !readPathLegacy { blockers.append(.readPathNotLegacy) }
        if !testsPresent { blockers.append(.testsMissing) }
        self.domain = domain
        self.machinePartsPresent = machinePartsPresent
        self.appSeamPresent = appSeamPresent
        self.defaultOff = defaultOff
        self.noProductionInjection = noProductionInjection
        self.readPathLegacy = readPathLegacy
        self.testsPresent = testsPresent
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.staticReviewRecommended = staticReviewRecommended
        self.realMigrationBlocked = realMigrationBlocked
        self.diagnosticsSummary = [
            "domain=\(domain.rawValue)",
            "machinePartsPresent=\(machinePartsPresent)",
            "appSeamPresent=\(appSeamPresent)",
            "defaultOff=\(defaultOff)",
            "readPathLegacy=\(readPathLegacy)",
            "realMigrationBlocked=\(realMigrationBlocked)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalOtherDomainsStaticAuditReport: Codable, Equatable, Sendable {
    var audits: [CanonicalMigrationStaticDomainAudit]

    nonisolated static func v813Default() -> CanonicalOtherDomainsStaticAuditReport {
        CanonicalOtherDomainsStaticAuditReport(
            audits: [
                CanonicalMigrationStaticDomainAudit(
                    domain: .recordingMetadata,
                    machinePartsPresent: true,
                    appSeamPresent: true,
                    defaultOff: true,
                    noProductionInjection: true,
                    readPathLegacy: true,
                    testsPresent: true
                ),
                CanonicalMigrationStaticDomainAudit(
                    domain: .generatedArtifacts,
                    machinePartsPresent: true,
                    appSeamPresent: true,
                    defaultOff: true,
                    noProductionInjection: true,
                    readPathLegacy: true,
                    testsPresent: true
                ),
                CanonicalMigrationStaticDomainAudit(
                    domain: .tombstoneConflict,
                    machinePartsPresent: true,
                    appSeamPresent: true,
                    defaultOff: true,
                    noProductionInjection: true,
                    readPathLegacy: true,
                    testsPresent: true
                ),
                CanonicalMigrationStaticDomainAudit(
                    domain: .audioUpload,
                    machinePartsPresent: false,
                    appSeamPresent: true,
                    defaultOff: true,
                    noProductionInjection: true,
                    readPathLegacy: true,
                    testsPresent: true
                )
            ]
        )
    }

    nonisolated func audit(for domain: CanonicalMigrationDomain) -> CanonicalMigrationStaticDomainAudit? {
        audits.first { $0.domain == domain }
    }

    nonisolated var diagnosticsSummary: String {
        audits.map(\.diagnosticsSummary).joined(separator: "|")
    }
}
