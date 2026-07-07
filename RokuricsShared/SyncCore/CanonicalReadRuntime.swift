//
//  CanonicalReadRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/7.
//

import Foundation

nonisolated enum CanonicalReadProjectionSource: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case legacy
    case canonical
}

nonisolated enum CanonicalReadDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingMetadata
    case libraryMetadata
    case generatedArtifacts
    case tombstoneConflict
    case audioUploadStatus
    case syncEngineStatus
}

nonisolated enum CanonicalReadRuntimeMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case parallelCompare
    case canonicalReadCandidate
    case guardedCanonicalReadWithLegacyFallback
    case blocked

    nonisolated var buildsCanonicalCandidate: Bool {
        switch self {
        case .disabled, .blocked:
            return false
        case .parallelCompare, .canonicalReadCandidate, .guardedCanonicalReadWithLegacyFallback:
            return true
        }
    }
}

nonisolated struct CanonicalReadRuntimePolicy: Codable, Equatable, Sendable {
    var debugInternalBuild: Bool
    var ownerApproved: Bool
    var manualOwnerApproval: Bool
    var releaseDefaultBuild: Bool
    var legacyFallbackAvailable: Bool
    var diagnosticsRedacted: Bool
    var applyRuntimeEvidenceValidForNonAudio: Bool
    var uploadRuntimeEvidenceValidForAudioStatus: Bool
    var inventorySnapshotAvailable: Bool
    var planAuthorityEvidenceValid: Bool
    var existenceTruthEvidenceValid: Bool
    var otherDomainsNotConflicting: Bool
    var allowDivergentGuardedReadForTests: Bool
    var readMustNotTriggerSyncUpload: Bool
    var readMustNotMutateStore: Bool
    var maxDiagnosticsEvents: Int

    nonisolated init(
        debugInternalBuild: Bool = false,
        ownerApproved: Bool = false,
        manualOwnerApproval: Bool = false,
        releaseDefaultBuild: Bool = true,
        legacyFallbackAvailable: Bool = true,
        diagnosticsRedacted: Bool = true,
        applyRuntimeEvidenceValidForNonAudio: Bool = false,
        uploadRuntimeEvidenceValidForAudioStatus: Bool = false,
        inventorySnapshotAvailable: Bool = false,
        planAuthorityEvidenceValid: Bool = false,
        existenceTruthEvidenceValid: Bool = false,
        otherDomainsNotConflicting: Bool = true,
        allowDivergentGuardedReadForTests: Bool = false,
        readMustNotTriggerSyncUpload: Bool = true,
        readMustNotMutateStore: Bool = true,
        maxDiagnosticsEvents: Int = 64
    ) {
        self.debugInternalBuild = debugInternalBuild
        self.ownerApproved = ownerApproved
        self.manualOwnerApproval = manualOwnerApproval
        self.releaseDefaultBuild = releaseDefaultBuild
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.diagnosticsRedacted = diagnosticsRedacted
        self.applyRuntimeEvidenceValidForNonAudio = applyRuntimeEvidenceValidForNonAudio
        self.uploadRuntimeEvidenceValidForAudioStatus = uploadRuntimeEvidenceValidForAudioStatus
        self.inventorySnapshotAvailable = inventorySnapshotAvailable
        self.planAuthorityEvidenceValid = planAuthorityEvidenceValid
        self.existenceTruthEvidenceValid = existenceTruthEvidenceValid
        self.otherDomainsNotConflicting = otherDomainsNotConflicting
        self.allowDivergentGuardedReadForTests = allowDivergentGuardedReadForTests
        self.readMustNotTriggerSyncUpload = readMustNotTriggerSyncUpload
        self.readMustNotMutateStore = readMustNotMutateStore
        self.maxDiagnosticsEvents = max(0, maxDiagnosticsEvents)
    }

    nonisolated static func explicitGuardedDebugInternal(
        allowDivergentGuardedReadForTests: Bool = false
    ) -> CanonicalReadRuntimePolicy {
        CanonicalReadRuntimePolicy(
            debugInternalBuild: true,
            ownerApproved: true,
            manualOwnerApproval: true,
            releaseDefaultBuild: false,
            legacyFallbackAvailable: true,
            diagnosticsRedacted: true,
            applyRuntimeEvidenceValidForNonAudio: true,
            uploadRuntimeEvidenceValidForAudioStatus: true,
            inventorySnapshotAvailable: true,
            planAuthorityEvidenceValid: true,
            existenceTruthEvidenceValid: true,
            otherDomainsNotConflicting: true,
            allowDivergentGuardedReadForTests: allowDivergentGuardedReadForTests
        )
    }
}

nonisolated struct CanonicalReadRuntimeConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalReadRuntimeMode
    var policy: CanonicalReadRuntimePolicy

    nonisolated init(
        mode: CanonicalReadRuntimeMode = .disabled,
        policy: CanonicalReadRuntimePolicy = CanonicalReadRuntimePolicy()
    ) {
        self.mode = mode
        self.policy = policy
    }

    nonisolated static let disabled = CanonicalReadRuntimeConfiguration()

    nonisolated static func explicitGuardedCanonicalRead(
        allowDivergentGuardedReadForTests: Bool = false
    ) -> CanonicalReadRuntimeConfiguration {
        CanonicalReadRuntimeConfiguration(
            mode: .guardedCanonicalReadWithLegacyFallback,
            policy: .explicitGuardedDebugInternal(
                allowDivergentGuardedReadForTests: allowDivergentGuardedReadForTests
            )
        )
    }
}

nonisolated enum CanonicalReadProjectionFailureKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case snapshotMissing
    case unsupportedObject
    case pathContentLeakRisk
}

nonisolated struct CanonicalReadProjectionFailure: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, domain.rawValue, objectID ?? "run", reason].joined(separator: "|") }

    var kind: CanonicalReadProjectionFailureKind
    var domain: CanonicalReadDomain
    var objectID: String?
    var reason: String

    nonisolated init(
        kind: CanonicalReadProjectionFailureKind,
        domain: CanonicalReadDomain,
        objectID: String? = nil,
        reason: String
    ) {
        self.kind = kind
        self.domain = domain
        self.objectID = objectID.map { CanonicalReadRuntimeRedaction.safeIdentifier($0, fallback: "object") }
        self.reason = CanonicalReadRuntimeRedaction.safeText(reason) ?? kind.rawValue
    }
}

nonisolated struct CanonicalRecordingReadProjectionRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { objectID }

    var objectID: String
    var title: String
    var tags: [String]
    var filingSummary: String
    var createdAtSummary: String
    var modifiedAtSummary: String
    var durationSeconds: Int?
    var metadataHashPrefix: String?
    var isDeleted: Bool
    var syncState: CanonicalSyncState
    var processingSummary: String

    nonisolated init(object: CanonicalRecordingObject) {
        self.init(
            objectID: object.objectID,
            title: object.metadata.title,
            tags: object.metadata.tags,
            filingSummary: Self.filingSummary(object.metadata.filing),
            createdAt: object.metadata.createdAt,
            modifiedAt: object.metadata.modifiedAt,
            duration: object.metadata.duration,
            metadataHashPrefix: CanonicalReadRuntimeRedaction.hashPrefix(object.metadataHash.value),
            isDeleted: object.metadata.isDeleted,
            syncState: object.syncState,
            processingSummary: "transcription=\(object.processingState.transcription.rawValue),note=\(object.processingState.note.rawValue)"
        )
    }

    nonisolated init(
        objectID: String,
        title: String,
        tags: [String] = [],
        filingSummary: String = "none",
        createdAt: CanonicalTimestamp,
        modifiedAt: CanonicalTimestamp,
        duration: TimeInterval? = nil,
        metadataHashPrefix: String? = nil,
        isDeleted: Bool = false,
        syncState: CanonicalSyncState = .unknown,
        processingSummary: String = "unknown"
    ) {
        self.objectID = CanonicalReadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.title = CanonicalReadRuntimeRedaction.safeDisplayText(title, fallback: "Untitled")
        self.tags = tags.compactMap { CanonicalReadRuntimeRedaction.safeDisplayText($0, fallback: "") }.filter { !$0.isEmpty }.sorted()
        self.filingSummary = CanonicalReadRuntimeRedaction.safeText(filingSummary) ?? "none"
        self.createdAtSummary = Self.timestampSummary(createdAt)
        self.modifiedAtSummary = Self.timestampSummary(modifiedAt)
        self.durationSeconds = duration.map { max(0, Int($0.rounded())) }
        self.metadataHashPrefix = CanonicalReadRuntimeRedaction.hashPrefix(metadataHashPrefix)
        self.isDeleted = isDeleted
        self.syncState = syncState
        self.processingSummary = CanonicalReadRuntimeRedaction.safeText(processingSummary) ?? "unknown"
    }

    nonisolated var tagsKey: String {
        tags.joined(separator: "|")
    }

    private nonisolated static func filingSummary(_ filing: CanonicalRecordingMetadata.Filing?) -> String {
        guard let filing else {
            return "none"
        }
        let summary = [
            filing.type.map { "type=\($0)" },
            filing.subject.map { "subject=\($0)" },
            filing.chapter.map { "chapter=\($0)" },
            filing.topic.map { "topic=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
        return summary.isEmpty ? "none" : summary
    }

    private nonisolated static func timestampSummary(_ timestamp: CanonicalTimestamp) -> String {
        "unixSeconds=\(Int(timestamp.date.timeIntervalSince1970))"
    }
}

nonisolated struct CanonicalRecordingReadProjection: Codable, Equatable, Sendable {
    var source: CanonicalReadProjectionSource
    var records: [CanonicalRecordingReadProjectionRecord]
    var failures: [CanonicalReadProjectionFailure]

    nonisolated init(
        source: CanonicalReadProjectionSource,
        records: [CanonicalRecordingReadProjectionRecord] = [],
        failures: [CanonicalReadProjectionFailure] = []
    ) {
        self.source = source
        self.records = records.sorted { $0.objectID < $1.objectID }
        self.failures = failures.sorted { $0.id < $1.id }
    }

    nonisolated static func build(
        source: CanonicalReadProjectionSource,
        manifest: CanonicalManifest?
    ) -> CanonicalRecordingReadProjection {
        guard let manifest else {
            return CanonicalRecordingReadProjection(
                source: source,
                failures: [
                    CanonicalReadProjectionFailure(
                        kind: .snapshotMissing,
                        domain: .recordingMetadata,
                        reason: "recordingManifestMissing"
                    )
                ]
            )
        }
        return CanonicalRecordingReadProjection(
            source: source,
            records: manifest.objects.map(CanonicalRecordingReadProjectionRecord.init(object:))
        )
    }

    nonisolated var diagnosticsSummary: String {
        "source=\(source.rawValue),records=\(records.count),failures=\(failures.count)"
    }
}

nonisolated struct CanonicalLibraryReadProjection: Codable, Equatable, Sendable {
    var source: CanonicalReadProjectionSource
    var snapshot: CanonicalLibraryMetadataReadSnapshot

    nonisolated init(source: CanonicalReadProjectionSource, snapshot: CanonicalLibraryMetadataReadSnapshot) {
        self.source = source
        self.snapshot = snapshot
    }

    nonisolated static func build(
        source: CanonicalReadProjectionSource,
        manifest: CanonicalManifest?
    ) -> CanonicalLibraryReadProjection {
        CanonicalLibraryReadProjection(
            source: source,
            snapshot: CanonicalLibraryMetadataReadProjection.build(
                source: source.libraryMetadataSource,
                manifest: manifest
            ).snapshot
        )
    }
}

nonisolated struct CanonicalArtifactReadProjection: Codable, Equatable, Sendable {
    var source: CanonicalReadProjectionSource
    var snapshot: CanonicalGeneratedArtifactReadSnapshot

    nonisolated init(source: CanonicalReadProjectionSource, snapshot: CanonicalGeneratedArtifactReadSnapshot) {
        self.source = source
        self.snapshot = snapshot
    }

    nonisolated static func build(
        source: CanonicalReadProjectionSource,
        localManifest: CanonicalManifest?,
        peerManifest: CanonicalManifest? = nil
    ) -> CanonicalArtifactReadProjection {
        var facts: [CanonicalGeneratedArtifactReadProjectionArtifactFact] = []
        if let localManifest {
            facts.append(contentsOf: generatedArtifactFacts(from: localManifest, peerAuthoritative: false))
        }
        if let peerManifest {
            facts.append(contentsOf: generatedArtifactFacts(from: peerManifest, peerAuthoritative: true))
        }
        let failures: [CanonicalGeneratedArtifactReadProjectionFailure] = (localManifest == nil && peerManifest == nil)
            ? [
                CanonicalGeneratedArtifactReadProjectionFailure(
                    kind: .snapshotMissing,
                    source: source.generatedArtifactSource,
                    reason: "generatedArtifactReadProjectionSnapshotMissing"
                )
            ]
            : []
        return CanonicalArtifactReadProjection(
            source: source,
            snapshot: CanonicalGeneratedArtifactReadProjection.snapshot(
                source: source.generatedArtifactSource,
                facts: facts,
                failures: failures
            )
        )
    }

    private nonisolated static func generatedArtifactFacts(
        from manifest: CanonicalManifest,
        peerAuthoritative: Bool
    ) -> [CanonicalGeneratedArtifactReadProjectionArtifactFact] {
        manifest.objects.flatMap { object in
            object.artifacts
                .filter(\.isCanonicalGeneratedArtifact)
                .map { artifact in
                    CanonicalGeneratedArtifactReadProjectionArtifactFact(
                        artifact: artifact,
                        parentTombstoned: object.metadata.isDeleted || object.syncState == .deleted,
                        localAvailability: !peerAuthoritative && CanonicalProjectionContract.provesGeneratedArtifactAvailability(artifact),
                        peerAuthoritativeAvailability: peerAuthoritative && CanonicalProjectionContract.isAuthoritativeProducer(artifact, node: manifest.node),
                        producerSummary: artifact.producedBy?.rawValue ?? manifest.node.platform,
                        unsafePathTokenObserved: false
                    )
                }
        }
    }
}

nonisolated struct CanonicalConflictReadProjection: Codable, Equatable, Sendable {
    var source: CanonicalReadProjectionSource
    var snapshot: CanonicalTombstoneConflictReadSnapshot

    nonisolated init(source: CanonicalReadProjectionSource, snapshot: CanonicalTombstoneConflictReadSnapshot) {
        self.source = source
        self.snapshot = snapshot
    }

    nonisolated static func build(
        source: CanonicalReadProjectionSource,
        localManifest: CanonicalManifest?,
        peerManifest: CanonicalManifest? = nil,
        applyPlan: CanonicalApplyPlan? = nil,
        libraryPlan: CanonicalLibrarySyncPlan? = nil
    ) -> CanonicalConflictReadProjection {
        CanonicalConflictReadProjection(
            source: source,
            snapshot: CanonicalTombstoneConflictReadProjection.snapshot(
                source: source.tombstoneConflictSource,
                localManifest: localManifest,
                peerManifest: peerManifest,
                applyPlan: applyPlan,
                libraryPlan: libraryPlan
            )
        )
    }
}

nonisolated struct CanonicalUploadReadProjectionRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { objectID }

    var objectID: String
    var audioAvailable: Bool
    var audioAvailability: CanonicalArtifact.Availability
    var byteSize: Int64?
    var audioHashPrefix: String?
    var peerState: CanonicalAudioUploadPeerState?
    var uploadAction: CanonicalAudioUploadActionKind?
    var uploadEvidenceStatus: CanonicalAudioUploadEvidenceStatus?
    var uploadLedgerPhase: CanonicalAudioUploadLedgerPhase?
    var retryEligible: Bool
    var createdUploadJob: Bool
    var pathIncluded: Bool
    var contentIncluded: Bool

    nonisolated init(
        objectID: String,
        audioAvailable: Bool,
        audioAvailability: CanonicalArtifact.Availability,
        byteSize: Int64? = nil,
        audioHashPrefix: String? = nil,
        peerState: CanonicalAudioUploadPeerState? = nil,
        uploadAction: CanonicalAudioUploadActionKind? = nil,
        uploadEvidenceStatus: CanonicalAudioUploadEvidenceStatus? = nil,
        uploadLedgerPhase: CanonicalAudioUploadLedgerPhase? = nil,
        retryEligible: Bool = false
    ) {
        self.objectID = CanonicalReadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.audioAvailable = audioAvailable
        self.audioAvailability = audioAvailability
        self.byteSize = byteSize
        self.audioHashPrefix = CanonicalReadRuntimeRedaction.hashPrefix(audioHashPrefix)
        self.peerState = peerState
        self.uploadAction = uploadAction
        self.uploadEvidenceStatus = uploadEvidenceStatus
        self.uploadLedgerPhase = uploadLedgerPhase
        self.retryEligible = retryEligible
        self.createdUploadJob = false
        self.pathIncluded = false
        self.contentIncluded = false
    }

    nonisolated init(object: CanonicalRecordingObject, candidate: CanonicalAudioUploadCutoverCandidate?) {
        let audio = object.audioArtifact
        self.init(
            objectID: object.objectID,
            audioAvailable: object.audioAvailable,
            audioAvailability: audio?.availability ?? .missing,
            byteSize: audio?.byteSize,
            audioHashPrefix: audio?.contentHash?.value,
            peerState: candidate?.peerTruth.state,
            uploadAction: candidate?.actionKind,
            uploadEvidenceStatus: candidate?.evidenceStatus,
            uploadLedgerPhase: candidate?.ledgerTruth.phase,
            retryEligible: candidate?.retryTruth.hasExistingEligibleRetry == true
        )
    }
}

nonisolated struct CanonicalUploadReadProjection: Codable, Equatable, Sendable {
    var source: CanonicalReadProjectionSource
    var records: [CanonicalUploadReadProjectionRecord]
    var failures: [CanonicalReadProjectionFailure]

    nonisolated init(
        source: CanonicalReadProjectionSource,
        records: [CanonicalUploadReadProjectionRecord] = [],
        failures: [CanonicalReadProjectionFailure] = []
    ) {
        self.source = source
        self.records = records.sorted { $0.objectID < $1.objectID }
        self.failures = failures.sorted { $0.id < $1.id }
    }

    nonisolated static func build(
        source: CanonicalReadProjectionSource,
        manifest: CanonicalManifest?,
        uploadCandidates: [CanonicalAudioUploadCutoverCandidate] = []
    ) -> CanonicalUploadReadProjection {
        guard let manifest else {
            return CanonicalUploadReadProjection(
                source: source,
                failures: [
                    CanonicalReadProjectionFailure(
                        kind: .snapshotMissing,
                        domain: .audioUploadStatus,
                        reason: "uploadManifestMissing"
                    )
                ]
            )
        }
        let candidates = Dictionary(uploadCandidates.map { ($0.objectID, $0) }, uniquingKeysWith: { first, _ in first })
        return CanonicalUploadReadProjection(
            source: source,
            records: manifest.objects.map { object in
                CanonicalUploadReadProjectionRecord(object: object, candidate: candidates[object.objectID])
            }
        )
    }

    nonisolated var diagnosticsSummary: String {
        let available = records.filter(\.audioAvailable).count
        let uploadCandidates = records.filter { $0.uploadAction == .audioUploadCanaryCandidate }.count
        return "source=\(source.rawValue),records=\(records.count),audioAvailable=\(available),uploadCandidates=\(uploadCandidates),failures=\(failures.count)"
    }
}

nonisolated struct CanonicalSyncEngineStatusReadProjection: Codable, Equatable, Sendable {
    var source: CanonicalReadProjectionSource
    var mode: CanonicalReadRuntimeMode?
    var syncRuntimeMode: CanonicalSyncRuntimeMode?
    var canonicalPlanUsed: Bool
    var canonicalPlanFallback: Bool
    var canonicalPlanBlocked: Bool
    var canonicalPlanNoCommit: Bool
    var pendingTransferCount: Int
    var inFlightTransferCount: Int
    var failedTransferCount: Int
    var lastStatusSummary: String?
    var syncOrUploadTriggeredByRead: Bool

    nonisolated init(
        source: CanonicalReadProjectionSource,
        mode: CanonicalReadRuntimeMode? = nil,
        syncRuntimeResult: CanonicalSyncRuntimeResult? = nil,
        pendingTransferCount: Int = 0,
        inFlightTransferCount: Int = 0,
        failedTransferCount: Int = 0,
        lastStatusSummary: String? = nil
    ) {
        self.source = source
        self.mode = mode
        self.syncRuntimeMode = syncRuntimeResult?.mode
        self.canonicalPlanUsed = syncRuntimeResult?.canonicalPlanUsed ?? false
        self.canonicalPlanFallback = syncRuntimeResult?.canonicalPlanFallback ?? false
        self.canonicalPlanBlocked = syncRuntimeResult?.canonicalPlanBlocked ?? false
        self.canonicalPlanNoCommit = syncRuntimeResult?.canonicalPlanNoCommit ?? false
        self.pendingTransferCount = max(0, pendingTransferCount)
        self.inFlightTransferCount = max(0, inFlightTransferCount)
        self.failedTransferCount = max(0, failedTransferCount)
        self.lastStatusSummary = lastStatusSummary.flatMap(CanonicalReadRuntimeRedaction.safeText)
        self.syncOrUploadTriggeredByRead = false
    }

    nonisolated var diagnosticsSummary: String {
        [
            "source=\(source.rawValue)",
            mode.map { "readMode=\($0.rawValue)" },
            syncRuntimeMode.map { "syncMode=\($0.rawValue)" },
            "canonicalPlanUsed=\(canonicalPlanUsed)",
            "fallback=\(canonicalPlanFallback)",
            "blocked=\(canonicalPlanBlocked)",
            "pending=\(pendingTransferCount)",
            "inFlight=\(inFlightTransferCount)",
            "failed=\(failedTransferCount)",
            "syncOrUploadTriggeredByRead=false"
        ].compactMap { $0 }.joined(separator: ",")
    }
}

nonisolated struct CanonicalReadSnapshotRedaction: Codable, Equatable, Sendable {
    var excludesAbsolutePaths: Bool
    var excludesFullHashes: Bool
    var excludesSecrets: Bool
    var excludesFullGeneratedContent: Bool
    var excludesRequestResponseBodies: Bool

    nonisolated static let redacted = CanonicalReadSnapshotRedaction(
        excludesAbsolutePaths: true,
        excludesFullHashes: true,
        excludesSecrets: true,
        excludesFullGeneratedContent: true,
        excludesRequestResponseBodies: true
    )

    nonisolated var isRedacted: Bool {
        excludesAbsolutePaths
            && excludesFullHashes
            && excludesSecrets
            && excludesFullGeneratedContent
            && excludesRequestResponseBodies
    }
}

nonisolated struct CanonicalReadSnapshot: Codable, Equatable, Sendable {
    var source: CanonicalReadProjectionSource
    var generatedAt: CanonicalTimestamp
    var recordingMetadata: CanonicalRecordingReadProjection
    var libraryMetadata: CanonicalLibraryReadProjection
    var artifactMetadata: CanonicalArtifactReadProjection
    var conflictState: CanonicalConflictReadProjection
    var uploadState: CanonicalUploadReadProjection
    var syncStatus: CanonicalSyncEngineStatusReadProjection
    var redaction: CanonicalReadSnapshotRedaction

    nonisolated init(
        source: CanonicalReadProjectionSource,
        generatedAt: Date = Date(),
        recordingMetadata: CanonicalRecordingReadProjection,
        libraryMetadata: CanonicalLibraryReadProjection,
        artifactMetadata: CanonicalArtifactReadProjection,
        conflictState: CanonicalConflictReadProjection,
        uploadState: CanonicalUploadReadProjection,
        syncStatus: CanonicalSyncEngineStatusReadProjection,
        redaction: CanonicalReadSnapshotRedaction = .redacted
    ) {
        self.source = source
        self.generatedAt = CanonicalTimestamp(generatedAt)
        self.recordingMetadata = recordingMetadata
        self.libraryMetadata = libraryMetadata
        self.artifactMetadata = artifactMetadata
        self.conflictState = conflictState
        self.uploadState = uploadState
        self.syncStatus = syncStatus
        self.redaction = redaction
    }

    nonisolated static func build(
        source: CanonicalReadProjectionSource,
        manifest: CanonicalManifest?,
        peerManifest: CanonicalManifest? = nil,
        applyPlan: CanonicalApplyPlan? = nil,
        libraryPlan: CanonicalLibrarySyncPlan? = nil,
        uploadCandidates: [CanonicalAudioUploadCutoverCandidate] = [],
        syncRuntimeResult: CanonicalSyncRuntimeResult? = nil,
        generatedAt: Date = Date()
    ) -> CanonicalReadSnapshot {
        CanonicalReadSnapshot(
            source: source,
            generatedAt: generatedAt,
            recordingMetadata: CanonicalRecordingReadProjection.build(source: source, manifest: manifest),
            libraryMetadata: CanonicalLibraryReadProjection.build(source: source, manifest: manifest),
            artifactMetadata: CanonicalArtifactReadProjection.build(source: source, localManifest: manifest, peerManifest: peerManifest),
            conflictState: CanonicalConflictReadProjection.build(source: source, localManifest: manifest, peerManifest: peerManifest, applyPlan: applyPlan, libraryPlan: libraryPlan),
            uploadState: CanonicalUploadReadProjection.build(source: source, manifest: manifest, uploadCandidates: uploadCandidates),
            syncStatus: CanonicalSyncEngineStatusReadProjection(
                source: source,
                syncRuntimeResult: syncRuntimeResult
            )
        )
    }

    nonisolated var pathOrContentLeakRisk: Bool {
        if !redaction.isRedacted {
            return true
        }
        if artifactMetadata.snapshot.contentIncludedCount > 0 || artifactMetadata.snapshot.failures.contains(where: { $0.kind == .contentLeakRisk || $0.kind == .unsafePathToken }) {
            return true
        }
        if conflictState.snapshot.fullContentIncludedCount > 0 || conflictState.snapshot.absolutePathIncludedCount > 0 || conflictState.snapshot.pathLeakRiskCount > 0 {
            return true
        }
        if libraryMetadata.snapshot.pathLeakRiskCount > 0 || libraryMetadata.snapshot.fullContentIncluded {
            return true
        }
        if uploadState.records.contains(where: { $0.pathIncluded || $0.contentIncluded }) {
            return true
        }
        return false
    }

    nonisolated var diagnosticsSummary: String {
        [
            "source=\(source.rawValue)",
            "recordings=\(recordingMetadata.records.count)",
            "folders=\(libraryMetadata.snapshot.folders.count)",
            "items=\(libraryMetadata.snapshot.studyItems.count)",
            "artifacts=\(artifactMetadata.snapshot.itemCount)",
            "conflicts=\(conflictState.snapshot.items.filter { $0.conflictStatus != .none }.count)",
            "uploadRecords=\(uploadState.records.count)",
            "redacted=\(redaction.isRedacted)",
            "syncStatus=\(syncStatus.diagnosticsSummary)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalReadRuntimeDivergenceKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingObject
    case metadataMismatch
    case titleTagsFolderMismatch
    case artifactAvailabilityMismatch
    case tombstoneConflictMismatch
    case audioAvailabilityMismatch
    case uploadStatusMismatch
    case unsupportedObject
    case pathContentLeakRisk
}

nonisolated struct CanonicalReadRuntimeDivergence: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, domain.rawValue, objectID ?? "run", field ?? ""].joined(separator: "|") }

    var kind: CanonicalReadRuntimeDivergenceKind
    var domain: CanonicalReadDomain
    var objectID: String?
    var field: String?
    var legacyValue: String?
    var canonicalValue: String?
    var fatal: Bool

    nonisolated init(
        kind: CanonicalReadRuntimeDivergenceKind,
        domain: CanonicalReadDomain,
        objectID: String? = nil,
        field: String? = nil,
        legacyValue: String? = nil,
        canonicalValue: String? = nil,
        fatal: Bool = false
    ) {
        self.kind = kind
        self.domain = domain
        self.objectID = objectID.map { CanonicalReadRuntimeRedaction.safeIdentifier($0, fallback: "object") }
        self.field = CanonicalReadRuntimeRedaction.safeText(field)
        self.legacyValue = CanonicalReadRuntimeRedaction.safeText(legacyValue)
        self.canonicalValue = CanonicalReadRuntimeRedaction.safeText(canonicalValue)
        self.fatal = fatal || kind == .pathContentLeakRisk
    }
}

nonisolated struct CanonicalReadRuntimeEquivalenceReport: Codable, Equatable, Sendable {
    var equivalent: Bool
    var divergenceCount: Int
    var fatalDivergenceCount: Int
    var domainsCompared: [CanonicalReadDomain]
    var diagnosticsSummary: String
}

nonisolated struct CanonicalReadRuntimeDiff: Codable, Equatable, Sendable {
    var divergences: [CanonicalReadRuntimeDivergence]
    var equivalenceReport: CanonicalReadRuntimeEquivalenceReport
    var legacySnapshotSummary: String
    var canonicalSnapshotSummary: String
    var diagnosticsSummary: String

    nonisolated var equivalent: Bool {
        equivalenceReport.equivalent
    }

    nonisolated var divergenceCount: Int {
        equivalenceReport.divergenceCount
    }

    nonisolated static func compare(
        legacy: CanonicalReadSnapshot,
        canonical: CanonicalReadSnapshot
    ) -> CanonicalReadRuntimeDiff {
        var divergences: [CanonicalReadRuntimeDivergence] = []
        compareRecordingMetadata(legacy.recordingMetadata, canonical.recordingMetadata, into: &divergences)
        mapLibraryDiff(legacy.libraryMetadata.snapshot, canonical.libraryMetadata.snapshot, into: &divergences)
        mapArtifactDiff(legacy.artifactMetadata.snapshot, canonical.artifactMetadata.snapshot, into: &divergences)
        mapConflictDiff(legacy.conflictState.snapshot, canonical.conflictState.snapshot, into: &divergences)
        compareUploadState(legacy.uploadState, canonical.uploadState, into: &divergences)
        compareSyncStatus(legacy.syncStatus, canonical.syncStatus, into: &divergences)
        if legacy.pathOrContentLeakRisk || canonical.pathOrContentLeakRisk {
            divergences.append(CanonicalReadRuntimeDivergence(
                kind: .pathContentLeakRisk,
                domain: .syncEngineStatus,
                field: "snapshotRedaction",
                legacyValue: "legacyLeakRisk=\(legacy.pathOrContentLeakRisk)",
                canonicalValue: "canonicalLeakRisk=\(canonical.pathOrContentLeakRisk)",
                fatal: true
            ))
        }

        let uniqueDivergences = Dictionary(divergences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.id < $1.id }
        let equivalent = uniqueDivergences.isEmpty
        let domains = CanonicalReadDomain.allCases
        let kindSummary = Array(Set(uniqueDivergences.map(\.kind.rawValue))).sorted().joined(separator: "+")
        let report = CanonicalReadRuntimeEquivalenceReport(
            equivalent: equivalent,
            divergenceCount: uniqueDivergences.count,
            fatalDivergenceCount: uniqueDivergences.filter(\.fatal).count,
            domainsCompared: domains,
            diagnosticsSummary: "equivalent=\(equivalent),divergences=\(uniqueDivergences.count),fatal=\(uniqueDivergences.filter(\.fatal).count),kinds=\(kindSummary)"
        )
        return CanonicalReadRuntimeDiff(
            divergences: uniqueDivergences,
            equivalenceReport: report,
            legacySnapshotSummary: legacy.diagnosticsSummary,
            canonicalSnapshotSummary: canonical.diagnosticsSummary,
            diagnosticsSummary: "domains=\(domains.map(\.rawValue).joined(separator: "+")),\(report.diagnosticsSummary)"
        )
    }

    private nonisolated static func compareRecordingMetadata(
        _ legacy: CanonicalRecordingReadProjection,
        _ canonical: CanonicalRecordingReadProjection,
        into divergences: inout [CanonicalReadRuntimeDivergence]
    ) {
        appendProjectionFailures(legacy.failures + canonical.failures, into: &divergences)
        let legacyByID = Dictionary(uniqueKeysWithValues: legacy.records.map { ($0.objectID, $0) })
        let canonicalByID = Dictionary(uniqueKeysWithValues: canonical.records.map { ($0.objectID, $0) })
        for objectID in Set(legacyByID.keys).union(canonicalByID.keys).sorted() {
            guard let legacyRecord = legacyByID[objectID] else {
                divergences.append(.init(kind: .missingObject, domain: .recordingMetadata, objectID: objectID, canonicalValue: "present"))
                continue
            }
            guard let canonicalRecord = canonicalByID[objectID] else {
                divergences.append(.init(kind: .missingObject, domain: .recordingMetadata, objectID: objectID, legacyValue: "present"))
                continue
            }
            appendMismatch(.titleTagsFolderMismatch, .recordingMetadata, objectID, "title", legacyRecord.title, canonicalRecord.title, into: &divergences)
            appendMismatch(.titleTagsFolderMismatch, .recordingMetadata, objectID, "tags", legacyRecord.tagsKey, canonicalRecord.tagsKey, into: &divergences)
            appendMismatch(.titleTagsFolderMismatch, .recordingMetadata, objectID, "filing", legacyRecord.filingSummary, canonicalRecord.filingSummary, into: &divergences)
            appendMismatch(.metadataMismatch, .recordingMetadata, objectID, "deleted", String(legacyRecord.isDeleted), String(canonicalRecord.isDeleted), into: &divergences)
            appendMismatch(.metadataMismatch, .recordingMetadata, objectID, "metadataHashPrefix", legacyRecord.metadataHashPrefix ?? "nil", canonicalRecord.metadataHashPrefix ?? "nil", into: &divergences)
        }
    }

    private nonisolated static func appendProjectionFailures(
        _ failures: [CanonicalReadProjectionFailure],
        into divergences: inout [CanonicalReadRuntimeDivergence]
    ) {
        for failure in failures {
            switch failure.kind {
            case .snapshotMissing:
                divergences.append(.init(kind: .missingObject, domain: failure.domain, objectID: failure.objectID, field: "snapshot", canonicalValue: failure.reason))
            case .unsupportedObject:
                divergences.append(.init(kind: .unsupportedObject, domain: failure.domain, objectID: failure.objectID, field: "object", canonicalValue: failure.reason))
            case .pathContentLeakRisk:
                divergences.append(.init(kind: .pathContentLeakRisk, domain: failure.domain, objectID: failure.objectID, field: "projection", canonicalValue: failure.reason, fatal: true))
            }
        }
    }

    private nonisolated static func mapLibraryDiff(
        _ legacy: CanonicalLibraryMetadataReadSnapshot,
        _ canonical: CanonicalLibraryMetadataReadSnapshot,
        into divergences: inout [CanonicalReadRuntimeDivergence]
    ) {
        let report = CanonicalLibraryMetadataReadSideParallelDiff.compare(legacy: legacy, canonical: canonical)
        for divergence in report.divergences where divergence.isBlocking {
            let kind: CanonicalReadRuntimeDivergenceKind
            switch divergence.kind {
            case .missingInCanonical, .missingInLegacy:
                kind = .missingObject
            case .titleMismatch, .parentMismatch, .folderMembershipMismatch, .filingMismatch, .tagsMismatch:
                kind = .titleTagsFolderMismatch
            case .unsupportedLegacyObject, .unsupportedCanonicalObject:
                kind = .unsupportedObject
            case .pathLeakRisk:
                kind = .pathContentLeakRisk
            default:
                kind = .metadataMismatch
            }
            divergences.append(.init(
                kind: kind,
                domain: .libraryMetadata,
                objectID: divergence.objectID,
                field: divergence.field,
                legacyValue: divergence.legacyValue,
                canonicalValue: divergence.canonicalValue,
                fatal: divergence.fatal
            ))
        }
    }

    private nonisolated static func mapArtifactDiff(
        _ legacy: CanonicalGeneratedArtifactReadSnapshot,
        _ canonical: CanonicalGeneratedArtifactReadSnapshot,
        into divergences: inout [CanonicalReadRuntimeDivergence]
    ) {
        let report = CanonicalGeneratedArtifactReadSideParallelDiff.compare(legacy: legacy, canonical: canonical)
        for divergence in report.divergences {
            let kind: CanonicalReadRuntimeDivergenceKind
            switch divergence.kind {
            case .missingCanonical, .missingLegacy:
                kind = .missingObject
            case .availabilityMismatch, .byteSizeMismatch, .hashPrefixMismatch, .producerMismatch, .artifactKindMismatch, .localDownloadedStateMismatch, .peerAuthoritativeStateMismatch, .parentStateMismatch:
                kind = .artifactAvailabilityMismatch
            case .unsafePathToken, .contentLeakRisk:
                kind = .pathContentLeakRisk
            case .unsupportedArtifactKind, .audioConfusionRisk, .tombstonedParentResurrectionRisk:
                kind = .unsupportedObject
            default:
                kind = .metadataMismatch
            }
            divergences.append(.init(
                kind: kind,
                domain: .generatedArtifacts,
                objectID: divergence.objectID,
                field: divergence.artifactKind?.rawValue,
                legacyValue: divergence.legacyValue,
                canonicalValue: divergence.canonicalValue,
                fatal: divergence.fatal
            ))
        }
    }

    private nonisolated static func mapConflictDiff(
        _ legacy: CanonicalTombstoneConflictReadSnapshot,
        _ canonical: CanonicalTombstoneConflictReadSnapshot,
        into divergences: inout [CanonicalReadRuntimeDivergence]
    ) {
        let report = CanonicalTombstoneConflictReadSideParallelDiff.compare(legacy: legacy, canonical: canonical)
        for divergence in report.divergences {
            let kind: CanonicalReadRuntimeDivergenceKind
            switch divergence.kind {
            case .missingInCanonical, .missingInLegacy:
                kind = .missingObject
            case .unsupportedObjectKind:
                kind = .unsupportedObject
            case .pathLeakRisk, .physicalDeleteRisk, .permanentDeleteRisk, .tombstoneGCRisk, .autoConflictResolutionRisk, .staleLiveResurrectionRisk:
                kind = .pathContentLeakRisk
            default:
                kind = .tombstoneConflictMismatch
            }
            divergences.append(.init(
                kind: kind,
                domain: .tombstoneConflict,
                objectID: divergence.objectID,
                field: divergence.field,
                legacyValue: divergence.legacyValue,
                canonicalValue: divergence.canonicalValue,
                fatal: divergence.fatal
            ))
        }
    }

    private nonisolated static func compareUploadState(
        _ legacy: CanonicalUploadReadProjection,
        _ canonical: CanonicalUploadReadProjection,
        into divergences: inout [CanonicalReadRuntimeDivergence]
    ) {
        appendProjectionFailures(legacy.failures + canonical.failures, into: &divergences)
        let legacyByID = Dictionary(uniqueKeysWithValues: legacy.records.map { ($0.objectID, $0) })
        let canonicalByID = Dictionary(uniqueKeysWithValues: canonical.records.map { ($0.objectID, $0) })
        for objectID in Set(legacyByID.keys).union(canonicalByID.keys).sorted() {
            guard let legacyRecord = legacyByID[objectID] else {
                divergences.append(.init(kind: .missingObject, domain: .audioUploadStatus, objectID: objectID, canonicalValue: "present"))
                continue
            }
            guard let canonicalRecord = canonicalByID[objectID] else {
                divergences.append(.init(kind: .missingObject, domain: .audioUploadStatus, objectID: objectID, legacyValue: "present"))
                continue
            }
            appendMismatch(.audioAvailabilityMismatch, .audioUploadStatus, objectID, "audioAvailable", String(legacyRecord.audioAvailable), String(canonicalRecord.audioAvailable), into: &divergences)
            appendMismatch(.audioAvailabilityMismatch, .audioUploadStatus, objectID, "audioAvailability", legacyRecord.audioAvailability.rawValue, canonicalRecord.audioAvailability.rawValue, into: &divergences)
            appendMismatch(.audioAvailabilityMismatch, .audioUploadStatus, objectID, "byteSize", legacyRecord.byteSize.map(String.init) ?? "nil", canonicalRecord.byteSize.map(String.init) ?? "nil", into: &divergences)
            appendMismatch(.audioAvailabilityMismatch, .audioUploadStatus, objectID, "audioHashPrefix", legacyRecord.audioHashPrefix ?? "nil", canonicalRecord.audioHashPrefix ?? "nil", into: &divergences)
            appendMismatch(.uploadStatusMismatch, .audioUploadStatus, objectID, "uploadAction", legacyRecord.uploadAction?.rawValue ?? "nil", canonicalRecord.uploadAction?.rawValue ?? "nil", into: &divergences)
            appendMismatch(.uploadStatusMismatch, .audioUploadStatus, objectID, "uploadEvidenceStatus", legacyRecord.uploadEvidenceStatus?.rawValue ?? "nil", canonicalRecord.uploadEvidenceStatus?.rawValue ?? "nil", into: &divergences)
            appendMismatch(.uploadStatusMismatch, .audioUploadStatus, objectID, "ledgerPhase", legacyRecord.uploadLedgerPhase?.rawValue ?? "nil", canonicalRecord.uploadLedgerPhase?.rawValue ?? "nil", into: &divergences)
        }
    }

    private nonisolated static func compareSyncStatus(
        _ legacy: CanonicalSyncEngineStatusReadProjection,
        _ canonical: CanonicalSyncEngineStatusReadProjection,
        into divergences: inout [CanonicalReadRuntimeDivergence]
    ) {
        appendMismatch(.metadataMismatch, .syncEngineStatus, "sync-engine", "pending", String(legacy.pendingTransferCount), String(canonical.pendingTransferCount), into: &divergences)
        appendMismatch(.metadataMismatch, .syncEngineStatus, "sync-engine", "inFlight", String(legacy.inFlightTransferCount), String(canonical.inFlightTransferCount), into: &divergences)
        appendMismatch(.metadataMismatch, .syncEngineStatus, "sync-engine", "failed", String(legacy.failedTransferCount), String(canonical.failedTransferCount), into: &divergences)
    }

    private nonisolated static func appendMismatch(
        _ kind: CanonicalReadRuntimeDivergenceKind,
        _ domain: CanonicalReadDomain,
        _ objectID: String,
        _ field: String,
        _ legacyValue: String,
        _ canonicalValue: String,
        into divergences: inout [CanonicalReadRuntimeDivergence]
    ) {
        guard legacyValue != canonicalValue else {
            return
        }
        divergences.append(CanonicalReadRuntimeDivergence(
            kind: kind,
            domain: domain,
            objectID: objectID,
            field: field,
            legacyValue: legacyValue,
            canonicalValue: canonicalValue
        ))
    }
}

nonisolated enum CanonicalReadRuntimeGateBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case blockedMode
    case canonicalSnapshotMissing
    case applyRuntimeEvidenceMissing
    case uploadRuntimeEvidenceMissing
    case inventorySnapshotMissing
    case planAuthorityEvidenceMissing
    case existenceTruthEvidenceMissing
    case divergencePresent
    case legacyFallbackUnavailable
    case otherDomainConflict
    case releaseDefaultBuild
    case debugInternalApprovalMissing
    case manualOwnerApprovalMissing
    case diagnosticsNotRedacted
    case readMayTriggerSyncUpload
    case readMayMutateStore
    case pathContentLeakRisk
}

nonisolated struct CanonicalReadRuntimeGateResult: Codable, Equatable, Sendable {
    var allowed: Bool
    var blockers: [CanonicalReadRuntimeGateBlocker]
    var diagnosticsSummary: String

    nonisolated init(blockers: [CanonicalReadRuntimeGateBlocker]) {
        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.allowed = uniqueBlockers.isEmpty
        self.blockers = uniqueBlockers
        self.diagnosticsSummary = "allowed=\(uniqueBlockers.isEmpty),blockers=\(uniqueBlockers.map(\.rawValue).joined(separator: "+"))"
    }
}

nonisolated enum CanonicalReadRuntimeGate {
    nonisolated static func evaluate(
        configuration: CanonicalReadRuntimeConfiguration,
        canonicalSnapshotAvailable: Bool,
        diff: CanonicalReadRuntimeDiff?
    ) -> CanonicalReadRuntimeGateResult {
        let policy = configuration.policy
        var blockers: [CanonicalReadRuntimeGateBlocker] = []
        if configuration.mode == .blocked {
            blockers.append(.blockedMode)
        }
        if !canonicalSnapshotAvailable {
            blockers.append(.canonicalSnapshotMissing)
        }
        if !policy.applyRuntimeEvidenceValidForNonAudio {
            blockers.append(.applyRuntimeEvidenceMissing)
        }
        if !policy.uploadRuntimeEvidenceValidForAudioStatus {
            blockers.append(.uploadRuntimeEvidenceMissing)
        }
        if !policy.inventorySnapshotAvailable {
            blockers.append(.inventorySnapshotMissing)
        }
        if !policy.planAuthorityEvidenceValid {
            blockers.append(.planAuthorityEvidenceMissing)
        }
        if !policy.existenceTruthEvidenceValid {
            blockers.append(.existenceTruthEvidenceMissing)
        }
        if !policy.legacyFallbackAvailable {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !policy.otherDomainsNotConflicting {
            blockers.append(.otherDomainConflict)
        }
        if policy.releaseDefaultBuild {
            blockers.append(.releaseDefaultBuild)
        }
        if !policy.debugInternalBuild || !policy.ownerApproved {
            blockers.append(.debugInternalApprovalMissing)
        }
        if !policy.manualOwnerApproval {
            blockers.append(.manualOwnerApprovalMissing)
        }
        if !policy.diagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
        }
        if !policy.readMustNotTriggerSyncUpload {
            blockers.append(.readMayTriggerSyncUpload)
        }
        if !policy.readMustNotMutateStore {
            blockers.append(.readMayMutateStore)
        }
        if let diff {
            if diff.divergenceCount > 0 && !policy.allowDivergentGuardedReadForTests {
                blockers.append(.divergencePresent)
            }
            if diff.divergences.contains(where: { $0.kind == .pathContentLeakRisk }) {
                blockers.append(.pathContentLeakRisk)
            }
        }
        return CanonicalReadRuntimeGateResult(blockers: blockers)
    }
}

nonisolated enum CanonicalReadRuntimeDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalReadRuntimeModeEvaluated
    case canonicalReadRuntimeServedCanonical
    case canonicalReadRuntimeServedLegacyFallback
    case canonicalReadRuntimeDiffEquivalent
    case canonicalReadRuntimeDiffDivergent
    case canonicalReadRuntimeBlocked
    case canonicalReadRuntimeReportBuilt
    case canonicalRecordingMetadataReadModeEvaluated
    case canonicalRecordingMetadataReadServedCanonical
    case canonicalRecordingMetadataReadServedLegacyFallback
    case canonicalRecordingMetadataReadDiffEquivalent
    case canonicalRecordingMetadataReadDiffDivergent
    case canonicalRecordingMetadataReadBlocked
    case canonicalLibraryMetadataReadModeEvaluated
    case canonicalLibraryMetadataReadServedCanonical
    case canonicalLibraryMetadataReadServedLegacyFallback
    case canonicalLibraryMetadataReadDiffEquivalent
    case canonicalLibraryMetadataReadDiffDivergent
    case canonicalLibraryMetadataReadBlocked
    case canonicalGeneratedArtifactReadModeEvaluated
    case canonicalGeneratedArtifactReadServedCanonical
    case canonicalGeneratedArtifactReadServedLegacyFallback
    case canonicalGeneratedArtifactReadDiffEquivalent
    case canonicalGeneratedArtifactReadDiffDivergent
    case canonicalGeneratedArtifactReadBlocked
    case canonicalGeneratedArtifactReadContentNotLogged
    case canonicalTombstoneConflictReadModeEvaluated
    case canonicalTombstoneConflictReadServedCanonical
    case canonicalTombstoneConflictReadServedLegacyFallback
    case canonicalTombstoneConflictReadDiffEquivalent
    case canonicalTombstoneConflictReadDiffDivergent
    case canonicalTombstoneConflictReadBlocked
    case canonicalTombstoneConflictReadDidNotTriggerDelete
    case canonicalReadEffectiveCacheHit
    case canonicalReadEffectiveCacheMiss
    case canonicalReadEffectiveCacheInvalidated
    case canonicalReadEffectiveCacheRebuilt
    case canonicalReadEffectiveTreeRebuilt
    case canonicalReadEffectiveFallbackLegacy
    case canonicalReadEffectiveRepeatedAccessAvoidedRebuild
    case canonicalReadEffectiveRebuildDurationMs
}

nonisolated struct CanonicalReadRuntimeDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, syncRunID ?? "", mode.rawValue, detail ?? ""].joined(separator: "|") }

    var kind: CanonicalReadRuntimeDiagnosticKind
    var syncRunID: String?
    var mode: CanonicalReadRuntimeMode
    var source: CanonicalReadProjectionSource?
    var count: Int?
    var detail: String?

    nonisolated init(
        kind: CanonicalReadRuntimeDiagnosticKind,
        syncRunID: String?,
        mode: CanonicalReadRuntimeMode,
        source: CanonicalReadProjectionSource? = nil,
        count: Int? = nil,
        detail: String? = nil
    ) {
        self.kind = kind
        self.syncRunID = syncRunID.flatMap(CanonicalReadRuntimeRedaction.safeText)
        self.mode = mode
        self.source = source
        self.count = count
        self.detail = detail.flatMap(CanonicalReadRuntimeRedaction.safeText)
    }

    nonisolated var isRedacted: Bool {
        [syncRunID, detail].compactMap { $0 }.allSatisfy {
            !CanonicalReadRuntimeRedaction.containsForbiddenSignal($0)
        }
    }

    nonisolated var diagnosticsSummary: String {
        [
            "kind=\(kind.rawValue)",
            "mode=\(mode.rawValue)",
            source.map { "source=\($0.rawValue)" },
            count.map { "count=\($0)" },
            detail.map { "detail=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }
}

nonisolated enum CanonicalReadRuntimeFallback: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case none
    case legacyDefault
    case parallelCompareReturnsLegacy
    case canonicalCandidateNotServed
    case guardedGateBlocked
    case canonicalProjectionMissing
    case canonicalReadException
    case blockedMode
}

nonisolated struct CanonicalReadRuntimeResult: Codable, Equatable, Sendable {
    var mode: CanonicalReadRuntimeMode
    var returnedSource: CanonicalReadProjectionSource
    var readSnapshot: CanonicalReadSnapshot
    var legacySnapshot: CanonicalReadSnapshot
    var canonicalCandidate: CanonicalReadSnapshot?
    var diff: CanonicalReadRuntimeDiff?
    var gateResult: CanonicalReadRuntimeGateResult?
    var fallback: CanonicalReadRuntimeFallback
    var canonicalReadServed: Bool
    var legacyFallbackServed: Bool
    var canonicalCandidateBuilt: Bool
    var storeMutated: Bool
    var syncOrUploadTriggered: Bool
    var uploadJobCreated: Bool
    var resourceMoved: Bool
    var productionDataWritten: Bool
    var diagnostics: [CanonicalReadRuntimeDiagnostic]
    var diagnosticsSummary: String
}

nonisolated struct CanonicalReadRuntimeProvider: Sendable {
    var configuration: CanonicalReadRuntimeConfiguration

    nonisolated init(configuration: CanonicalReadRuntimeConfiguration = .disabled) {
        self.configuration = configuration
    }

    nonisolated func read(
        legacySnapshot: CanonicalReadSnapshot,
        canonicalSnapshot: CanonicalReadSnapshot?,
        syncRunID: String? = nil,
        canonicalReadFailureReason: String? = nil
    ) -> CanonicalReadRuntimeResult {
        let mode = configuration.mode
        let evaluated = diagnostic(.canonicalReadRuntimeModeEvaluated, syncRunID: syncRunID, source: nil, count: nil, detail: "mode=\(mode.rawValue)")

        switch mode {
        case .disabled:
            return makeResult(
                returnedSnapshot: legacySnapshot,
                legacySnapshot: legacySnapshot,
                canonicalSnapshot: nil,
                diff: nil,
                gate: nil,
                fallback: .legacyDefault,
                diagnostics: [
                    evaluated,
                    diagnostic(.canonicalReadRuntimeServedLegacyFallback, syncRunID: syncRunID, source: .legacy, detail: "disabledDefaultLegacy")
                ]
            )
        case .blocked:
            let diff = canonicalSnapshot.map { CanonicalReadRuntimeDiff.compare(legacy: legacySnapshot, canonical: $0) }
            return makeResult(
                returnedSnapshot: legacySnapshot,
                legacySnapshot: legacySnapshot,
                canonicalSnapshot: canonicalSnapshot,
                diff: diff,
                gate: CanonicalReadRuntimeGateResult(blockers: [.blockedMode]),
                fallback: .blockedMode,
                diagnostics: [
                    evaluated,
                    diagnostic(.canonicalReadRuntimeBlocked, syncRunID: syncRunID, source: .legacy, count: 1, detail: "blockedMode"),
                    diagnostic(.canonicalReadRuntimeServedLegacyFallback, syncRunID: syncRunID, source: .legacy, detail: "blockedMode")
                ] + diffDiagnostics(diff, syncRunID: syncRunID)
            )
        case .parallelCompare, .canonicalReadCandidate:
            let diff = canonicalSnapshot.map { CanonicalReadRuntimeDiff.compare(legacy: legacySnapshot, canonical: $0) }
            let fallback: CanonicalReadRuntimeFallback = mode == .parallelCompare ? .parallelCompareReturnsLegacy : .canonicalCandidateNotServed
            let reason = mode == .parallelCompare ? "parallelCompareReturnsLegacy" : "canonicalCandidateNotServed"
            return makeResult(
                returnedSnapshot: legacySnapshot,
                legacySnapshot: legacySnapshot,
                canonicalSnapshot: canonicalSnapshot,
                diff: diff,
                gate: nil,
                fallback: fallback,
                diagnostics: [
                    evaluated,
                    diagnostic(.canonicalReadRuntimeServedLegacyFallback, syncRunID: syncRunID, source: .legacy, detail: reason)
                ] + diffDiagnostics(diff, syncRunID: syncRunID)
            )
        case .guardedCanonicalReadWithLegacyFallback:
            guard let canonicalSnapshot else {
                return makeResult(
                    returnedSnapshot: legacySnapshot,
                    legacySnapshot: legacySnapshot,
                    canonicalSnapshot: nil,
                    diff: nil,
                    gate: CanonicalReadRuntimeGate.evaluate(configuration: configuration, canonicalSnapshotAvailable: false, diff: nil),
                    fallback: .canonicalProjectionMissing,
                    diagnostics: [
                        evaluated,
                        diagnostic(.canonicalReadRuntimeBlocked, syncRunID: syncRunID, source: .legacy, count: 1, detail: "canonicalProjectionMissing"),
                        diagnostic(.canonicalReadRuntimeServedLegacyFallback, syncRunID: syncRunID, source: .legacy, detail: "canonicalProjectionMissing")
                    ]
                )
            }
            let diff = CanonicalReadRuntimeDiff.compare(legacy: legacySnapshot, canonical: canonicalSnapshot)
            let gate = CanonicalReadRuntimeGate.evaluate(configuration: configuration, canonicalSnapshotAvailable: true, diff: diff)
            var diagnostics = [evaluated] + diffDiagnostics(diff, syncRunID: syncRunID)
            if let canonicalReadFailureReason {
                diagnostics.append(diagnostic(.canonicalReadRuntimeServedLegacyFallback, syncRunID: syncRunID, source: .legacy, detail: canonicalReadFailureReason))
                return makeResult(
                    returnedSnapshot: legacySnapshot,
                    legacySnapshot: legacySnapshot,
                    canonicalSnapshot: canonicalSnapshot,
                    diff: diff,
                    gate: gate,
                    fallback: .canonicalReadException,
                    diagnostics: diagnostics
                )
            }
            guard gate.allowed else {
                diagnostics.append(diagnostic(.canonicalReadRuntimeBlocked, syncRunID: syncRunID, source: .legacy, count: gate.blockers.count, detail: gate.blockers.map(\.rawValue).joined(separator: "+")))
                diagnostics.append(diagnostic(.canonicalReadRuntimeServedLegacyFallback, syncRunID: syncRunID, source: .legacy, detail: "guardedGateBlocked"))
                return makeResult(
                    returnedSnapshot: legacySnapshot,
                    legacySnapshot: legacySnapshot,
                    canonicalSnapshot: canonicalSnapshot,
                    diff: diff,
                    gate: gate,
                    fallback: .guardedGateBlocked,
                    diagnostics: diagnostics
                )
            }
            diagnostics.append(diagnostic(.canonicalReadRuntimeServedCanonical, syncRunID: syncRunID, source: .canonical, detail: "guardedCanonicalReadWithLegacyFallback"))
            return makeResult(
                returnedSnapshot: canonicalSnapshot,
                legacySnapshot: legacySnapshot,
                canonicalSnapshot: canonicalSnapshot,
                diff: diff,
                gate: gate,
                fallback: .none,
                diagnostics: diagnostics
            )
        }
    }

    private nonisolated func makeResult(
        returnedSnapshot: CanonicalReadSnapshot,
        legacySnapshot: CanonicalReadSnapshot,
        canonicalSnapshot: CanonicalReadSnapshot?,
        diff: CanonicalReadRuntimeDiff?,
        gate: CanonicalReadRuntimeGateResult?,
        fallback: CanonicalReadRuntimeFallback,
        diagnostics: [CanonicalReadRuntimeDiagnostic]
    ) -> CanonicalReadRuntimeResult {
        var diagnostics = diagnostics
        diagnostics.append(diagnostic(.canonicalReadRuntimeReportBuilt, syncRunID: diagnostics.first?.syncRunID, source: returnedSnapshot.source, count: diff?.divergenceCount, detail: "fallback=\(fallback.rawValue)"))
        diagnostics.append(contentsOf: recordingMetadataReadDiagnostics(
            returnedSnapshot: returnedSnapshot,
            diff: diff,
            gate: gate,
            fallback: fallback,
            syncRunID: diagnostics.first?.syncRunID
        ))
        diagnostics.append(contentsOf: libraryMetadataReadDiagnostics(
            returnedSnapshot: returnedSnapshot,
            diff: diff,
            gate: gate,
            fallback: fallback,
            syncRunID: diagnostics.first?.syncRunID
        ))
        diagnostics.append(contentsOf: generatedArtifactReadDiagnostics(
            returnedSnapshot: returnedSnapshot,
            diff: diff,
            gate: gate,
            fallback: fallback,
            syncRunID: diagnostics.first?.syncRunID
        ))
        diagnostics.append(contentsOf: tombstoneConflictReadDiagnostics(
            returnedSnapshot: returnedSnapshot,
            diff: diff,
            gate: gate,
            fallback: fallback,
            syncRunID: diagnostics.first?.syncRunID
        ))
        let limitedDiagnostics = Array(diagnostics.prefix(configuration.policy.maxDiagnosticsEvents))
        let canonicalServed = returnedSnapshot.source == .canonical && fallback == .none
        return CanonicalReadRuntimeResult(
            mode: configuration.mode,
            returnedSource: returnedSnapshot.source,
            readSnapshot: returnedSnapshot,
            legacySnapshot: legacySnapshot,
            canonicalCandidate: canonicalSnapshot,
            diff: diff,
            gateResult: gate,
            fallback: fallback,
            canonicalReadServed: canonicalServed,
            legacyFallbackServed: returnedSnapshot.source == .legacy && fallback != .none,
            canonicalCandidateBuilt: canonicalSnapshot != nil && configuration.mode.buildsCanonicalCandidate,
            storeMutated: false,
            syncOrUploadTriggered: false,
            uploadJobCreated: false,
            resourceMoved: false,
            productionDataWritten: false,
            diagnostics: limitedDiagnostics,
            diagnosticsSummary: [
                "mode=\(configuration.mode.rawValue)",
                "returned=\(returnedSnapshot.source.rawValue)",
                "fallback=\(fallback.rawValue)",
                "canonicalServed=\(canonicalServed)",
                "canonicalCandidateBuilt=\(canonicalSnapshot != nil && configuration.mode.buildsCanonicalCandidate)",
                "divergences=\(diff?.divergenceCount ?? 0)",
                "storeMutated=false",
                "syncOrUploadTriggered=false",
                "uploadJobCreated=false",
                "resourceMoved=false",
                "productionDataWritten=false"
            ].joined(separator: ",")
        )
    }

    private nonisolated func diffDiagnostics(
        _ diff: CanonicalReadRuntimeDiff?,
        syncRunID: String?
    ) -> [CanonicalReadRuntimeDiagnostic] {
        guard let diff else {
            return []
        }
        return [
            diagnostic(
                diff.equivalent ? .canonicalReadRuntimeDiffEquivalent : .canonicalReadRuntimeDiffDivergent,
                syncRunID: syncRunID,
                source: .canonical,
                count: diff.divergenceCount,
                detail: diff.equivalenceReport.diagnosticsSummary
            )
        ]
    }

    private nonisolated func recordingMetadataReadDiagnostics(
        returnedSnapshot: CanonicalReadSnapshot,
        diff: CanonicalReadRuntimeDiff?,
        gate: CanonicalReadRuntimeGateResult?,
        fallback: CanonicalReadRuntimeFallback,
        syncRunID: String?
    ) -> [CanonicalReadRuntimeDiagnostic] {
        var diagnostics = [
            diagnostic(
                .canonicalRecordingMetadataReadModeEvaluated,
                syncRunID: syncRunID,
                source: returnedSnapshot.source,
                count: returnedSnapshot.recordingMetadata.records.count,
                detail: "mode=\(configuration.mode.rawValue)"
            )
        ]

        if returnedSnapshot.source == .canonical && fallback == .none {
            diagnostics.append(diagnostic(
                .canonicalRecordingMetadataReadServedCanonical,
                syncRunID: syncRunID,
                source: .canonical,
                count: returnedSnapshot.recordingMetadata.records.count,
                detail: "guardedCanonicalReadWithLegacyFallback"
            ))
        } else {
            diagnostics.append(diagnostic(
                .canonicalRecordingMetadataReadServedLegacyFallback,
                syncRunID: syncRunID,
                source: .legacy,
                count: returnedSnapshot.recordingMetadata.records.count,
                detail: fallback.rawValue
            ))
        }

        if let diff {
            diagnostics.append(diagnostic(
                diff.equivalent ? .canonicalRecordingMetadataReadDiffEquivalent : .canonicalRecordingMetadataReadDiffDivergent,
                syncRunID: syncRunID,
                source: .canonical,
                count: diff.divergenceCount,
                detail: diff.equivalenceReport.diagnosticsSummary
            ))
        }

        if gate?.allowed == false
            || fallback == .guardedGateBlocked
            || fallback == .canonicalProjectionMissing
            || fallback == .canonicalReadException
            || fallback == .blockedMode {
            diagnostics.append(diagnostic(
                .canonicalRecordingMetadataReadBlocked,
                syncRunID: syncRunID,
                source: .legacy,
                count: gate?.blockers.count,
                detail: gate?.blockers.map(\.rawValue).joined(separator: "+") ?? fallback.rawValue
            ))
        }
        return diagnostics
    }

    private nonisolated func libraryMetadataReadDiagnostics(
        returnedSnapshot: CanonicalReadSnapshot,
        diff: CanonicalReadRuntimeDiff?,
        gate: CanonicalReadRuntimeGateResult?,
        fallback: CanonicalReadRuntimeFallback,
        syncRunID: String?
    ) -> [CanonicalReadRuntimeDiagnostic] {
        let objectCount = returnedSnapshot.libraryMetadata.snapshot.objectCount
        var diagnostics = [
            diagnostic(
                .canonicalLibraryMetadataReadModeEvaluated,
                syncRunID: syncRunID,
                source: returnedSnapshot.source,
                count: objectCount,
                detail: "mode=\(configuration.mode.rawValue)"
            )
        ]

        if returnedSnapshot.source == .canonical && fallback == .none {
            diagnostics.append(diagnostic(
                .canonicalLibraryMetadataReadServedCanonical,
                syncRunID: syncRunID,
                source: .canonical,
                count: objectCount,
                detail: "guardedCanonicalReadWithLegacyFallback"
            ))
        } else {
            diagnostics.append(diagnostic(
                .canonicalLibraryMetadataReadServedLegacyFallback,
                syncRunID: syncRunID,
                source: .legacy,
                count: objectCount,
                detail: fallback.rawValue
            ))
        }

        if let diff {
            let libraryDivergenceCount = diff.divergences.filter { $0.domain == .libraryMetadata }.count
            diagnostics.append(diagnostic(
                libraryDivergenceCount == 0 ? .canonicalLibraryMetadataReadDiffEquivalent : .canonicalLibraryMetadataReadDiffDivergent,
                syncRunID: syncRunID,
                source: .canonical,
                count: libraryDivergenceCount,
                detail: "domain=libraryMetadata,divergences=\(libraryDivergenceCount)"
            ))
        }

        if gate?.allowed == false
            || fallback == .guardedGateBlocked
            || fallback == .canonicalProjectionMissing
            || fallback == .canonicalReadException
            || fallback == .blockedMode {
            diagnostics.append(diagnostic(
                .canonicalLibraryMetadataReadBlocked,
                syncRunID: syncRunID,
                source: .legacy,
                count: gate?.blockers.count,
                detail: gate?.blockers.map(\.rawValue).joined(separator: "+") ?? fallback.rawValue
            ))
        }
        return diagnostics
    }

    private nonisolated func generatedArtifactReadDiagnostics(
        returnedSnapshot: CanonicalReadSnapshot,
        diff: CanonicalReadRuntimeDiff?,
        gate: CanonicalReadRuntimeGateResult?,
        fallback: CanonicalReadRuntimeFallback,
        syncRunID: String?
    ) -> [CanonicalReadRuntimeDiagnostic] {
        let artifactCount = returnedSnapshot.artifactMetadata.snapshot.itemCount
        var diagnostics = [
            diagnostic(
                .canonicalGeneratedArtifactReadModeEvaluated,
                syncRunID: syncRunID,
                source: returnedSnapshot.source,
                count: artifactCount,
                detail: "mode=\(configuration.mode.rawValue)"
            ),
            diagnostic(
                .canonicalGeneratedArtifactReadContentNotLogged,
                syncRunID: syncRunID,
                source: returnedSnapshot.source,
                count: returnedSnapshot.artifactMetadata.snapshot.contentIncludedCount,
                detail: "contentExcluded=true"
            )
        ]

        if returnedSnapshot.source == .canonical && fallback == .none {
            diagnostics.append(diagnostic(
                .canonicalGeneratedArtifactReadServedCanonical,
                syncRunID: syncRunID,
                source: .canonical,
                count: artifactCount,
                detail: "guardedCanonicalReadWithLegacyFallback"
            ))
        } else {
            diagnostics.append(diagnostic(
                .canonicalGeneratedArtifactReadServedLegacyFallback,
                syncRunID: syncRunID,
                source: .legacy,
                count: artifactCount,
                detail: fallback.rawValue
            ))
        }

        if let diff {
            let generatedArtifactDivergenceCount = diff.divergences.filter { $0.domain == .generatedArtifacts }.count
            diagnostics.append(diagnostic(
                generatedArtifactDivergenceCount == 0 ? .canonicalGeneratedArtifactReadDiffEquivalent : .canonicalGeneratedArtifactReadDiffDivergent,
                syncRunID: syncRunID,
                source: .canonical,
                count: generatedArtifactDivergenceCount,
                detail: "domain=generatedArtifacts,divergences=\(generatedArtifactDivergenceCount)"
            ))
        }

        if gate?.allowed == false
            || fallback == .guardedGateBlocked
            || fallback == .canonicalProjectionMissing
            || fallback == .canonicalReadException
            || fallback == .blockedMode {
            diagnostics.append(diagnostic(
                .canonicalGeneratedArtifactReadBlocked,
                syncRunID: syncRunID,
                source: .legacy,
                count: gate?.blockers.count,
                detail: gate?.blockers.map(\.rawValue).joined(separator: "+") ?? fallback.rawValue
            ))
        }
        return diagnostics
    }

    private nonisolated func tombstoneConflictReadDiagnostics(
        returnedSnapshot: CanonicalReadSnapshot,
        diff: CanonicalReadRuntimeDiff?,
        gate: CanonicalReadRuntimeGateResult?,
        fallback: CanonicalReadRuntimeFallback,
        syncRunID: String?
    ) -> [CanonicalReadRuntimeDiagnostic] {
        let itemCount = returnedSnapshot.conflictState.snapshot.itemCount
        var diagnostics = [
            diagnostic(
                .canonicalTombstoneConflictReadModeEvaluated,
                syncRunID: syncRunID,
                source: returnedSnapshot.source,
                count: itemCount,
                detail: "mode=\(configuration.mode.rawValue)"
            ),
            diagnostic(
                .canonicalTombstoneConflictReadDidNotTriggerDelete,
                syncRunID: syncRunID,
                source: returnedSnapshot.source,
                count: returnedSnapshot.conflictState.snapshot.physicalDeleteRiskCount,
                detail: "deleteRestoreGCTriggered=false"
            )
        ]

        if returnedSnapshot.source == .canonical && fallback == .none {
            diagnostics.append(diagnostic(
                .canonicalTombstoneConflictReadServedCanonical,
                syncRunID: syncRunID,
                source: .canonical,
                count: itemCount,
                detail: "guardedCanonicalReadWithLegacyFallback"
            ))
        } else {
            diagnostics.append(diagnostic(
                .canonicalTombstoneConflictReadServedLegacyFallback,
                syncRunID: syncRunID,
                source: .legacy,
                count: itemCount,
                detail: fallback.rawValue
            ))
        }

        if let diff {
            let tombstoneDivergenceCount = diff.divergences.filter { $0.domain == .tombstoneConflict }.count
            diagnostics.append(diagnostic(
                tombstoneDivergenceCount == 0 ? .canonicalTombstoneConflictReadDiffEquivalent : .canonicalTombstoneConflictReadDiffDivergent,
                syncRunID: syncRunID,
                source: .canonical,
                count: tombstoneDivergenceCount,
                detail: "domain=tombstoneConflict,divergences=\(tombstoneDivergenceCount)"
            ))
        }

        if gate?.allowed == false
            || fallback == .guardedGateBlocked
            || fallback == .canonicalProjectionMissing
            || fallback == .canonicalReadException
            || fallback == .blockedMode {
            diagnostics.append(diagnostic(
                .canonicalTombstoneConflictReadBlocked,
                syncRunID: syncRunID,
                source: .legacy,
                count: gate?.blockers.count,
                detail: gate?.blockers.map(\.rawValue).joined(separator: "+") ?? fallback.rawValue
            ))
        }
        return diagnostics
    }

    private nonisolated func diagnostic(
        _ kind: CanonicalReadRuntimeDiagnosticKind,
        syncRunID: String?,
        source: CanonicalReadProjectionSource?,
        count: Int? = nil,
        detail: String? = nil
    ) -> CanonicalReadRuntimeDiagnostic {
        CanonicalReadRuntimeDiagnostic(
            kind: kind,
            syncRunID: syncRunID,
            mode: configuration.mode,
            source: source,
            count: count,
            detail: detail
        )
    }
}

private extension CanonicalReadProjectionSource {
    nonisolated var libraryMetadataSource: CanonicalLibraryMetadataReadProjectionSource {
        switch self {
        case .legacy: return .legacy
        case .canonical: return .canonical
        }
    }

    nonisolated var generatedArtifactSource: CanonicalGeneratedArtifactReadProjectionSource {
        switch self {
        case .legacy: return .legacy
        case .canonical: return .canonical
        }
    }

    nonisolated var tombstoneConflictSource: CanonicalTombstoneConflictReadProjectionSource {
        switch self {
        case .legacy: return .legacy
        case .canonical: return .canonical
        }
    }
}

private nonisolated enum CanonicalReadRuntimeRedaction {
    static func safeIdentifier(_ value: String, fallback: String) -> String {
        CanonicalProductionRedaction.safeIdentifier(value, fallback: fallback)
    }

    static func safeDisplayText(_ value: String, fallback: String) -> String {
        CanonicalProductionRedaction.safeDiagnosticText(value) ?? fallback
    }

    static func safeText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        return CanonicalProductionRedaction.safeDiagnosticText(value)
    }

    static func hashPrefix(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        return CanonicalProductionRedaction.hashPrefix(value)
    }

    static func containsForbiddenSignal(_ value: String) -> Bool {
        containsSensitivePathSignal(value)
            || value.contains("{")
            || value.contains("}")
            || value.contains("://")
            || value.count > 320
    }

    private static func containsSensitivePathSignal(_ value: String) -> Bool {
        CanonicalProductionRedaction.containsSensitivePathSignal(value)
            || value.contains("/")
            || value.contains("\\")
    }
}
