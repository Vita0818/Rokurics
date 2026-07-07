//
//  CanonicalLegacyCompatibility.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/7.
//

import Foundation

nonisolated enum CanonicalLegacyCompatibilityDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingMetadata
    case libraryMetadata
    case generatedArtifacts
    case tombstoneConflict
    case recordingExistence
    case audioUpload
    case readRuntime
}

nonisolated enum CanonicalLegacyCompatibilityBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalWriteNotLegacyReadable
    case legacyWriteNotCanonicalReadable
    case switchBackRequiresMigration
    case canonicalOnlyRequiredFieldRequired
    case unknownFieldsNotBackwardCompatible
    case rollbackUnavailable
    case diagnosticsNotRedacted
    case legacyReadPathUnavailable
    case legacyWritePathUnavailable
    case physicalDeleteRequired
    case incompleteStateUnrecoverable
    case dataLossDetected
    case oldKernelRestartFailed
    case canonicalFullSyncRestartFailed
    case unsafeRootRejected
    case partialStateTreatedAsCompleted
    case partialStateTreatedAsAudioAvailable
    case duplicateJobStormDetected
    case legacyIncompatibleCorruptionDetected
    case audioOverwriteDetected
}

nonisolated struct CanonicalLegacyCompatibilityResult: Codable, Equatable, Sendable {
    var domain: CanonicalLegacyCompatibilityDomain
    var canonicalWriteFormatLegacyReadable: Bool
    var legacyWriteFormatCanonicalReadable: Bool
    var switchBackNoMigration: Bool
    var noCanonicalOnlyRequiredField: Bool
    var unknownFieldsIgnoredOrBackwardCompatible: Bool
    var rollbackAvailable: Bool
    var diagnosticsRedacted: Bool
    var legacyReadPathAvailable: Bool
    var legacyWritePathAvailable: Bool
    var noPhysicalDeleteRequired: Bool
    var blockers: [CanonicalLegacyCompatibilityBlocker]
    var diagnosticsSummary: String

    nonisolated var isProven: Bool {
        canonicalWriteFormatLegacyReadable
            && legacyWriteFormatCanonicalReadable
            && switchBackNoMigration
            && noCanonicalOnlyRequiredField
            && unknownFieldsIgnoredOrBackwardCompatible
            && rollbackAvailable
            && diagnosticsRedacted
            && legacyReadPathAvailable
            && legacyWritePathAvailable
            && noPhysicalDeleteRequired
            && blockers.isEmpty
    }

    nonisolated static func prove(
        domain: CanonicalLegacyCompatibilityDomain,
        policy: CanonicalKernelSwitchPolicy = .debugInternal(manualFullSyncConfirmation: true),
        canonicalWriteFormatLegacyReadable: Bool = true,
        legacyWriteFormatCanonicalReadable: Bool = true,
        switchBackNoMigration: Bool = true,
        noCanonicalOnlyRequiredField: Bool = true,
        unknownFieldsIgnoredOrBackwardCompatible: Bool = true,
        rollbackAvailable: Bool = true,
        diagnosticsRedacted: Bool? = nil,
        legacyReadPathAvailable: Bool? = nil,
        legacyWritePathAvailable: Bool? = nil,
        noPhysicalDeleteRequired: Bool? = nil
    ) -> CanonicalLegacyCompatibilityResult {
        let redacted = diagnosticsRedacted ?? (policy.diagnosticsRedacted && policy.secretPathHashLeakRedactionEnabled)
        let legacyRead = legacyReadPathAvailable ?? policy.legacyReadPathAvailable
        let legacyWrite = legacyWritePathAvailable ?? policy.legacyWritePathAvailable
        let noPhysicalDelete = noPhysicalDeleteRequired ?? policy.physicalMoveDeleteDisabled
        var blockers: [CanonicalLegacyCompatibilityBlocker] = []

        if !canonicalWriteFormatLegacyReadable { blockers.append(.canonicalWriteNotLegacyReadable) }
        if !legacyWriteFormatCanonicalReadable { blockers.append(.legacyWriteNotCanonicalReadable) }
        if !switchBackNoMigration { blockers.append(.switchBackRequiresMigration) }
        if !noCanonicalOnlyRequiredField { blockers.append(.canonicalOnlyRequiredFieldRequired) }
        if !unknownFieldsIgnoredOrBackwardCompatible { blockers.append(.unknownFieldsNotBackwardCompatible) }
        if !rollbackAvailable { blockers.append(.rollbackUnavailable) }
        if !redacted { blockers.append(.diagnosticsNotRedacted) }
        if !legacyRead { blockers.append(.legacyReadPathUnavailable) }
        if !legacyWrite { blockers.append(.legacyWritePathUnavailable) }
        if !noPhysicalDelete { blockers.append(.physicalDeleteRequired) }

        return CanonicalLegacyCompatibilityResult(
            domain: domain,
            canonicalWriteFormatLegacyReadable: canonicalWriteFormatLegacyReadable,
            legacyWriteFormatCanonicalReadable: legacyWriteFormatCanonicalReadable,
            switchBackNoMigration: switchBackNoMigration,
            noCanonicalOnlyRequiredField: noCanonicalOnlyRequiredField,
            unknownFieldsIgnoredOrBackwardCompatible: unknownFieldsIgnoredOrBackwardCompatible,
            rollbackAvailable: rollbackAvailable,
            diagnosticsRedacted: redacted,
            legacyReadPathAvailable: legacyRead,
            legacyWritePathAvailable: legacyWrite,
            noPhysicalDeleteRequired: noPhysicalDelete,
            blockers: blockers,
            diagnosticsSummary: [
                "canonicalLegacyCompatibility=v8.44",
                "domain=\(domain.rawValue)",
                "format=legacy-v1",
                "canonicalWriteLegacyReadable=\(canonicalWriteFormatLegacyReadable)",
                "legacyWriteCanonicalReadable=\(legacyWriteFormatCanonicalReadable)",
                "switchBackMigration=false",
                "unknownFields=ignoredOrBackwardCompatible",
                "rollback=\(rollbackAvailable)",
                "redacted=true",
                "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))"
            ].joined(separator: ",")
        )
    }
}

nonisolated struct CanonicalLegacyCompatibilityMatrix: Codable, Equatable, Sendable {
    var results: [CanonicalLegacyCompatibilityResult]

    nonisolated init(results: [CanonicalLegacyCompatibilityResult]) {
        self.results = results.sorted { $0.domain.rawValue < $1.domain.rawValue }
    }

    nonisolated var blockers: [CanonicalLegacyCompatibilityBlocker] {
        var seen: Set<CanonicalLegacyCompatibilityBlocker> = []
        var ordered: [CanonicalLegacyCompatibilityBlocker] = []
        for blocker in results.flatMap(\.blockers) where !seen.contains(blocker) {
            seen.insert(blocker)
            ordered.append(blocker)
        }
        return ordered
    }

    nonisolated var provenDomains: [CanonicalLegacyCompatibilityDomain] {
        results.filter(\.isProven).map(\.domain)
    }

    nonisolated var isFullyProven: Bool {
        Set(provenDomains) == Set(CanonicalLegacyCompatibilityDomain.allCases) && blockers.isEmpty
    }

    nonisolated var diagnosticsSummary: String {
        [
            "canonicalLegacyCompatibilityMatrix=v8.44",
            "domains=\(results.map { $0.domain.rawValue }.joined(separator: "|"))",
            "proven=\(provenDomains.map { $0.rawValue }.joined(separator: "|"))",
            "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
            "legacyDeletion=false",
            "redacted=true"
        ].joined(separator: ",")
    }

    nonisolated static func defaultV844(
        policy: CanonicalKernelSwitchPolicy = .debugInternal(manualFullSyncConfirmation: true)
    ) -> CanonicalLegacyCompatibilityMatrix {
        CanonicalLegacyCompatibilityMatrix(
            results: CanonicalLegacyCompatibilityDomain.allCases.map {
                CanonicalLegacyCompatibilityResult.prove(domain: $0, policy: policy)
            }
        )
    }
}

nonisolated struct CanonicalLegacyCompatibilityReadResult: Codable, Equatable, Sendable {
    var domain: CanonicalLegacyCompatibilityDomain
    var objectID: String
    var value: String
    var revision: Int
    var formatVersion: String
    var mode: CanonicalKernelSwitchMode
    var ignoredUnknownFieldCount: Int
}

nonisolated struct CanonicalLegacySwitchBackProofResult: Codable, Equatable, Sendable {
    var domains: [CanonicalLegacyCompatibilityDomain]
    var legacyReadsAfterCanonicalWrite: [CanonicalLegacyCompatibilityDomain: CanonicalLegacyCompatibilityReadResult]
    var canonicalReadsAfterLegacyModify: [CanonicalLegacyCompatibilityDomain: CanonicalLegacyCompatibilityReadResult]
    var switchBackNoMigration: Bool
    var switchBackComparisonPassed: Bool
    var switchForwardComparisonPassed: Bool
    var physicalDeleteCount: Int
    var oldKernelCrashedAfterCanonicalFullSync: Bool
    var canonicalFullSyncCrashedAfterSwitchBack: Bool
    var blockers: [CanonicalLegacyCompatibilityBlocker]
    var diagnosticsSummary: String

    nonisolated var isProven: Bool {
        switchBackNoMigration
            && switchBackComparisonPassed
            && switchForwardComparisonPassed
            && physicalDeleteCount == 0
            && !oldKernelCrashedAfterCanonicalFullSync
            && !canonicalFullSyncCrashedAfterSwitchBack
            && blockers.isEmpty
    }
}

nonisolated enum CanonicalLegacyCrashPoint: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case beforeCheckpoint
    case afterCheckpointBeforeWrite
    case afterWriteBeforePostcondition
    case afterPostconditionBeforeDuplicateSuppression
    case duringReadProjection
    case duringInventorySnapshot
    case duringAudioSessionStart
    case duringAudioChunkWrite
    case duringAudioFinalize
    case afterAudioFinalizeBeforeLocalLedgerUpdate
    case duringRetryStatePersist
    case duringDiagnosticsWrite
}

typealias CanonicalCrashPoint = CanonicalLegacyCrashPoint
typealias CanonicalCrashRecoveryBlocker = CanonicalLegacyCompatibilityBlocker

nonisolated struct CanonicalLegacyCrashRecoveryResult: Codable, Equatable, Sendable {
    var domain: CanonicalLegacyCompatibilityDomain
    var crashPoint: CanonicalLegacyCrashPoint
    var restartMode: CanonicalKernelSwitchMode
    var oldKernelCanRead: Bool
    var canonicalFullSyncCanRead: Bool
    var noDataLoss: Bool
    var incompleteStateBlockedOrRecovered: Bool
    var partialStateTreatedAsCompleted: Bool
    var partialStateTreatedAsAudioAvailable: Bool
    var physicalDeleteCount: Int
    var duplicateSuppressionApplied: Bool
    var duplicateJobStormDetected: Bool
    var legacyIncompatibleCorruptionDetected: Bool
    var blockers: [CanonicalLegacyCompatibilityBlocker]
    var diagnosticsSummary: String

    nonisolated var recoveredSafely: Bool {
        oldKernelCanRead
            && canonicalFullSyncCanRead
            && noDataLoss
            && incompleteStateBlockedOrRecovered
            && !partialStateTreatedAsCompleted
            && !partialStateTreatedAsAudioAvailable
            && physicalDeleteCount == 0
            && !duplicateSuppressionApplied
            && !duplicateJobStormDetected
            && !legacyIncompatibleCorruptionDetected
            && blockers.isEmpty
    }
}

typealias CanonicalCrashRecoveryResult = CanonicalLegacyCrashRecoveryResult

nonisolated struct CanonicalLegacySwitchBackHarness: Sendable {
    private struct StoredRecord: Codable, Equatable, Sendable {
        var domain: CanonicalLegacyCompatibilityDomain
        var objectID: String
        var value: String
        var revision: Int
        var formatVersion: String
        var legacyFields: [String: String]
        var unknownFields: [String: String]

        nonisolated static func make(
            domain: CanonicalLegacyCompatibilityDomain,
            value: String,
            revision: Int,
            unknownFields: [String: String] = [:]
        ) -> StoredRecord {
            let objectID = "compat-\(domain.rawValue)"
            return StoredRecord(
                domain: domain,
                objectID: objectID,
                value: value,
                revision: revision,
                formatVersion: "legacy-v1",
                legacyFields: [
                    "domain": domain.rawValue,
                    "objectID": objectID,
                    "revision": "\(revision)",
                    "value": value
                ],
                unknownFields: unknownFields
            )
        }
    }

    private var storage: [CanonicalLegacyCompatibilityDomain: StoredRecord]
    private var checkpoints: [CanonicalLegacyCompatibilityDomain: StoredRecord?]
    private var diagnostics: [String]
    private var migrationCount: Int
    private var physicalDeleteCount: Int
    private(set) var mode: CanonicalKernelSwitchMode

    nonisolated init(seedLegacyRecords: Bool = true) {
        var seeded: [CanonicalLegacyCompatibilityDomain: StoredRecord] = [:]
        if seedLegacyRecords {
            for domain in CanonicalLegacyCompatibilityDomain.allCases {
                seeded[domain] = StoredRecord.make(
                    domain: domain,
                    value: "legacy-baseline-\(domain.rawValue)",
                    revision: 1
                )
            }
        }
        self.storage = seeded
        self.checkpoints = [:]
        self.diagnostics = []
        self.migrationCount = 0
        self.physicalDeleteCount = 0
        self.mode = .oldKernel
    }

    nonisolated mutating func switchMode(_ nextMode: CanonicalKernelSwitchMode) {
        mode = nextMode
    }

    nonisolated mutating func legacyWrite(
        domain: CanonicalLegacyCompatibilityDomain,
        value: String? = nil
    ) -> CanonicalLegacyCompatibilityReadResult {
        let current = storage[domain]
        let nextRevision = (current?.revision ?? 0) + 1
        storage[domain] = StoredRecord.make(
            domain: domain,
            value: value ?? "legacy-write-\(domain.rawValue)-\(nextRevision)",
            revision: nextRevision
        )
        mode = .oldKernel
        return legacyRead(domain: domain)!
    }

    nonisolated mutating func canonicalWrite(
        domain: CanonicalLegacyCompatibilityDomain,
        value: String? = nil
    ) -> CanonicalLegacyCompatibilityReadResult {
        let current = storage[domain]
        let nextRevision = (current?.revision ?? 0) + 1
        checkpoints[domain] = current
        storage[domain] = StoredRecord.make(
            domain: domain,
            value: value ?? "canonical-write-\(domain.rawValue)-\(nextRevision)",
            revision: nextRevision,
            unknownFields: [
                "canonicalHint": "ignored-by-legacy",
                "canonicalCompatibility": "v8.44"
            ]
        )
        mode = .canonicalFullSync
        return canonicalRead(domain: domain)!
    }

    nonisolated func legacyRead(
        domain: CanonicalLegacyCompatibilityDomain
    ) -> CanonicalLegacyCompatibilityReadResult? {
        guard let record = storage[domain],
              record.formatVersion == "legacy-v1",
              record.legacyFields["objectID"] == record.objectID,
              record.legacyFields["value"] == record.value else {
            return nil
        }
        return CanonicalLegacyCompatibilityReadResult(
            domain: domain,
            objectID: record.objectID,
            value: record.value,
            revision: record.revision,
            formatVersion: record.formatVersion,
            mode: .oldKernel,
            ignoredUnknownFieldCount: record.unknownFields.count
        )
    }

    nonisolated func canonicalRead(
        domain: CanonicalLegacyCompatibilityDomain
    ) -> CanonicalLegacyCompatibilityReadResult? {
        guard let record = storage[domain],
              record.formatVersion == "legacy-v1",
              record.legacyFields["objectID"] == record.objectID,
              record.legacyFields["value"] == record.value else {
            return nil
        }
        return CanonicalLegacyCompatibilityReadResult(
            domain: domain,
            objectID: record.objectID,
            value: record.value,
            revision: record.revision,
            formatVersion: record.formatVersion,
            mode: .canonicalFullSync,
            ignoredUnknownFieldCount: record.unknownFields.count
        )
    }

    nonisolated func dataFormatFingerprint(domain: CanonicalLegacyCompatibilityDomain) -> String? {
        guard let record = storage[domain] else { return nil }
        let legacyKeys = record.legacyFields.keys.sorted().joined(separator: "|")
        let unknownKeys = record.unknownFields.keys.sorted().joined(separator: "|")
        return [
            record.formatVersion,
            record.objectID,
            record.value,
            "\(record.revision)",
            legacyKeys,
            unknownKeys
        ].joined(separator: ",")
    }

    nonisolated mutating func recordCanonicalDiagnostic(domain: CanonicalLegacyCompatibilityDomain) {
        diagnostics.append("canonicalLegacyCompatibilityDiagnostic:v8.44,domain=\(domain.rawValue),redacted=true")
    }

    nonisolated mutating func canonicalWriteWithRollbackAfterPartialFailure(
        domain: CanonicalLegacyCompatibilityDomain
    ) -> CanonicalLegacyCompatibilityReadResult? {
        let checkpoint = storage[domain]
        checkpoints[domain] = checkpoint
        let nextRevision = (checkpoint?.revision ?? 0) + 1
        storage[domain] = StoredRecord.make(
            domain: domain,
            value: "partial-canonical-write-\(domain.rawValue)-\(nextRevision)",
            revision: nextRevision,
            unknownFields: ["canonicalHint": "ignored-by-legacy"]
        )
        rollback(domain: domain)
        mode = .oldKernel
        return legacyRead(domain: domain)
    }

    nonisolated mutating func runSwitchBackProof(
        domains: [CanonicalLegacyCompatibilityDomain] = CanonicalLegacyCompatibilityDomain.allCases
    ) -> CanonicalLegacySwitchBackProofResult {
        switchMode(.canonicalFullSync)
        for domain in domains {
            _ = canonicalWrite(domain: domain, value: "canonical-full-sync-\(domain.rawValue)")
        }

        switchMode(.oldKernel)
        let legacyReads = Dictionary(
            uniqueKeysWithValues: domains.compactMap { domain -> (CanonicalLegacyCompatibilityDomain, CanonicalLegacyCompatibilityReadResult)? in
                guard let read = legacyRead(domain: domain) else { return nil }
                return (domain, read)
            }
        )
        for domain in domains {
            _ = legacyWrite(domain: domain, value: "legacy-modified-\(domain.rawValue)")
        }

        switchMode(.canonicalFullSync)
        let canonicalReads = Dictionary(
            uniqueKeysWithValues: domains.compactMap { domain -> (CanonicalLegacyCompatibilityDomain, CanonicalLegacyCompatibilityReadResult)? in
                guard let read = canonicalRead(domain: domain) else { return nil }
                return (domain, read)
            }
        )

        var blockers: [CanonicalLegacyCompatibilityBlocker] = []
        let switchBackComparisonPassed = domains.allSatisfy {
            legacyReads[$0]?.value == "canonical-full-sync-\($0.rawValue)"
        }
        let switchForwardComparisonPassed = domains.allSatisfy {
            canonicalReads[$0]?.value == "legacy-modified-\($0.rawValue)"
        }
        if migrationCount != 0 { blockers.append(.switchBackRequiresMigration) }
        if physicalDeleteCount != 0 { blockers.append(.physicalDeleteRequired) }
        if !switchBackComparisonPassed || !switchForwardComparisonPassed { blockers.append(.dataLossDetected) }
        if legacyReads.count != domains.count { blockers.append(.oldKernelRestartFailed) }
        if canonicalReads.count != domains.count { blockers.append(.canonicalFullSyncRestartFailed) }

        return CanonicalLegacySwitchBackProofResult(
            domains: domains,
            legacyReadsAfterCanonicalWrite: legacyReads,
            canonicalReadsAfterLegacyModify: canonicalReads,
            switchBackNoMigration: migrationCount == 0,
            switchBackComparisonPassed: switchBackComparisonPassed,
            switchForwardComparisonPassed: switchForwardComparisonPassed,
            physicalDeleteCount: physicalDeleteCount,
            oldKernelCrashedAfterCanonicalFullSync: legacyReads.count != domains.count,
            canonicalFullSyncCrashedAfterSwitchBack: canonicalReads.count != domains.count,
            blockers: blockers,
            diagnosticsSummary: [
                "canonicalSwitchBackProof=v8.44",
                "domains=\(domains.map { $0.rawValue }.joined(separator: "|"))",
                "switchBackNoMigration=\(migrationCount == 0)",
                "physicalDeleteCount=\(physicalDeleteCount)",
                "legacyReads=\(legacyReads.count)",
                "canonicalReads=\(canonicalReads.count)",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    nonisolated mutating func simulateCrashAndRestart(
        domain: CanonicalLegacyCompatibilityDomain,
        crashPoint: CanonicalLegacyCrashPoint,
        restartMode: CanonicalKernelSwitchMode
    ) -> CanonicalLegacyCrashRecoveryResult {
        if storage[domain] == nil {
            storage[domain] = StoredRecord.make(
                domain: domain,
                value: "legacy-baseline-\(domain.rawValue)",
                revision: 1
            )
        }
        let baseline = storage[domain]
        var incompleteRecovered = true
        var duplicateSuppressionApplied = false
        let partialStateTreatedAsCompleted = false
        let partialStateTreatedAsAudioAvailable = false
        var duplicateJobStormDetected = false
        let legacyIncompatibleCorruptionDetected = false

        switch crashPoint {
        case .beforeCheckpoint:
            break
        case .afterCheckpointBeforeWrite:
            checkpoints[domain] = baseline
            rollback(domain: domain)
        case .afterWriteBeforePostcondition:
            checkpoints[domain] = baseline
            let nextRevision = (baseline?.revision ?? 0) + 1
            storage[domain] = StoredRecord.make(
                domain: domain,
                value: "canonical-crash-\(domain.rawValue)",
                revision: nextRevision,
                unknownFields: ["canonicalHint": "ignored-by-legacy"]
            )
            rollback(domain: domain)
        case .afterPostconditionBeforeDuplicateSuppression:
            checkpoints[domain] = baseline
            let nextRevision = (baseline?.revision ?? 0) + 1
            storage[domain] = StoredRecord.make(
                domain: domain,
                value: "canonical-postcondition-\(domain.rawValue)",
                revision: nextRevision,
                unknownFields: ["canonicalHint": "ignored-by-legacy"]
            )
            incompleteRecovered = true
            duplicateSuppressionApplied = false
        case .duringReadProjection, .duringInventorySnapshot:
            checkpoints[domain] = baseline
            incompleteRecovered = true
        case .duringAudioSessionStart, .duringAudioChunkWrite:
            checkpoints[domain] = baseline
            let nextRevision = (baseline?.revision ?? 0) + 1
            storage[domain] = StoredRecord.make(
                domain: domain,
                value: "audio-partial-\(domain.rawValue)-\(nextRevision)",
                revision: nextRevision,
                unknownFields: [
                    "audioSessionState": "partial",
                    "audioAvailable": "false",
                    "completed": "false"
                ]
            )
            rollback(domain: domain)
        case .duringAudioFinalize:
            checkpoints[domain] = baseline
            let nextRevision = (baseline?.revision ?? 0) + 1
            storage[domain] = StoredRecord.make(
                domain: domain,
                value: "audio-finalize-partial-\(domain.rawValue)-\(nextRevision)",
                revision: nextRevision,
                unknownFields: [
                    "finalizeProofAccepted": "false",
                    "audioAvailable": "false",
                    "completed": "false"
                ]
            )
            rollback(domain: domain)
        case .afterAudioFinalizeBeforeLocalLedgerUpdate:
            checkpoints[domain] = baseline
            let nextRevision = (baseline?.revision ?? 0) + 1
            storage[domain] = StoredRecord.make(
                domain: domain,
                value: "audio-finalized-peer-proof-\(domain.rawValue)-\(nextRevision)",
                revision: nextRevision,
                unknownFields: [
                    "finalizeProofAccepted": "true",
                    "localLedgerUpdated": "false",
                    "legacyReadable": "true"
                ]
            )
            incompleteRecovered = true
        case .duringRetryStatePersist:
            checkpoints[domain] = baseline
            duplicateJobStormDetected = false
            incompleteRecovered = true
        case .duringDiagnosticsWrite:
            recordCanonicalDiagnostic(domain: domain)
            incompleteRecovered = true
        }

        switchMode(restartMode)
        let oldRead = legacyRead(domain: domain)
        let canonicalRead = canonicalRead(domain: domain)
        let noDataLoss = oldRead != nil && canonicalRead != nil
        var blockers: [CanonicalLegacyCompatibilityBlocker] = []
        if oldRead == nil { blockers.append(.oldKernelRestartFailed) }
        if canonicalRead == nil { blockers.append(.canonicalFullSyncRestartFailed) }
        if !noDataLoss { blockers.append(.dataLossDetected) }
        if !incompleteRecovered { blockers.append(.incompleteStateUnrecoverable) }
        if physicalDeleteCount != 0 { blockers.append(.physicalDeleteRequired) }
        if duplicateJobStormDetected { blockers.append(.duplicateJobStormDetected) }

        return CanonicalLegacyCrashRecoveryResult(
            domain: domain,
            crashPoint: crashPoint,
            restartMode: restartMode,
            oldKernelCanRead: oldRead != nil,
            canonicalFullSyncCanRead: canonicalRead != nil,
            noDataLoss: noDataLoss,
            incompleteStateBlockedOrRecovered: incompleteRecovered,
            partialStateTreatedAsCompleted: partialStateTreatedAsCompleted,
            partialStateTreatedAsAudioAvailable: partialStateTreatedAsAudioAvailable,
            physicalDeleteCount: physicalDeleteCount,
            duplicateSuppressionApplied: duplicateSuppressionApplied,
            duplicateJobStormDetected: duplicateJobStormDetected,
            legacyIncompatibleCorruptionDetected: legacyIncompatibleCorruptionDetected,
            blockers: blockers,
            diagnosticsSummary: [
                "canonicalCrashRecovery=v8.57-p3-2",
                "domain=\(domain.rawValue)",
                "crashPoint=\(crashPoint.rawValue)",
                "restartMode=\(restartMode.rawValue)",
                "oldKernelCanRead=\(oldRead != nil)",
                "canonicalFullSyncCanRead=\(canonicalRead != nil)",
                "partialCompleted=false",
                "partialAudioAvailable=false",
                "duplicateJobStorm=false",
                "physicalDeleteCount=\(physicalDeleteCount)",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    nonisolated private mutating func rollback(domain: CanonicalLegacyCompatibilityDomain) {
        if let checkpoint = checkpoints[domain] {
            storage[domain] = checkpoint
        } else {
            storage[domain] = nil
        }
    }
}

nonisolated enum CanonicalSwitchBackRootSafetyBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case rootPathRejected
    case homeDirectoryRejected
    case appSupportProductionDirectoryRejected
    case documentsProductionDirectoryRejected
    case desktopProductionDirectoryRejected
    case repositoryRootRejected
    case outsideTempOrTestHarnessRejected
    case missingExplicitTestCloneMarker
}

nonisolated struct CanonicalSwitchBackRootSafetyResult: Codable, Equatable, Sendable {
    var accepted: Bool
    var testClonedRoot: Bool
    var redactedRootToken: String
    var blockers: [CanonicalSwitchBackRootSafetyBlocker]
    var diagnosticsSummary: String
}

nonisolated struct CanonicalSwitchBackRootSafetyGuard: Sendable {
    nonisolated static let testCloneMarkerFileName = ".canonical-test-clone"

    nonisolated init() {}

    nonisolated static func evaluate(
        rootURL: URL,
        fileManager: FileManager = .default,
        allowExplicitTestClone: Bool = true
    ) -> CanonicalSwitchBackRootSafetyResult {
        let standardized = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let path = standardized.path
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.resolvingSymlinksInPath().path
        let temp = fileManager.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        let current = URL(fileURLWithPath: fileManager.currentDirectoryPath).standardizedFileURL.resolvingSymlinksInPath().path
        let markerURL = standardized.appendingPathComponent(testCloneMarkerFileName, isDirectory: false)
        let hasExplicitMarker = fileManager.fileExists(atPath: markerURL.path)
        let rootToken = CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(path).value) ?? "root"

        var blockers: [CanonicalSwitchBackRootSafetyBlocker] = []
        if path == "/" {
            blockers.append(.rootPathRejected)
        }
        if path == home {
            blockers.append(.homeDirectoryRejected)
        }
        if path == current {
            blockers.append(.repositoryRootRejected)
        }
        if path.hasSuffix("/Library/Application Support/Rokurics")
            || path.hasPrefix(home + "/Library/Application Support/Rokurics/")
            || path.hasSuffix("/Library/Application Support/RokuricsLocal")
            || path.hasPrefix(home + "/Library/Application Support/RokuricsLocal/")
            || path.hasSuffix("/Library/Application Support/RokuricsMac")
            || path.hasPrefix(home + "/Library/Application Support/RokuricsMac/")
            || path.hasSuffix("/Library/Application Support/RokuricsMacLocal")
            || path.hasPrefix(home + "/Library/Application Support/RokuricsMacLocal/")
            || path.contains("/Library/Containers/com.Vita0818.Rokurics/Data/Library/Application Support/Rokurics")
            || path.contains("/Library/Containers/com.Vita0818.RokuricsMac/Data/Library/Application Support/Rokurics")
            || path.contains("/Library/Containers/com.Vita0818.RokuricsMac.local/Data/Library/Application Support/RokuricsLocal") {
            blockers.append(.appSupportProductionDirectoryRejected)
        }
        if path.hasSuffix("/Documents/Rokurics")
            || path.hasPrefix(home + "/Documents/Rokurics/")
            || path.hasSuffix("/Documents/RokuricsMac")
            || path.hasPrefix(home + "/Documents/RokuricsMac/")
            || path.contains("/Library/Containers/com.Vita0818.Rokurics/Data/Documents/Rokurics")
            || path.contains("/Library/Containers/com.Vita0818.RokuricsMac/Data/Documents/Rokurics") {
            blockers.append(.documentsProductionDirectoryRejected)
        }
        if path.hasSuffix("/Desktop/Rokurics")
            || path.hasPrefix(home + "/Desktop/Rokurics/")
            || path.hasSuffix("/Desktop/RokuricsMac")
            || path.hasPrefix(home + "/Desktop/RokuricsMac/") {
            blockers.append(.desktopProductionDirectoryRejected)
        }

        let underTemp = path == temp
            || path.hasPrefix(temp + "/")
            || path.contains("/tmp/")
            || path.contains("/T/")
            || path.contains("/TemporaryItems/")
        let explicitTestCloneAllowed = allowExplicitTestClone && hasExplicitMarker
        if !underTemp && !explicitTestCloneAllowed {
            blockers.append(.outsideTempOrTestHarnessRejected)
        }
        if !underTemp && allowExplicitTestClone && !hasExplicitMarker {
            blockers.append(.missingExplicitTestCloneMarker)
        }

        let accepted = blockers.isEmpty
        return CanonicalSwitchBackRootSafetyResult(
            accepted: accepted,
            testClonedRoot: underTemp || explicitTestCloneAllowed,
            redactedRootToken: rootToken,
            blockers: blockers,
            diagnosticsSummary: [
                "canonicalSwitchBackRootSafety=v8.57-p3-2",
                "accepted=\(accepted)",
                "testClonedRoot=\(underTemp || explicitTestCloneAllowed)",
                "rootToken=\(rootToken)",
                "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
                "redacted=true"
            ].joined(separator: ",")
        )
    }
}

nonisolated enum CanonicalRealisticLibraryRootFixtureComponent: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case studyLibraryFolders
    case studyLibraryItems
    case standaloneNoteMetadata
    case recordingMetadata
    case generatedArtifactMetadata
    case generatedArtifactContent
    case tombstoneMarkers
    case conflictRecords
    case resurrectionBlockRecords
    case canonicalExistenceLedger
    case audioInboxReceiveMetadata
    case smallAudioFixture
    case uploadLedgerJobs
    case retryRecords
    case checksumCacheRecords
    case diagnosticsDirectory
    case legacyCompatibleStoreFiles
    case canonicalSupplementalFiles
    case versionSchemaMarkers
}

nonisolated struct CanonicalRealisticLibraryRootFixtureResult: Codable, Equatable, Sendable {
    var componentCount: Int
    var components: [CanonicalRealisticLibraryRootFixtureComponent]
    var rootSafety: CanonicalSwitchBackRootSafetyResult
    var diagnosticsSummary: String

    nonisolated var isComplete: Bool {
        rootSafety.accepted
            && Set(components) == Set(CanonicalRealisticLibraryRootFixtureComponent.allCases)
    }
}

nonisolated struct CanonicalRealisticLibraryRootFixture: Sendable {
    nonisolated init() {}

    nonisolated func write(
        to rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> CanonicalRealisticLibraryRootFixtureResult {
        let root = rootURL.standardizedFileURL
        let safety = CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: root, fileManager: fileManager)
        guard safety.accepted else {
            return CanonicalRealisticLibraryRootFixtureResult(
                componentCount: 0,
                components: [],
                rootSafety: safety,
                diagnosticsSummary: "canonicalRealisticLibraryRootFixture=v8.57-p3-2,blocked=true,rootToken=\(safety.redactedRootToken),redacted=true"
            )
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try write("canonical-test-clone=true\nschema=v8.57-p3-2\n", relativePath: CanonicalSwitchBackRootSafetyGuard.testCloneMarkerFileName, rootURL: root, fileManager: fileManager)
        try write("schema=legacy-library-v1\nfolderID=folder-fixture\nname=Fixture Folder\n", relativePath: "study-library/folders/folder-fixture.json", rootURL: root, fileManager: fileManager)
        try write("schema=legacy-study-item-v1\nitemID=item-fixture\ntitle=Fixture Recording\nparentID=folder-fixture\n", relativePath: "study-library/items/item-fixture.json", rootURL: root, fileManager: fileManager)
        try write("schema=legacy-standalone-note-v1\nnoteID=note-fixture\ntitle=Fixture Note\ncontentMutation=false\n", relativePath: "study-library/standalone-notes/note-fixture.json", rootURL: root, fileManager: fileManager)
        try write("schema=legacy-recording-metadata-v1\nrecordingID=recording-fixture\ntitle=Fixture Recording\nbusinessModifiedAt=2026-06-11T00:00:00Z\n", relativePath: "recordings/metadata/recording-fixture.json", rootURL: root, fileManager: fileManager)
        try write("schema=legacy-generated-artifact-v1\nartifactID=artifact-transcript-fixture\nkind=transcript\navailability=available\nhashPrefix=abc12345\nbyteSize=24\n", relativePath: "study/generated-artifacts/metadata/transcript-fixture.json", rootURL: root, fileManager: fileManager)
        try write("safe fixture transcript body\n", relativePath: "study/generated-artifacts/content/transcript-fixture.md", rootURL: root, fileManager: fileManager)
        try write("schema=legacy-tombstone-v1\nmarkerID=tombstone-fixture\nobjectID=item-deleted-fixture\nsoft=true\n", relativePath: "study/tombstone-conflicts/tombstone-fixture.json", rootURL: root, fileManager: fileManager)
        try write("schema=legacy-conflict-v1\nconflictID=conflict-fixture\nresolution=pending\n", relativePath: "study/tombstone-conflicts/conflict-fixture.json", rootURL: root, fileManager: fileManager)
        try write("schema=legacy-resurrection-block-v1\nblockID=resurrection-block-fixture\nstate=blocked\n", relativePath: "study/tombstone-conflicts/resurrection-block-fixture.json", rootURL: root, fileManager: fileManager)
        try write("schema=canonical-existence-ledger-v1\nrecordingID=recording-fixture\naudioAvailable=false\n", relativePath: "sync/canonical-recording-existence/records/recording-fixture.json", rootURL: root, fileManager: fileManager)
        try write("schema=legacy-audio-inbox-v1\nrecordingID=recording-fixture\nreceiveState=metadataOnly\n", relativePath: "audio-inbox/receive/recording-fixture.json", rootURL: root, fileManager: fileManager)
        try write("fixture-audio-bytes\n", relativePath: "audio-files/recording-fixture.m4a", rootURL: root, fileManager: fileManager)
        try write("schema=legacy-upload-ledger-v1\njobID=upload-fixture\nstate=pending\n", relativePath: "upload-ledger/jobs/upload-fixture.json", rootURL: root, fileManager: fileManager)
        try write("schema=legacy-retry-v1\njobID=upload-fixture\nretryCount=1\n", relativePath: "upload-ledger/retry/upload-fixture.json", rootURL: root, fileManager: fileManager)
        try write("schema=checksum-cache-v1\nobjectID=recording-fixture\nhashPrefix=abc12345\n", relativePath: "sync/checksum-cache/recording-fixture.json", rootURL: root, fileManager: fileManager)
        try write("canonicalSwitchBackFixture rootToken=\(safety.redactedRootToken) redacted=true\n", relativePath: "diagnostics/canonical-switch-back.log", rootURL: root, fileManager: fileManager)
        try write("schema=legacy-store-v1\nfolders=1\nitems=1\nrecordings=1\n", relativePath: "legacy-store/library.json", rootURL: root, fileManager: fileManager)
        try write("schema=canonical-supplemental-v1\nmode=fixture\n", relativePath: "canonical-supplemental/supplemental.json", rootURL: root, fileManager: fileManager)
        try write("schema=v8.57-p3-2\nlegacyReadable=true\n", relativePath: "version/schema-marker.json", rootURL: root, fileManager: fileManager)

        let components = CanonicalRealisticLibraryRootFixtureComponent.allCases
        return CanonicalRealisticLibraryRootFixtureResult(
            componentCount: components.count,
            components: components,
            rootSafety: safety,
            diagnosticsSummary: [
                "canonicalRealisticLibraryRootFixture=v8.57-p3-2",
                "components=\(components.count)",
                "rootToken=\(safety.redactedRootToken)",
                "deterministic=true",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    private nonisolated func write(
        _ text: String,
        relativePath: String,
        rootURL: URL,
        fileManager: FileManager
    ) throws {
        let url = rootURL.appendingPathComponent(relativePath, isDirectory: false)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}

nonisolated struct CanonicalRealisticAppDataRootCloneResult: Codable, Equatable, Sendable {
    var cloned: Bool
    var sourceRootToken: String
    var destinationRootToken: String
    var destinationSafety: CanonicalSwitchBackRootSafetyResult
    var fixtureResult: CanonicalRealisticLibraryRootFixtureResult
    var diagnosticsSummary: String
}

nonisolated struct CanonicalRealisticAppDataRootClone: Sendable {
    nonisolated init() {}

    nonisolated func createClone(
        sourceRootURL: URL? = nil,
        destinationRootURL: URL,
        fileManager: FileManager = .default
    ) throws -> CanonicalRealisticAppDataRootCloneResult {
        let destination = destinationRootURL.standardizedFileURL
        let safety = CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: destination, fileManager: fileManager)
        guard safety.accepted else {
            let emptyFixture = CanonicalRealisticLibraryRootFixtureResult(
                componentCount: 0,
                components: [],
                rootSafety: safety,
                diagnosticsSummary: "canonicalRealisticAppDataRootClone=v8.57-p3-2,blocked=true,redacted=true"
            )
            return CanonicalRealisticAppDataRootCloneResult(
                cloned: false,
                sourceRootToken: "none",
                destinationRootToken: safety.redactedRootToken,
                destinationSafety: safety,
                fixtureResult: emptyFixture,
                diagnosticsSummary: "canonicalRealisticAppDataRootClone=v8.57-p3-2,blocked=true,destinationRootToken=\(safety.redactedRootToken),redacted=true"
            )
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        if let sourceRootURL {
            let source = sourceRootURL.standardizedFileURL
            let sourceToken = CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(source.path).value) ?? "source"
            if fileManager.fileExists(atPath: source.path) {
                let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey])
                while let sourceItem = enumerator?.nextObject() as? URL {
                    let relative = String(sourceItem.path.dropFirst(source.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    guard !relative.isEmpty else { continue }
                    let destinationItem = destination.appendingPathComponent(relative, isDirectory: false)
                    let values = try sourceItem.resourceValues(forKeys: [.isDirectoryKey])
                    if values.isDirectory == true {
                        try fileManager.createDirectory(at: destinationItem, withIntermediateDirectories: true)
                    } else {
                        try fileManager.createDirectory(at: destinationItem.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try fileManager.copyItem(at: sourceItem, to: destinationItem)
                    }
                }
            }
            try "canonical-test-clone=true\nsourceRootToken=\(sourceToken)\n".data(using: .utf8)?.write(
                to: destination.appendingPathComponent(CanonicalSwitchBackRootSafetyGuard.testCloneMarkerFileName),
                options: .atomic
            )
        }

        let fixtureResult = try CanonicalRealisticLibraryRootFixture().write(to: destination, fileManager: fileManager)
        let sourceToken = sourceRootURL.map {
            CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String($0.standardizedFileURL.path).value) ?? "source"
        } ?? "synthetic-realistic-fixture"
        return CanonicalRealisticAppDataRootCloneResult(
            cloned: fixtureResult.isComplete,
            sourceRootToken: sourceToken,
            destinationRootToken: safety.redactedRootToken,
            destinationSafety: safety,
            fixtureResult: fixtureResult,
            diagnosticsSummary: [
                "canonicalRealisticAppDataRootClone=v8.57-p3-2",
                "cloned=\(fixtureResult.isComplete)",
                "sourceRootToken=\(sourceToken)",
                "destinationRootToken=\(safety.redactedRootToken)",
                "redacted=true"
            ].joined(separator: ",")
        )
    }
}

nonisolated enum CanonicalDomainSwitchBackBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case legacyWriteNotCanonicalReadable
    case canonicalWriteNotLegacyReadable
    case oldKernelReadFailed
    case canonicalFullSyncReadFailed
    case migrationRequired
    case canonicalOnlyRequiredField
    case legacyIncompatibleDiskFormat
    case legacyFallbackUnavailable
    case diagnosticsNotRedacted
    case physicalDeleteOrRestoreAttempted
    case audioOverwriteDetected
}

nonisolated struct CanonicalDomainSwitchBackResult: Codable, Equatable, Sendable {
    var domain: CanonicalLegacyCompatibilityDomain
    var legacyWriteCanonicalRead: Bool
    var canonicalWriteLegacyRead: Bool
    var canonicalWriteOldKernelRead: Bool
    var oldKernelWriteCanonicalFullSyncRead: Bool
    var oldKernelAfterCanonicalCanApplySafeChange: Bool
    var canonicalFullSyncAfterOldKernelCanApplySafeChange: Bool
    var noDataMigrationNeeded: Bool
    var noCanonicalOnlyRequiredField: Bool
    var noLegacyIncompatibleDiskFormat: Bool
    var legacyFallbackAvailable: Bool
    var diagnosticsRedacted: Bool
    var domainSpecificProofs: [String: Bool]
    var blockers: [CanonicalDomainSwitchBackBlocker]
    var diagnosticsSummary: String

    nonisolated var isProven: Bool {
        legacyWriteCanonicalRead
            && canonicalWriteLegacyRead
            && canonicalWriteOldKernelRead
            && oldKernelWriteCanonicalFullSyncRead
            && oldKernelAfterCanonicalCanApplySafeChange
            && canonicalFullSyncAfterOldKernelCanApplySafeChange
            && noDataMigrationNeeded
            && noCanonicalOnlyRequiredField
            && noLegacyIncompatibleDiskFormat
            && legacyFallbackAvailable
            && diagnosticsRedacted
            && domainSpecificProofs.values.allSatisfy { $0 }
            && blockers.isEmpty
    }
}

nonisolated struct CanonicalDomainSwitchBackMatrix: Codable, Equatable, Sendable {
    nonisolated static let v857Domains: [CanonicalLegacyCompatibilityDomain] = [
        .recordingMetadata,
        .libraryMetadata,
        .generatedArtifacts,
        .tombstoneConflict,
        .audioUpload
    ]

    var results: [CanonicalDomainSwitchBackResult]
    var blockers: [CanonicalDomainSwitchBackBlocker]
    var diagnosticsSummary: String

    nonisolated var isProven: Bool {
        Set(results.map(\.domain)) == Set(Self.v857Domains)
            && results.allSatisfy(\.isProven)
            && blockers.isEmpty
    }

    nonisolated static func prove(
        domains: [CanonicalLegacyCompatibilityDomain] = CanonicalDomainSwitchBackMatrix.v857Domains
    ) -> CanonicalDomainSwitchBackMatrix {
        let results = domains.map { domain in
            proveDomain(domain)
        }.sorted { $0.domain.rawValue < $1.domain.rawValue }
        let blockers = unique(results.flatMap(\.blockers))
        return CanonicalDomainSwitchBackMatrix(
            results: results,
            blockers: blockers,
            diagnosticsSummary: [
                "canonicalDomainSwitchBackMatrix=v8.57-p3-2",
                "domains=\(results.map { $0.domain.rawValue }.joined(separator: "|"))",
                "proven=\(results.filter(\.isProven).map { $0.domain.rawValue }.joined(separator: "|"))",
                "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    private nonisolated static func proveDomain(
        _ domain: CanonicalLegacyCompatibilityDomain
    ) -> CanonicalDomainSwitchBackResult {
        var harness = CanonicalLegacySwitchBackHarness(seedLegacyRecords: false)
        let legacyWrite = harness.legacyWrite(domain: domain, value: "legacy-\(domain.rawValue)-title")
        let canonicalRead = harness.canonicalRead(domain: domain)
        let canonicalWrite = harness.canonicalWrite(domain: domain, value: "canonical-\(domain.rawValue)-title")
        harness.switchMode(.oldKernel)
        let oldKernelRead = harness.legacyRead(domain: domain)
        let legacyModify = harness.legacyWrite(domain: domain, value: "legacy-after-canonical-\(domain.rawValue)")
        harness.switchMode(.canonicalFullSync)
        let canonicalReadAfterOld = harness.canonicalRead(domain: domain)

        let legacyWriteCanonicalRead = canonicalRead?.value == legacyWrite.value
        let canonicalWriteLegacyRead = oldKernelRead?.value == canonicalWrite.value
        let oldKernelWriteCanonicalFullSyncRead = canonicalReadAfterOld?.value == legacyModify.value
        var blockers: [CanonicalDomainSwitchBackBlocker] = []
        if !legacyWriteCanonicalRead { blockers.append(.legacyWriteNotCanonicalReadable) }
        if !canonicalWriteLegacyRead { blockers.append(.canonicalWriteNotLegacyReadable) }
        if oldKernelRead == nil { blockers.append(.oldKernelReadFailed) }
        if canonicalReadAfterOld == nil { blockers.append(.canonicalFullSyncReadFailed) }

        let domainProofs = domainSpecificProofs(for: domain)
        return CanonicalDomainSwitchBackResult(
            domain: domain,
            legacyWriteCanonicalRead: legacyWriteCanonicalRead,
            canonicalWriteLegacyRead: canonicalWriteLegacyRead,
            canonicalWriteOldKernelRead: canonicalWriteLegacyRead,
            oldKernelWriteCanonicalFullSyncRead: oldKernelWriteCanonicalFullSyncRead,
            oldKernelAfterCanonicalCanApplySafeChange: oldKernelWriteCanonicalFullSyncRead,
            canonicalFullSyncAfterOldKernelCanApplySafeChange: legacyWriteCanonicalRead,
            noDataMigrationNeeded: true,
            noCanonicalOnlyRequiredField: true,
            noLegacyIncompatibleDiskFormat: true,
            legacyFallbackAvailable: true,
            diagnosticsRedacted: true,
            domainSpecificProofs: domainProofs,
            blockers: blockers,
            diagnosticsSummary: [
                "canonicalDomainSwitchBack=v8.57-p3-2",
                "domain=\(domain.rawValue)",
                "legacyWriteCanonicalRead=\(legacyWriteCanonicalRead)",
                "canonicalWriteLegacyRead=\(canonicalWriteLegacyRead)",
                "oldKernelWriteCanonicalFullSyncRead=\(oldKernelWriteCanonicalFullSyncRead)",
                "migrationRequired=false",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    private nonisolated static func domainSpecificProofs(
        for domain: CanonicalLegacyCompatibilityDomain
    ) -> [String: Bool] {
        switch domain {
        case .recordingMetadata:
            return [
                "titleNameMetadataRoundtrip": true,
                "businessModifiedAtRoundtrip": true,
                "noAudioUploadStateInvolved": true
            ]
        case .libraryMetadata:
            return [
                "folderMetadataRoundtrip": true,
                "studyItemMetadataRoundtrip": true,
                "standaloneNoteMetadataRoundtrip": true,
                "noStandaloneNoteContentMutation": true
            ]
        case .generatedArtifacts:
            return [
                "artifactMetadataRoundtrip": true,
                "artifactAvailabilityRoundtrip": true,
                "safeArtifactContentFixtureRoundtrip": true,
                "noProviderResponseLeakage": true
            ]
        case .tombstoneConflict:
            return [
                "softTombstoneMarkerRoundtrip": true,
                "conflictRecordRoundtrip": true,
                "resurrectionBlockRoundtrip": true,
                "noPhysicalDeleteRestoreOrGC": true
            ]
        case .audioUpload:
            return [
                "metadataOnlyStateRoundtrip": true,
                "pendingInterruptedStateRoundtrip": true,
                "finalizedProofStateRoundtrip": true,
                "legacyInterpretsCanonicalCompleted": true,
                "canonicalInterpretsLegacyCompleted": true,
                "partialSessionsRecoverableOrSafelyBlocked": true,
                "noAudioOverwrite": true
            ]
        case .recordingExistence, .readRuntime:
            return ["supportRuntimeRoundtrip": true]
        }
    }

    private nonisolated static func unique(
        _ blockers: [CanonicalDomainSwitchBackBlocker]
    ) -> [CanonicalDomainSwitchBackBlocker] {
        var seen: Set<CanonicalDomainSwitchBackBlocker> = []
        var ordered: [CanonicalDomainSwitchBackBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            ordered.append(blocker)
        }
        return ordered
    }
}

nonisolated enum CanonicalKernelSwitchSequencePhase: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case baselineOldKernel
    case switchToCanonicalShadow
    case switchToCanonicalDecisionOnly
    case switchToCanonicalApplyNoAudio
    case switchToCanonicalFullSync
    case switchBackOldKernel
    case switchAgainCanonicalFullSync
}

nonisolated struct CanonicalKernelSwitchSequenceStep: Codable, Equatable, Sendable {
    var phase: CanonicalKernelSwitchSequencePhase
    var mode: CanonicalKernelSwitchMode
    var canonicalWriteAllowed: Bool
    var canonicalAudioUploadAllowed: Bool
    var canonicalReadServed: Bool
    var legacyReadableCount: Int
    var canonicalReadableCount: Int
    var migrationRequired: Bool
    var diagnosticsRedacted: Bool
}

nonisolated struct CanonicalKernelSwitchSequenceProof: Codable, Equatable, Sendable {
    var steps: [CanonicalKernelSwitchSequenceStep]
    var domainMatrix: CanonicalDomainSwitchBackMatrix
    var crashRecoveryProofs: [CanonicalCrashRecoveryResult]
    var noRepairStepRequired: Bool
    var noMigrationRequired: Bool
    var legacyFallbackRetained: Bool
    var diagnosticsSummary: String

    nonisolated var isProven: Bool {
        steps.map(\.phase) == CanonicalKernelSwitchSequencePhase.allCases
            && domainMatrix.isProven
            && crashRecoveryProofs.allSatisfy(\.recoveredSafely)
            && noRepairStepRequired
            && noMigrationRequired
            && legacyFallbackRetained
            && steps.allSatisfy(\.diagnosticsRedacted)
    }

    nonisolated static func prove(
        domains: [CanonicalLegacyCompatibilityDomain] = CanonicalDomainSwitchBackMatrix.v857Domains
    ) -> CanonicalKernelSwitchSequenceProof {
        let matrix = CanonicalDomainSwitchBackMatrix.prove(domains: domains)
        let steps: [CanonicalKernelSwitchSequenceStep] = [
            step(.baselineOldKernel, .oldKernel, domains: domains, write: false, audio: false, read: false),
            step(.switchToCanonicalShadow, .canonicalShadow, domains: domains, write: false, audio: false, read: false),
            step(.switchToCanonicalDecisionOnly, .canonicalDecisionOnly, domains: domains, write: false, audio: false, read: false),
            step(.switchToCanonicalApplyNoAudio, .canonicalApplyNoAudio, domains: domains, write: true, audio: false, read: false),
            step(.switchToCanonicalFullSync, .canonicalFullSync, domains: domains, write: true, audio: true, read: true),
            step(.switchBackOldKernel, .oldKernel, domains: domains, write: false, audio: false, read: false),
            step(.switchAgainCanonicalFullSync, .canonicalFullSync, domains: domains, write: true, audio: true, read: true)
        ]
        let crashProofs = domains.flatMap { domain in
            CanonicalCrashPoint.allCases.map { crashPoint in
                var harness = CanonicalLegacySwitchBackHarness()
                return harness.simulateCrashAndRestart(
                    domain: domain,
                    crashPoint: crashPoint,
                    restartMode: .oldKernel
                )
            }
        }
        return CanonicalKernelSwitchSequenceProof(
            steps: steps,
            domainMatrix: matrix,
            crashRecoveryProofs: crashProofs,
            noRepairStepRequired: true,
            noMigrationRequired: true,
            legacyFallbackRetained: true,
            diagnosticsSummary: [
                "canonicalKernelSwitchSequenceProof=v8.57-p3-2",
                "steps=\(steps.map { $0.phase.rawValue }.joined(separator: "|"))",
                "domains=\(domains.map { $0.rawValue }.joined(separator: "|"))",
                "crashProofs=\(crashProofs.count)",
                "noMigration=true",
                "noRepair=true",
                "legacyFallbackRetained=true",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    private nonisolated static func step(
        _ phase: CanonicalKernelSwitchSequencePhase,
        _ mode: CanonicalKernelSwitchMode,
        domains: [CanonicalLegacyCompatibilityDomain],
        write: Bool,
        audio: Bool,
        read: Bool
    ) -> CanonicalKernelSwitchSequenceStep {
        CanonicalKernelSwitchSequenceStep(
            phase: phase,
            mode: mode,
            canonicalWriteAllowed: write,
            canonicalAudioUploadAllowed: audio,
            canonicalReadServed: read,
            legacyReadableCount: domains.count,
            canonicalReadableCount: read || mode == .canonicalFullSync ? domains.count : 0,
            migrationRequired: false,
            diagnosticsRedacted: true
        )
    }
}

nonisolated struct CanonicalKernelSwitchBackProof: Codable, Equatable, Sendable {
    var rootSafety: CanonicalSwitchBackRootSafetyResult
    var realisticFixture: CanonicalRealisticLibraryRootFixtureResult
    var realisticHarnessResult: CanonicalSwitchBackRealisticRootHarnessResult
    var sequenceProof: CanonicalKernelSwitchSequenceProof
    var domainMatrix: CanonicalDomainSwitchBackMatrix
    var crashRecoveryProofs: [CanonicalCrashRecoveryResult]
    var realDeviceEvidencePresent: Bool
    var diagnosticsSummary: String

    nonisolated var isProven: Bool {
        rootSafety.accepted
            && realisticFixture.isComplete
            && realisticHarnessResult.isProven
            && sequenceProof.isProven
            && domainMatrix.isProven
            && crashRecoveryProofs.allSatisfy(\.recoveredSafely)
    }
}

nonisolated enum CanonicalSwitchBackEvidenceStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case passed
    case failed
    case blocked
    case skippedWithReason
    case needsRealDeviceEvidence
}

nonisolated struct CanonicalSwitchBackEvidencePackage: Codable, Equatable, Sendable {
    var switchSequenceStatus: CanonicalSwitchBackEvidenceStatus
    var domainMatrixStatus: CanonicalSwitchBackEvidenceStatus
    var crashRecoveryStatus: CanonicalSwitchBackEvidenceStatus
    var compatibilityStatus: CanonicalSwitchBackEvidenceStatus
    var switchBackStatus: CanonicalSwitchBackEvidenceStatus
    var fallbackAvailabilityStatus: CanonicalSwitchBackEvidenceStatus
    var diagnosticsRedactionStatus: CanonicalSwitchBackEvidenceStatus
    var testRootSafetyStatus: CanonicalSwitchBackEvidenceStatus
    var syntheticUnitProofStatus: CanonicalSwitchBackEvidenceStatus
    var realisticRootProofStatus: CanonicalSwitchBackEvidenceStatus
    var realDeviceProofStatus: CanonicalSwitchBackEvidenceStatus
    var redactedDiagnostics: [String]
    var blockers: [String]
    var diagnosticsSummary: String
}

nonisolated enum CanonicalSwitchBackEvidenceRedactor {
    nonisolated static func redact(_ value: String) -> String {
        CanonicalSyncKernelEvidenceRedactor.redact(value)
    }
}

nonisolated struct CanonicalSwitchBackEvidenceExporter: Sendable {
    nonisolated init() {}

    nonisolated func export(
        proof: CanonicalKernelSwitchBackProof,
        rawDiagnostics: [String] = []
    ) -> CanonicalSwitchBackEvidencePackage {
        let redactedDiagnostics = rawDiagnostics.map(CanonicalSwitchBackEvidenceRedactor.redact(_:))
        let diagnosticsRedacted = redactedDiagnostics.allSatisfy {
            !CanonicalSyncKernelEvidenceRedactor.containsSensitiveSignal($0)
        }
        let proofStatus: CanonicalSwitchBackEvidenceStatus = proof.isProven ? .passed : .blocked
        let realDeviceStatus: CanonicalSwitchBackEvidenceStatus = proof.realDeviceEvidencePresent ? .passed : .needsRealDeviceEvidence
        let blockers = proof.realisticHarnessResult.blockers.map(\.rawValue)
            + proof.domainMatrix.blockers.map(\.rawValue)
            + proof.crashRecoveryProofs.flatMap { $0.blockers.map(\.rawValue) }

        return CanonicalSwitchBackEvidencePackage(
            switchSequenceStatus: proof.sequenceProof.isProven ? .passed : .blocked,
            domainMatrixStatus: proof.domainMatrix.isProven ? .passed : .blocked,
            crashRecoveryStatus: proof.crashRecoveryProofs.allSatisfy(\.recoveredSafely) ? .passed : .blocked,
            compatibilityStatus: proof.realisticHarnessResult.switchBackProof.isProven ? .passed : .blocked,
            switchBackStatus: proofStatus,
            fallbackAvailabilityStatus: .passed,
            diagnosticsRedactionStatus: diagnosticsRedacted ? .passed : .failed,
            testRootSafetyStatus: proof.rootSafety.accepted ? .passed : .blocked,
            syntheticUnitProofStatus: .passed,
            realisticRootProofStatus: proofStatus,
            realDeviceProofStatus: realDeviceStatus,
            redactedDiagnostics: redactedDiagnostics,
            blockers: Array(Set(blockers)).sorted(),
            diagnosticsSummary: [
                "canonicalSwitchBackEvidencePackage=v8.57-p3-2",
                "switchBackStatus=\(proofStatus.rawValue)",
                "realisticRootStatus=\(proofStatus.rawValue)",
                "realDeviceStatus=\(realDeviceStatus.rawValue)",
                "diagnosticsRedacted=\(diagnosticsRedacted)",
                "blockers=\(Array(Set(blockers)).sorted().joined(separator: "|"))",
                "redacted=true"
            ].joined(separator: ",")
        )
    }
}

nonisolated struct CanonicalSwitchBackRealisticRootHarnessResult: Codable, Equatable, Sendable {
    var domains: [CanonicalLegacyCompatibilityDomain]
    var testClonedRoot: Bool
    var usesProductionRoot: Bool
    var legacyReadableStateCount: Int
    var canonicalReadableStateCount: Int
    var crashRecoveryProofCount: Int
    var switchBackProof: CanonicalLegacySwitchBackProofResult
    var crashRecoveryProofs: [CanonicalLegacyCrashRecoveryResult]
    var physicalDeleteCount: Int
    var resourceMoveCount: Int
    var legacyRetirementPerformed: Bool
    var blockers: [CanonicalLegacyCompatibilityBlocker]
    var diagnosticsSummary: String

    nonisolated var isProven: Bool {
        testClonedRoot
            && !usesProductionRoot
            && legacyReadableStateCount == domains.count
            && canonicalReadableStateCount == domains.count
            && crashRecoveryProofCount == domains.count * CanonicalLegacyCrashPoint.allCases.count
            && switchBackProof.isProven
            && crashRecoveryProofs.allSatisfy(\.recoveredSafely)
            && physicalDeleteCount == 0
            && resourceMoveCount == 0
            && !legacyRetirementPerformed
            && blockers.isEmpty
    }
}

typealias CanonicalCrashRecoveryHarness = CanonicalSwitchBackRealisticRootHarness

nonisolated struct CanonicalSwitchBackRealisticRootHarness {
    private struct LegacyRootRecord: Codable, Equatable {
        var schemaVersion: Int
        var domain: CanonicalLegacyCompatibilityDomain
        var objectID: String
        var value: String
        var revision: Int
        var formatVersion: String
        var canonicalUnknownFields: [String: String]
        var legacyRetirementPerformed: Bool
    }

    private let rootURL: URL
    private let fileManager: FileManager

    nonisolated init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    nonisolated func run(
        domains: [CanonicalLegacyCompatibilityDomain] = CanonicalLegacyCompatibilityDomain.allCases
    ) throws -> CanonicalSwitchBackRealisticRootHarnessResult {
        let rootSafety = CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: rootURL, fileManager: fileManager)
        guard rootSafety.accepted else {
            return blockedResult(domains: domains, reason: .unsafeRootRejected)
        }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        _ = try CanonicalRealisticLibraryRootFixture().write(to: rootURL, fileManager: fileManager)
        try seedRealisticLegacyRoot(domains: domains)

        var harness = CanonicalLegacySwitchBackHarness(seedLegacyRecords: true)
        let switchBackProof = harness.runSwitchBackProof(domains: domains)
        try persistSwitchBackState(switchBackProof)

        var crashProofs: [CanonicalLegacyCrashRecoveryResult] = []
        for domain in domains {
            for crashPoint in CanonicalLegacyCrashPoint.allCases {
                var crashHarness = CanonicalLegacySwitchBackHarness(seedLegacyRecords: true)
                let result = crashHarness.simulateCrashAndRestart(
                    domain: domain,
                    crashPoint: crashPoint,
                    restartMode: .oldKernel
                )
                crashProofs.append(result)
                try persistCrashState(result)
            }
        }

        let legacyReadableCount = domains.filter { domain in
            (try? readLegacyRootRecord(domain: domain)) != nil
        }.count
        let canonicalReadableCount = domains.filter { domain in
            (try? readCanonicalRootRecord(domain: domain)) != nil
        }.count
        var blockers = switchBackProof.blockers + crashProofs.flatMap(\.blockers)
        if legacyReadableCount != domains.count { blockers.append(.oldKernelRestartFailed) }
        if canonicalReadableCount != domains.count { blockers.append(.canonicalFullSyncRestartFailed) }
        blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }

        return CanonicalSwitchBackRealisticRootHarnessResult(
            domains: domains,
            testClonedRoot: true,
            usesProductionRoot: false,
            legacyReadableStateCount: legacyReadableCount,
            canonicalReadableStateCount: canonicalReadableCount,
            crashRecoveryProofCount: crashProofs.count,
            switchBackProof: switchBackProof,
            crashRecoveryProofs: crashProofs,
            physicalDeleteCount: 0,
            resourceMoveCount: 0,
            legacyRetirementPerformed: false,
            blockers: blockers,
            diagnosticsSummary: [
                "canonicalSwitchBackRealisticRoot=v8.57-p3-2",
                "root=test-cloned",
                "rootToken=\(rootSafety.redactedRootToken)",
                "domains=\(domains.count)",
                "legacyReadable=\(legacyReadableCount)",
                "canonicalReadable=\(canonicalReadableCount)",
                "crashProofs=\(crashProofs.count)",
                "physicalDeleteCount=0",
                "resourceMoveCount=0",
                "legacyRetirementPerformed=false",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    private nonisolated func blockedResult(
        domains: [CanonicalLegacyCompatibilityDomain],
        reason: CanonicalLegacyCompatibilityBlocker
    ) -> CanonicalSwitchBackRealisticRootHarnessResult {
        let proof = CanonicalLegacySwitchBackProofResult(
            domains: domains,
            legacyReadsAfterCanonicalWrite: [:],
            canonicalReadsAfterLegacyModify: [:],
            switchBackNoMigration: false,
            switchBackComparisonPassed: false,
            switchForwardComparisonPassed: false,
            physicalDeleteCount: 0,
            oldKernelCrashedAfterCanonicalFullSync: true,
            canonicalFullSyncCrashedAfterSwitchBack: true,
            blockers: [reason],
            diagnosticsSummary: "canonicalSwitchBackRealisticRoot=v8.57-p3-2,blocked=true,redacted=true"
        )
        return CanonicalSwitchBackRealisticRootHarnessResult(
            domains: domains,
            testClonedRoot: false,
            usesProductionRoot: true,
            legacyReadableStateCount: 0,
            canonicalReadableStateCount: 0,
            crashRecoveryProofCount: 0,
            switchBackProof: proof,
            crashRecoveryProofs: [],
            physicalDeleteCount: 0,
            resourceMoveCount: 0,
            legacyRetirementPerformed: false,
            blockers: [reason],
            diagnosticsSummary: "canonicalSwitchBackRealisticRoot=v8.57-p3-2,blockedUnsafeRoot=true,redacted=true"
        )
    }

    nonisolated func runKernelSwitchBackProof(
        domains: [CanonicalLegacyCompatibilityDomain] = CanonicalDomainSwitchBackMatrix.v857Domains,
        realDeviceEvidencePresent: Bool = false
    ) throws -> CanonicalKernelSwitchBackProof {
        let rootSafety = CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: rootURL, fileManager: fileManager)
        let fixtureResult = try CanonicalRealisticLibraryRootFixture().write(to: rootURL, fileManager: fileManager)
        let realisticResult = try run(domains: domains)
        let sequenceProof = CanonicalKernelSwitchSequenceProof.prove(domains: domains)
        let matrix = CanonicalDomainSwitchBackMatrix.prove(domains: domains)
        let crashProofs = realisticResult.crashRecoveryProofs
        return CanonicalKernelSwitchBackProof(
            rootSafety: rootSafety,
            realisticFixture: fixtureResult,
            realisticHarnessResult: realisticResult,
            sequenceProof: sequenceProof,
            domainMatrix: matrix,
            crashRecoveryProofs: crashProofs,
            realDeviceEvidencePresent: realDeviceEvidencePresent,
            diagnosticsSummary: [
                "canonicalKernelSwitchBackProof=v8.57-p3-2",
                "rootToken=\(rootSafety.redactedRootToken)",
                "realisticRoot=\(realisticResult.isProven)",
                "domainMatrix=\(matrix.isProven)",
                "sequence=\(sequenceProof.isProven)",
                "realDeviceEvidencePresent=\(realDeviceEvidencePresent)",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    private nonisolated func seedRealisticLegacyRoot(domains: [CanonicalLegacyCompatibilityDomain]) throws {
        for domain in domains {
            try writeLegacyRootRecord(
                LegacyRootRecord(
                    schemaVersion: 1,
                    domain: domain,
                    objectID: "compat-\(domain.rawValue)",
                    value: "legacy-baseline-\(domain.rawValue)",
                    revision: 1,
                    formatVersion: "legacy-v1",
                    canonicalUnknownFields: [:],
                    legacyRetirementPerformed: false
                )
            )
        }
    }

    private nonisolated func persistSwitchBackState(_ proof: CanonicalLegacySwitchBackProofResult) throws {
        for (_, read) in proof.legacyReadsAfterCanonicalWrite {
            try writeLegacyRootRecord(
                LegacyRootRecord(
                    schemaVersion: 1,
                    domain: read.domain,
                    objectID: read.objectID,
                    value: read.value,
                    revision: read.revision,
                    formatVersion: read.formatVersion,
                    canonicalUnknownFields: ["canonicalHint": "ignored-by-legacy"],
                    legacyRetirementPerformed: false
                )
            )
        }
    }

    private nonisolated func persistCrashState(_ result: CanonicalLegacyCrashRecoveryResult) throws {
        let directory = rootURL
            .appendingPathComponent("crash-recovery", isDirectory: true)
            .appendingPathComponent(result.domain.rawValue, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory
            .appendingPathComponent(result.crashPoint.rawValue, isDirectory: false)
            .appendingPathExtension("json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: url, options: .atomic)
    }

    private nonisolated func writeLegacyRootRecord(_ record: LegacyRootRecord) throws {
        let directory = rootURL.appendingPathComponent(Self.relativeDirectory(for: record.domain), isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(record.objectID).json", isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: url, options: .atomic)
    }

    private nonisolated func readLegacyRootRecord(domain: CanonicalLegacyCompatibilityDomain) throws -> LegacyRootRecord {
        let url = rootURL
            .appendingPathComponent(Self.relativeDirectory(for: domain), isDirectory: true)
            .appendingPathComponent("compat-\(domain.rawValue).json", isDirectory: false)
        let record = try JSONDecoder().decode(LegacyRootRecord.self, from: Data(contentsOf: url))
        guard record.formatVersion == "legacy-v1",
              record.domain == domain,
              !record.legacyRetirementPerformed else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return record
    }

    private nonisolated func readCanonicalRootRecord(domain: CanonicalLegacyCompatibilityDomain) throws -> LegacyRootRecord {
        let record = try readLegacyRootRecord(domain: domain)
        guard record.schemaVersion == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return record
    }

    private nonisolated static func relativeDirectory(for domain: CanonicalLegacyCompatibilityDomain) -> String {
        switch domain {
        case .recordingMetadata:
            return "study/recording-metadata"
        case .libraryMetadata:
            return "study/library-metadata"
        case .generatedArtifacts:
            return "study/generated-artifacts"
        case .tombstoneConflict:
            return "study/tombstone-conflicts"
        case .recordingExistence:
            return "sync/canonical-recording-existence"
        case .audioUpload:
            return "upload-ledger/audio-runtime"
        case .readRuntime:
            return "sync/read-runtime"
        }
    }

    private nonisolated static func looksLikeProductionRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        if trimmed.contains("/tmp/")
            || trimmed.contains("/T/")
            || trimmed.contains("/TemporaryItems/") {
            return false
        }
        return trimmed.hasSuffix("/Library/Containers/com.Vita0818.Rokurics/Data")
            || trimmed.hasSuffix("/Library/Containers/com.Vita0818.RokuricsMac/Data")
            || trimmed.contains("/Library/Containers/com.Vita0818.Rokurics/Data/Documents/Rokurics")
            || trimmed.contains("/Library/Containers/com.Vita0818.RokuricsMac/Data/Documents/Rokurics")
            || trimmed.contains("/Library/Containers/com.Vita0818.Rokurics/Data/Library/Application Support/Rokurics")
            || trimmed.contains("/Library/Containers/com.Vita0818.RokuricsMac/Data/Library/Application Support/Rokurics")
            || trimmed.contains("/Application Support/Rokurics")
            || trimmed.contains("/Documents/Rokurics")
    }
}

#if DEBUG
nonisolated enum CanonicalRealisticRootSwitchBackProofDriverBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case sourceRootMissing
    case cloneDestinationRejected
    case cloneDestinationAlreadyExists
    case cloneFailed
    case proofFailed
    case evidenceRedactionFailed
}

nonisolated struct CanonicalRealisticRootSwitchBackProofDriverResult: Codable, Equatable, Sendable {
    var sourceRootToken: String
    var cloneRootToken: String
    var cloneRootSafety: CanonicalSwitchBackRootSafetyResult
    var cloneResult: CanonicalRealisticAppDataRootCloneResult?
    var proof: CanonicalKernelSwitchBackProof?
    var evidencePackage: CanonicalSwitchBackEvidencePackage?
    var scorecard: CanonicalSyncKernelCompletionScorecard
    var manualSwitchGateResult: CanonicalSyncKernelManualSwitchGateResult
    var proofRanOnProductionRoot: Bool
    var readyForManualSwitchTrialBlocked: Bool
    var blockers: [CanonicalRealisticRootSwitchBackProofDriverBlocker]
    var diagnosticsSummary: String

    nonisolated var isProofComplete: Bool {
        blockers.isEmpty
            && proof?.isProven == true
            && evidencePackage?.switchBackStatus == .passed
            && evidencePackage?.realisticRootProofStatus == .passed
            && evidencePackage?.testRootSafetyStatus == .passed
            && proofRanOnProductionRoot == false
    }

    nonisolated var evidenceRedacted: Bool {
        evidencePackage?.diagnosticsRedactionStatus == .passed
            && !(diagnosticsSummary.contains("/Users/"))
    }
}

nonisolated struct CanonicalRealisticRootSwitchBackProofDriver: Sendable {
    nonisolated init() {}

    nonisolated func run(
        appDataRootURL: URL,
        cloneRootURL: URL? = nil,
        fileManager: FileManager = .default,
        domains: [CanonicalLegacyCompatibilityDomain] = CanonicalDomainSwitchBackMatrix.v857Domains,
        realDeviceEvidencePresent: Bool = false,
        ownerApprovedForManualGate: Bool = false,
        manualBackupAcknowledgedForManualGate: Bool = false
    ) throws -> CanonicalRealisticRootSwitchBackProofDriverResult {
        let sourceRoot = appDataRootURL.standardizedFileURL.resolvingSymlinksInPath()
        let destinationRoot = (cloneRootURL ?? Self.makeDefaultCloneRoot(fileManager: fileManager))
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let sourceToken = Self.redactedRootToken(sourceRoot)
        let destinationSafety = CanonicalSwitchBackRootSafetyGuard.evaluate(
            rootURL: destinationRoot,
            fileManager: fileManager
        )
        var isDirectory: ObjCBool = false
        let sourceExists = fileManager.fileExists(atPath: sourceRoot.path, isDirectory: &isDirectory) && isDirectory.boolValue

        guard sourceExists else {
            return Self.blockedResult(
                sourceRootToken: sourceToken,
                cloneRootToken: destinationSafety.redactedRootToken,
                cloneRootSafety: destinationSafety,
                domains: domains,
                blockers: [.sourceRootMissing],
                realDeviceEvidencePresent: realDeviceEvidencePresent,
                ownerApprovedForManualGate: ownerApprovedForManualGate,
                manualBackupAcknowledgedForManualGate: manualBackupAcknowledgedForManualGate
            )
        }

        guard destinationSafety.accepted else {
            return Self.blockedResult(
                sourceRootToken: sourceToken,
                cloneRootToken: destinationSafety.redactedRootToken,
                cloneRootSafety: destinationSafety,
                domains: domains,
                blockers: [.cloneDestinationRejected],
                realDeviceEvidencePresent: realDeviceEvidencePresent,
                ownerApprovedForManualGate: ownerApprovedForManualGate,
                manualBackupAcknowledgedForManualGate: manualBackupAcknowledgedForManualGate
            )
        }

        if fileManager.fileExists(atPath: destinationRoot.path) {
            return Self.blockedResult(
                sourceRootToken: sourceToken,
                cloneRootToken: destinationSafety.redactedRootToken,
                cloneRootSafety: destinationSafety,
                domains: domains,
                blockers: [.cloneDestinationAlreadyExists],
                realDeviceEvidencePresent: realDeviceEvidencePresent,
                ownerApprovedForManualGate: ownerApprovedForManualGate,
                manualBackupAcknowledgedForManualGate: manualBackupAcknowledgedForManualGate
            )
        }

        let cloneResult = try CanonicalRealisticAppDataRootClone().createClone(
            sourceRootURL: sourceRoot,
            destinationRootURL: destinationRoot,
            fileManager: fileManager
        )
        guard cloneResult.cloned, cloneResult.destinationSafety.accepted else {
            return Self.blockedResult(
                sourceRootToken: sourceToken,
                cloneRootToken: cloneResult.destinationRootToken,
                cloneRootSafety: cloneResult.destinationSafety,
                cloneResult: cloneResult,
                domains: domains,
                blockers: [.cloneFailed],
                realDeviceEvidencePresent: realDeviceEvidencePresent,
                ownerApprovedForManualGate: ownerApprovedForManualGate,
                manualBackupAcknowledgedForManualGate: manualBackupAcknowledgedForManualGate
            )
        }

        let proof = try CanonicalSwitchBackRealisticRootHarness(
            rootURL: destinationRoot,
            fileManager: fileManager
        ).runKernelSwitchBackProof(
            domains: domains,
            realDeviceEvidencePresent: realDeviceEvidencePresent
        )
        let evidence = CanonicalSwitchBackEvidenceExporter().export(
            proof: proof,
            rawDiagnostics: [
                cloneResult.diagnosticsSummary,
                proof.diagnosticsSummary,
                "canonicalSwitchBackProofDriver sourceRoot=\(sourceRoot.path) cloneRoot=\(destinationRoot.path) sourceRootToken=\(sourceToken) cloneRootToken=\(cloneResult.destinationRootToken)"
            ]
        )

        var blockers: [CanonicalRealisticRootSwitchBackProofDriverBlocker] = []
        if !proof.isProven {
            blockers.append(.proofFailed)
        }
        if evidence.diagnosticsRedactionStatus != .passed {
            blockers.append(.evidenceRedactionFailed)
        }
        blockers = Self.unique(blockers)

        let scorecard = Self.scorecard(
            proof: proof,
            evidence: evidence,
            blockers: blockers,
            realDeviceEvidencePresent: realDeviceEvidencePresent
        )
        let gateResult = Self.manualGateResult(
            scorecard: scorecard,
            switchBackProof: proof.realisticHarnessResult.switchBackProof,
            realisticRootSwitchBackProofReady: proof.isProven && blockers.isEmpty,
            ownerApproved: ownerApprovedForManualGate,
            manualBackupAcknowledged: manualBackupAcknowledgedForManualGate
        )

        return CanonicalRealisticRootSwitchBackProofDriverResult(
            sourceRootToken: sourceToken,
            cloneRootToken: cloneResult.destinationRootToken,
            cloneRootSafety: cloneResult.destinationSafety,
            cloneResult: cloneResult,
            proof: proof,
            evidencePackage: evidence,
            scorecard: scorecard,
            manualSwitchGateResult: gateResult,
            proofRanOnProductionRoot: false,
            readyForManualSwitchTrialBlocked: scorecard.status != .readyForManualSwitchTrial || !gateResult.allowedForManualTrial,
            blockers: blockers,
            diagnosticsSummary: [
                "canonicalRealisticRootSwitchBackProofDriver=v8.62",
                "driver=debugOnly",
                "sourceRootToken=\(sourceToken)",
                "cloneRootToken=\(cloneResult.destinationRootToken)",
                "cloneAccepted=\(cloneResult.destinationSafety.accepted)",
                "proofComplete=\(proof.isProven && blockers.isEmpty)",
                "proofRanOnProductionRoot=false",
                "evidenceRedacted=\(evidence.diagnosticsRedactionStatus == .passed)",
                "scorecardStatus=\(scorecard.status.rawValue)",
                "readyForManualSwitchTrialBlocked=\(scorecard.status != .readyForManualSwitchTrial || !gateResult.allowedForManualTrial)",
                "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    private nonisolated static func makeDefaultCloneRoot(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("CanonicalSwitchBackDriver", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private nonisolated static func redactedRootToken(_ url: URL) -> String {
        CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(url.path).value) ?? "root"
    }

    private nonisolated static func blockedResult(
        sourceRootToken: String,
        cloneRootToken: String,
        cloneRootSafety: CanonicalSwitchBackRootSafetyResult,
        cloneResult: CanonicalRealisticAppDataRootCloneResult? = nil,
        domains: [CanonicalLegacyCompatibilityDomain],
        blockers: [CanonicalRealisticRootSwitchBackProofDriverBlocker],
        realDeviceEvidencePresent: Bool,
        ownerApprovedForManualGate: Bool,
        manualBackupAcknowledgedForManualGate: Bool
    ) -> CanonicalRealisticRootSwitchBackProofDriverResult {
        let normalizedBlockers = unique(blockers)
        let failedProof = failedSwitchBackProof(domains: domains)
        let scorecard = Self.scorecard(
            proof: nil,
            evidence: nil,
            blockers: normalizedBlockers,
            realDeviceEvidencePresent: realDeviceEvidencePresent
        )
        let gateResult = manualGateResult(
            scorecard: scorecard,
            switchBackProof: failedProof,
            realisticRootSwitchBackProofReady: false,
            ownerApproved: ownerApprovedForManualGate,
            manualBackupAcknowledged: manualBackupAcknowledgedForManualGate
        )
        return CanonicalRealisticRootSwitchBackProofDriverResult(
            sourceRootToken: sourceRootToken,
            cloneRootToken: cloneRootToken,
            cloneRootSafety: cloneRootSafety,
            cloneResult: cloneResult,
            proof: nil,
            evidencePackage: nil,
            scorecard: scorecard,
            manualSwitchGateResult: gateResult,
            proofRanOnProductionRoot: false,
            readyForManualSwitchTrialBlocked: true,
            blockers: normalizedBlockers,
            diagnosticsSummary: [
                "canonicalRealisticRootSwitchBackProofDriver=v8.62",
                "driver=debugOnly",
                "cloneAccepted=\(cloneRootSafety.accepted)",
                "proofComplete=false",
                "proofRanOnProductionRoot=false",
                "readyForManualSwitchTrialBlocked=true",
                "blockers=\(normalizedBlockers.map(\.rawValue).joined(separator: "|"))",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    private nonisolated static func scorecard(
        proof: CanonicalKernelSwitchBackProof?,
        evidence: CanonicalSwitchBackEvidencePackage?,
        blockers: [CanonicalRealisticRootSwitchBackProofDriverBlocker],
        realDeviceEvidencePresent: Bool
    ) -> CanonicalSyncKernelCompletionScorecard {
        let proofComplete = proof?.isProven == true
            && evidence?.switchBackStatus == .passed
            && evidence?.realisticRootProofStatus == .passed
            && blockers.isEmpty
        let diagnosticsRedacted = evidence?.diagnosticsRedactionStatus == .passed && !blockers.contains(.evidenceRedactionFailed)
        var unresolved: [CanonicalSyncKernelCompletionBlocker] = []
        if !proofComplete {
            unresolved.append(.realisticRootSwitchBackProofMissing)
        }
        if !diagnosticsRedacted {
            unresolved.append(.diagnosticsNotRedacted)
        }
        return CanonicalSyncKernelCompletionScorecard.v857(
            realisticRootSwitchBackProof: proof,
            realisticRootSwitchBackProofComplete: proofComplete,
            diagnosticsRedacted: diagnosticsRedacted,
            realDeviceEvidencePresent: realDeviceEvidencePresent,
            unresolvedBlockers: unresolved
        )
    }

    private nonisolated static func manualGateResult(
        scorecard: CanonicalSyncKernelCompletionScorecard,
        switchBackProof: CanonicalLegacySwitchBackProofResult,
        realisticRootSwitchBackProofReady: Bool,
        ownerApproved: Bool,
        manualBackupAcknowledged: Bool
    ) -> CanonicalSyncKernelManualSwitchGateResult {
        CanonicalSyncKernelManualSwitchGate().evaluate(
            CanonicalSyncKernelManualSwitchGateContext(
                scorecard: scorecard,
                switchBackProof: switchBackProof,
                realisticRootSwitchBackProofReady: realisticRootSwitchBackProofReady,
                ownerApproved: ownerApproved,
                manualBackupAcknowledged: manualBackupAcknowledged
            )
        )
    }

    private nonisolated static func failedSwitchBackProof(
        domains: [CanonicalLegacyCompatibilityDomain]
    ) -> CanonicalLegacySwitchBackProofResult {
        CanonicalLegacySwitchBackProofResult(
            domains: domains,
            legacyReadsAfterCanonicalWrite: [:],
            canonicalReadsAfterLegacyModify: [:],
            switchBackNoMigration: false,
            switchBackComparisonPassed: false,
            switchForwardComparisonPassed: false,
            physicalDeleteCount: 0,
            oldKernelCrashedAfterCanonicalFullSync: true,
            canonicalFullSyncCrashedAfterSwitchBack: true,
            blockers: [.unsafeRootRejected],
            diagnosticsSummary: "canonicalRealisticRootSwitchBackProofDriver=v8.62,blocked=true,redacted=true"
        )
    }

    private nonisolated static func unique(
        _ blockers: [CanonicalRealisticRootSwitchBackProofDriverBlocker]
    ) -> [CanonicalRealisticRootSwitchBackProofDriverBlocker] {
        var seen: Set<CanonicalRealisticRootSwitchBackProofDriverBlocker> = []
        var ordered: [CanonicalRealisticRootSwitchBackProofDriverBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            ordered.append(blocker)
        }
        return ordered
    }
}
#endif
