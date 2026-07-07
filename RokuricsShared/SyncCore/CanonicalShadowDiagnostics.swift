//
//  CanonicalShadowDiagnostics.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/1.
//

import Foundation

nonisolated enum CanonicalShadowNodeRole: String, Codable, Equatable, Sendable {
    case iphone = "iPhone"
    case mac = "Mac"
}

nonisolated enum CanonicalShadowMismatchCategory: String, Codable, Equatable, Sendable {
    case legacyRecordingMissingInCanonical
    case canonicalObjectMissingInLegacy
    case studyItemOnlyWithoutReceiveRecord
    case receiveRecordOnlyWithoutStudyItem
    case legacyMetadataHashMismatchButCanonicalHashMatch
    case canonicalMetadataHashMismatch
    case canonicalMetadataHashConverged
    case canonicalCreatedAtIgnoredForMetadataHash
    case canonicalModifiedAtIgnoredProcessingState
    case canonicalMacUpdatedAtRejectedAsProcessingClock
    case canonicalBusinessModifiedAtUsed
    case canonicalAudioSameHashSameSize
    case canonicalAudioMissing
    case canonicalAudioUnknown
    case canonicalAudioConflict
    case peerUnknown
    case legacyWouldUploadMetadataButCanonicalNoOp
    case canonicalPlanUsed
    case canonicalPlanFallback
    case canonicalAudioBootstrapUpload
    case canonicalAudioPeerSameNoOp
    case canonicalAudioPeerUnknownDeferred
    case canonicalGeneratedArtifactPeerSameNoOp
    case canonicalGeneratedArtifactPeerUnknownDeferred
    case canonicalGeneratedArtifactConflict
}

nonisolated struct CanonicalShadowLegacyObjectFact: Codable, Equatable, Sendable {
    var objectID: String
    var legacyMetadataHashPrefix: String?
    var audioHashPrefix: String?
    var audioByteSize: Int64?
    var audioAvailability: String
    var hasRecordingMetadata: Bool
    var hasReceiveRecord: Bool
    var hasStudyItem: Bool

    init(
        objectID: String,
        legacyMetadataHash: String? = nil,
        audioHash: String? = nil,
        audioByteSize: Int64? = nil,
        audioAvailability: String = "unknown",
        hasRecordingMetadata: Bool = false,
        hasReceiveRecord: Bool = false,
        hasStudyItem: Bool = false
    ) {
        self.objectID = objectID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.legacyMetadataHashPrefix = Self.hashPrefix(legacyMetadataHash)
        self.audioHashPrefix = Self.hashPrefix(audioHash)
        self.audioByteSize = audioByteSize
        self.audioAvailability = audioAvailability.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "unknown"
        self.hasRecordingMetadata = hasRecordingMetadata
        self.hasReceiveRecord = hasReceiveRecord
        self.hasStudyItem = hasStudyItem
    }

    static func merged(_ facts: [CanonicalShadowLegacyObjectFact]) -> [CanonicalShadowLegacyObjectFact] {
        let grouped = Dictionary(grouping: facts) { $0.objectID }
        return grouped.map { objectID, values in
            CanonicalShadowLegacyObjectFact(
                objectID: objectID,
                legacyMetadataHash: values.compactMap(\.legacyMetadataHashPrefix).first,
                audioHash: values.compactMap(\.audioHashPrefix).first,
                audioByteSize: values.compactMap(\.audioByteSize).first,
                audioAvailability: values.first { $0.audioAvailability != "unknown" }?.audioAvailability ?? "unknown",
                hasRecordingMetadata: values.contains { $0.hasRecordingMetadata },
                hasReceiveRecord: values.contains { $0.hasReceiveRecord },
                hasStudyItem: values.contains { $0.hasStudyItem }
            )
        }.sorted { $0.objectID < $1.objectID }
    }

    private static func hashPrefix(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return nil
        }
        return String(normalized.prefix(12))
    }
}

nonisolated struct CanonicalShadowLegacySnapshot: Codable, Equatable, Sendable {
    var recordingCount: Int
    var studyItemCount: Int
    var artifactCount: Int
    var objects: [CanonicalShadowLegacyObjectFact]

    init(
        recordingCount: Int,
        studyItemCount: Int,
        artifactCount: Int,
        objects: [CanonicalShadowLegacyObjectFact]
    ) {
        self.recordingCount = recordingCount
        self.studyItemCount = studyItemCount
        self.artifactCount = artifactCount
        self.objects = CanonicalShadowLegacyObjectFact.merged(objects)
    }
}

nonisolated struct CanonicalShadowArtifactSummary: Codable, Equatable, Sendable {
    var artifactID: String
    var objectID: String
    var kind: String
    var availability: String
    var hashPrefix: String?
    var hasHash: Bool
    var hasByteSize: Bool
    var byteSize: Int64?
    var logicalName: String?
}

nonisolated struct CanonicalShadowObjectSummary: Codable, Equatable, Identifiable, Sendable {
    var id: String { objectID }

    var objectID: String
    var canonicalMetadataHashPrefix: String?
    var legacyMetadataHashPrefix: String?
    var createdAt: Date?
    var modifiedAt: Date?
    var audioAvailability: String
    var audioHashPrefix: String?
    var audioHashPresent: Bool
    var audioByteSizePresent: Bool
    var audioByteSize: Int64?
    var hasRecordingMetadata: Bool
    var hasReceiveRecord: Bool
    var hasStudyItem: Bool
}

nonisolated struct CanonicalShadowMismatch: Codable, Equatable, Identifiable, Sendable {
    var id: String { [category.rawValue, objectID ?? "", artifactID ?? "", detail ?? ""].joined(separator: "|") }

    var category: CanonicalShadowMismatchCategory
    var objectID: String?
    var artifactID: String?
    var detail: String?
    var localHashPrefix: String?
    var peerHashPrefix: String?
    var localByteSize: Int64?
    var peerByteSize: Int64?
}

nonisolated struct CanonicalShadowLegacyComparison: Codable, Equatable, Sendable {
    var legacyRecordingCount: Int
    var legacyStudyItemCount: Int
    var legacyArtifactCount: Int
    var canonicalObjectCount: Int
    var canonicalArtifactCount: Int
    var metadataHashConvergedObjectIDs: [String]
    var objectSummaries: [CanonicalShadowObjectSummary]
    var artifactSummaries: [CanonicalShadowArtifactSummary]
    var mismatches: [CanonicalShadowMismatch]

    func contains(_ category: CanonicalShadowMismatchCategory, objectID: String? = nil) -> Bool {
        mismatches.contains { mismatch in
            mismatch.category == category && (objectID == nil || mismatch.objectID == objectID)
        }
    }
}

nonisolated struct CanonicalShadowReport: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var runID: String
    var syncRunID: String?
    var trigger: String?
    var nodeID: String
    var nodeRole: CanonicalShadowNodeRole
    var generatedAt: Date
    var durationMs: Double
    var manifestHashPrefix: String?
    var comparison: CanonicalShadowLegacyComparison

    var legacyRecordingCount: Int { comparison.legacyRecordingCount }
    var legacyStudyItemCount: Int { comparison.legacyStudyItemCount }
    var legacyArtifactCount: Int { comparison.legacyArtifactCount }
    var canonicalObjectCount: Int { comparison.canonicalObjectCount }
    var canonicalArtifactCount: Int { comparison.canonicalArtifactCount }
}

nonisolated struct CanonicalShadowReportBuilder {
    init() {}

    func build(
        runID: String? = nil,
        syncRunID: String? = nil,
        trigger: String? = nil,
        nodeID: String,
        nodeRole: CanonicalShadowNodeRole,
        generatedAt: Date = Date(),
        durationMs: Double,
        manifest: CanonicalManifest,
        legacy: CanonicalShadowLegacySnapshot,
        peerManifest: CanonicalManifest? = nil,
        peerLegacy: CanonicalShadowLegacySnapshot? = nil
    ) -> CanonicalShadowReport {
        let localObjectsByID = Dictionary(uniqueKeysWithValues: manifest.objects.map { ($0.objectID, $0) })
        let peerObjectsByID = Dictionary(uniqueKeysWithValues: (peerManifest?.objects ?? []).map { ($0.objectID, $0) })
        let legacyByID = Dictionary(uniqueKeysWithValues: legacy.objects.map { ($0.objectID, $0) })
        let peerLegacyByID = Dictionary(uniqueKeysWithValues: (peerLegacy?.objects ?? []).map { ($0.objectID, $0) })
        let objectIDs = Set(localObjectsByID.keys)
            .union(legacyByID.keys)
            .union(peerObjectsByID.keys)
            .union(peerLegacyByID.keys)
            .sorted()

        var convergedObjectIDs: [String] = []
        var mismatches: [CanonicalShadowMismatch] = []
        let objectSummaries = objectIDs.map { objectID in
            let object = localObjectsByID[objectID]
            let legacyFact = legacyByID[objectID]
            appendStructuralMismatches(
                objectID: objectID,
                object: object,
                legacyFact: legacyFact,
                mismatches: &mismatches
            )
            appendMetadataMismatches(
                objectID: objectID,
                localObject: object,
                peerObject: peerObjectsByID[objectID],
                localLegacy: legacyFact,
                peerLegacy: peerLegacyByID[objectID],
                nodeRole: nodeRole,
                convergedObjectIDs: &convergedObjectIDs,
                mismatches: &mismatches
            )
            appendLocalSemanticEvents(
                objectID: objectID,
                object: object,
                nodeRole: nodeRole,
                mismatches: &mismatches
            )
            appendAudioMismatches(
                objectID: objectID,
                localObject: object,
                peerLegacy: peerLegacyByID[objectID],
                peerLegacyWasProvided: peerLegacy != nil,
                mismatches: &mismatches
            )
            appendGeneratedArtifactMismatches(
                objectID: objectID,
                localObject: object,
                peerObject: peerObjectsByID[objectID],
                peerManifestWasProvided: peerManifest != nil,
                mismatches: &mismatches
            )
            return makeObjectSummary(objectID: objectID, object: object, legacyFact: legacyFact)
        }

        let artifactSummaries = manifest.objects
            .flatMap(\.artifacts)
            .sorted { $0.artifactID < $1.artifactID }
            .map(makeArtifactSummary)

        let comparison = CanonicalShadowLegacyComparison(
            legacyRecordingCount: legacy.recordingCount,
            legacyStudyItemCount: legacy.studyItemCount,
            legacyArtifactCount: legacy.artifactCount,
            canonicalObjectCount: manifest.objects.count,
            canonicalArtifactCount: manifest.objects.reduce(0) { $0 + $1.artifacts.count },
            metadataHashConvergedObjectIDs: convergedObjectIDs.sorted(),
            objectSummaries: objectSummaries,
            artifactSummaries: artifactSummaries,
            mismatches: uniqueMismatches(mismatches)
        )
        return CanonicalShadowReport(
            schemaVersion: 1,
            runID: runID ?? syncRunID ?? UUID().uuidString,
            syncRunID: syncRunID,
            trigger: trigger?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            nodeID: nodeID,
            nodeRole: nodeRole,
            generatedAt: generatedAt,
            durationMs: max(0, durationMs),
            manifestHashPrefix: Self.hashPrefix(manifest.manifestHash.value),
            comparison: comparison
        )
    }

    private func appendStructuralMismatches(
        objectID: String,
        object: CanonicalRecordingObject?,
        legacyFact: CanonicalShadowLegacyObjectFact?,
        mismatches: inout [CanonicalShadowMismatch]
    ) {
        let hasCanonicalObject: Bool
        if let _ = object {
            hasCanonicalObject = true
        } else {
            hasCanonicalObject = false
        }
        let hasLegacyFact: Bool
        if let _ = legacyFact {
            hasLegacyFact = true
        } else {
            hasLegacyFact = false
        }
        if !hasCanonicalObject, legacyFact?.hasRecordingMetadata == true || legacyFact?.hasReceiveRecord == true {
            mismatches.append(CanonicalShadowMismatch(category: .legacyRecordingMissingInCanonical, objectID: objectID))
        }
        if hasCanonicalObject, !hasLegacyFact {
            mismatches.append(CanonicalShadowMismatch(category: .canonicalObjectMissingInLegacy, objectID: objectID))
        }
        if legacyFact?.hasStudyItem == true,
           legacyFact?.hasReceiveRecord != true,
           legacyFact?.hasRecordingMetadata != true {
            mismatches.append(CanonicalShadowMismatch(category: .studyItemOnlyWithoutReceiveRecord, objectID: objectID))
        }
        if legacyFact?.hasReceiveRecord == true, legacyFact?.hasStudyItem != true {
            mismatches.append(CanonicalShadowMismatch(category: .receiveRecordOnlyWithoutStudyItem, objectID: objectID))
        }
    }

    private func appendMetadataMismatches(
        objectID: String,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?,
        localLegacy: CanonicalShadowLegacyObjectFact?,
        peerLegacy: CanonicalShadowLegacyObjectFact?,
        nodeRole: CanonicalShadowNodeRole,
        convergedObjectIDs: inout [String],
        mismatches: inout [CanonicalShadowMismatch]
    ) {
        guard let localObject, let peerObject else {
            return
        }
        let localCanonicalHash = localObject.metadataHash.value
        let peerCanonicalHash = peerObject.metadataHash.value
        if localCanonicalHash == peerCanonicalHash {
            convergedObjectIDs.append(objectID)
            mismatches.append(
                CanonicalShadowMismatch(
                    category: .canonicalMetadataHashConverged,
                    objectID: objectID,
                    detail: "metadataHashEqual",
                    localHashPrefix: Self.hashPrefix(localCanonicalHash),
                    peerHashPrefix: Self.hashPrefix(peerCanonicalHash)
                )
            )
            if localObject.metadata.createdAt != peerObject.metadata.createdAt {
                mismatches.append(
                    CanonicalShadowMismatch(
                        category: .canonicalCreatedAtIgnoredForMetadataHash,
                        objectID: objectID,
                        detail: "createdAtExcluded",
                        localHashPrefix: Self.hashPrefix(localCanonicalHash),
                        peerHashPrefix: Self.hashPrefix(peerCanonicalHash)
                    )
                )
            }
            if localObject.processingState != peerObject.processingState {
                mismatches.append(
                    CanonicalShadowMismatch(
                        category: .canonicalModifiedAtIgnoredProcessingState,
                        objectID: objectID,
                        detail: "processingStateExcluded",
                        localHashPrefix: Self.hashPrefix(localCanonicalHash),
                        peerHashPrefix: Self.hashPrefix(peerCanonicalHash)
                    )
                )
            }
            if let localLegacyHash = localLegacy?.legacyMetadataHashPrefix,
               let peerLegacyHash = peerLegacy?.legacyMetadataHashPrefix,
               localLegacyHash != peerLegacyHash {
                mismatches.append(
                    CanonicalShadowMismatch(
                        category: .legacyMetadataHashMismatchButCanonicalHashMatch,
                        objectID: objectID,
                        localHashPrefix: localLegacyHash,
                        peerHashPrefix: peerLegacyHash
                    )
                )
            }
        } else {
            mismatches.append(
                CanonicalShadowMismatch(
                    category: .canonicalMetadataHashMismatch,
                    objectID: objectID,
                    localHashPrefix: Self.hashPrefix(localCanonicalHash),
                    peerHashPrefix: Self.hashPrefix(peerCanonicalHash)
                )
            )
            if localObject.metadata.modifiedAt != peerObject.metadata.modifiedAt {
                let direction = localObject.metadata.modifiedAt > peerObject.metadata.modifiedAt ? "localNewer" : "peerNewer"
                mismatches.append(
                    CanonicalShadowMismatch(
                        category: .canonicalBusinessModifiedAtUsed,
                        objectID: objectID,
                        detail: direction,
                        localHashPrefix: Self.hashPrefix(localCanonicalHash),
                        peerHashPrefix: Self.hashPrefix(peerCanonicalHash)
                    )
                )
            }
        }
    }

    private func appendLocalSemanticEvents(
        objectID: String,
        object: CanonicalRecordingObject?,
        nodeRole: CanonicalShadowNodeRole,
        mismatches: inout [CanonicalShadowMismatch]
    ) {
        guard nodeRole == .mac,
              let object,
              object.metadata.modifiedAt == object.metadata.createdAt,
              hasProcessingSignal(object.processingState) else {
            return
        }
        mismatches.append(
            CanonicalShadowMismatch(
                category: .canonicalMacUpdatedAtRejectedAsProcessingClock,
                objectID: objectID,
                detail: "processingClockExcluded",
                localHashPrefix: Self.hashPrefix(object.metadataHash.value)
            )
        )
    }

    private func hasProcessingSignal(_ processingState: CanonicalProcessingState) -> Bool {
        processingState.transcription != .unknown && processingState.transcription != .notStarted
            || processingState.note != .unknown && processingState.note != .notStarted
    }

    private func appendAudioMismatches(
        objectID: String,
        localObject: CanonicalRecordingObject?,
        peerLegacy: CanonicalShadowLegacyObjectFact?,
        peerLegacyWasProvided: Bool,
        mismatches: inout [CanonicalShadowMismatch]
    ) {
        guard let localObject else {
            return
        }
        guard let localAudio = localObject.audioArtifact else {
            mismatches.append(CanonicalShadowMismatch(category: .canonicalAudioMissing, objectID: objectID))
            return
        }
        guard localAudio.provesCanonicalAudioAvailability,
              let localHash = localAudio.contentHash?.value,
              let localSize = localAudio.byteSize else {
            mismatches.append(
                CanonicalShadowMismatch(
                    category: .canonicalAudioUnknown,
                    objectID: objectID,
                    artifactID: localAudio.artifactID,
                    localHashPrefix: Self.hashPrefix(localAudio.contentHash?.value),
                    localByteSize: localAudio.byteSize
                )
            )
            return
        }
        guard peerLegacyWasProvided else {
            return
        }
        guard let peerLegacy else {
            mismatches.append(
                CanonicalShadowMismatch(
                    category: .peerUnknown,
                    objectID: objectID,
                    artifactID: localAudio.artifactID,
                    localHashPrefix: Self.hashPrefix(localHash),
                    localByteSize: localSize
                )
            )
            return
        }
        guard let peerHashPrefix = peerLegacy.audioHashPrefix,
              let peerSize = peerLegacy.audioByteSize else {
            mismatches.append(
                CanonicalShadowMismatch(
                    category: .canonicalAudioUnknown,
                    objectID: objectID,
                    artifactID: localAudio.artifactID,
                    localHashPrefix: Self.hashPrefix(localHash),
                    peerHashPrefix: peerLegacy.audioHashPrefix,
                    localByteSize: localSize,
                    peerByteSize: peerLegacy.audioByteSize
                )
            )
            return
        }
        let localHashPrefix = Self.hashPrefix(localHash)
        if localHashPrefix == peerHashPrefix, localSize == peerSize {
            mismatches.append(
                CanonicalShadowMismatch(
                    category: .canonicalAudioSameHashSameSize,
                    objectID: objectID,
                    artifactID: localAudio.artifactID,
                    localHashPrefix: localHashPrefix,
                    peerHashPrefix: peerHashPrefix,
                    localByteSize: localSize,
                    peerByteSize: peerSize
                )
            )
        } else {
            mismatches.append(
                CanonicalShadowMismatch(
                    category: .canonicalAudioConflict,
                    objectID: objectID,
                    artifactID: localAudio.artifactID,
                    localHashPrefix: localHashPrefix,
                    peerHashPrefix: peerHashPrefix,
                    localByteSize: localSize,
                    peerByteSize: peerSize
                )
            )
        }
    }

    private func appendGeneratedArtifactMismatches(
        objectID: String,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?,
        peerManifestWasProvided: Bool,
        mismatches: inout [CanonicalShadowMismatch]
    ) {
        guard peerManifestWasProvided else {
            return
        }
        let localArtifacts = generatedArtifactsByKind(localObject)
        let peerArtifacts = generatedArtifactsByKind(peerObject)
        let kinds = Set(localArtifacts.keys).union(peerArtifacts.keys).sorted { $0.rawValue < $1.rawValue }
        for kind in kinds {
            let localArtifact = localArtifacts[kind]
            let peerArtifact = peerArtifacts[kind]
            let artifactID = peerArtifact?.artifactID ?? localArtifact?.artifactID
            let localProven = CanonicalProjectionContract.provesGeneratedArtifactAvailability(localArtifact)
            let peerProven = CanonicalProjectionContract.provesGeneratedArtifactAvailability(peerArtifact)
            guard localProven, peerProven, let localArtifact, let peerArtifact else {
                mismatches.append(
                    CanonicalShadowMismatch(
                        category: .canonicalGeneratedArtifactPeerUnknownDeferred,
                        objectID: objectID,
                        artifactID: artifactID,
                        detail: "kind=\(kind.rawValue)",
                        localHashPrefix: Self.hashPrefix(localArtifact?.contentHash?.value),
                        peerHashPrefix: Self.hashPrefix(peerArtifact?.contentHash?.value),
                        localByteSize: localArtifact?.byteSize,
                        peerByteSize: peerArtifact?.byteSize
                    )
                )
                continue
            }
            if CanonicalProjectionContract.sameContent(localArtifact, peerArtifact) {
                mismatches.append(
                    CanonicalShadowMismatch(
                        category: .canonicalGeneratedArtifactPeerSameNoOp,
                        objectID: objectID,
                        artifactID: artifactID,
                        detail: "kind=\(kind.rawValue)",
                        localHashPrefix: Self.hashPrefix(localArtifact.contentHash?.value),
                        peerHashPrefix: Self.hashPrefix(peerArtifact.contentHash?.value),
                        localByteSize: localArtifact.byteSize,
                        peerByteSize: peerArtifact.byteSize
                    )
                )
            } else {
                mismatches.append(
                    CanonicalShadowMismatch(
                        category: .canonicalGeneratedArtifactConflict,
                        objectID: objectID,
                        artifactID: artifactID,
                        detail: "kind=\(kind.rawValue)",
                        localHashPrefix: Self.hashPrefix(localArtifact.contentHash?.value),
                        peerHashPrefix: Self.hashPrefix(peerArtifact.contentHash?.value),
                        localByteSize: localArtifact.byteSize,
                        peerByteSize: peerArtifact.byteSize
                    )
                )
            }
        }
    }

    private func generatedArtifactsByKind(_ object: CanonicalRecordingObject?) -> [CanonicalArtifact.Kind: CanonicalArtifact] {
        guard let object else {
            return [:]
        }
        return object.artifacts.reduce(into: [CanonicalArtifact.Kind: CanonicalArtifact]()) { result, artifact in
            guard CanonicalProjectionContract.generatedArtifactKinds.contains(artifact.kind) else {
                return
            }
            result[artifact.kind] = artifact
        }
    }

    private func makeObjectSummary(
        objectID: String,
        object: CanonicalRecordingObject?,
        legacyFact: CanonicalShadowLegacyObjectFact?
    ) -> CanonicalShadowObjectSummary {
        let audio = object?.audioArtifact
        return CanonicalShadowObjectSummary(
            objectID: objectID,
            canonicalMetadataHashPrefix: object.map { Self.hashPrefix($0.metadataHash.value) } ?? nil,
            legacyMetadataHashPrefix: legacyFact?.legacyMetadataHashPrefix,
            createdAt: object?.metadata.createdAt.date,
            modifiedAt: object?.metadata.modifiedAt.date,
            audioAvailability: audio?.availability.rawValue ?? legacyFact?.audioAvailability ?? "unknown",
            audioHashPrefix: audio.flatMap { Self.hashPrefix($0.contentHash?.value) } ?? legacyFact?.audioHashPrefix,
            audioHashPresent: audio?.contentHash != nil || legacyFact?.audioHashPrefix != nil,
            audioByteSizePresent: audio?.byteSize != nil || legacyFact?.audioByteSize != nil,
            audioByteSize: audio?.byteSize ?? legacyFact?.audioByteSize,
            hasRecordingMetadata: legacyFact?.hasRecordingMetadata ?? false,
            hasReceiveRecord: legacyFact?.hasReceiveRecord ?? false,
            hasStudyItem: legacyFact?.hasStudyItem ?? false
        )
    }

    private func makeArtifactSummary(_ artifact: CanonicalArtifact) -> CanonicalShadowArtifactSummary {
        CanonicalShadowArtifactSummary(
            artifactID: artifact.artifactID,
            objectID: artifact.objectID,
            kind: artifact.kind.rawValue,
            availability: artifact.availability.rawValue,
            hashPrefix: Self.hashPrefix(artifact.contentHash?.value),
            hasHash: artifact.contentHash != nil,
            hasByteSize: artifact.byteSize != nil,
            byteSize: artifact.byteSize,
            logicalName: Self.logicalName(artifact.logicalName)
        )
    }

    private func uniqueMismatches(_ mismatches: [CanonicalShadowMismatch]) -> [CanonicalShadowMismatch] {
        var seen = Set<String>()
        return mismatches.filter { mismatch in
            let key = [mismatch.category.rawValue, mismatch.objectID ?? "", mismatch.artifactID ?? "", mismatch.detail ?? ""].joined(separator: "|")
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }.sorted { left, right in
            if left.category.rawValue != right.category.rawValue {
                return left.category.rawValue < right.category.rawValue
            }
            return (left.objectID ?? "") < (right.objectID ?? "")
        }
    }

    private static func hashPrefix(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return nil
        }
        return String(normalized.prefix(12))
    }

    private static func logicalName(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        return value.split(separator: "/").last.map(String.init) ?? value
    }
}

nonisolated struct CanonicalShadowReportJSONLWriter {
    var fileManager: FileManager
    var maxReports: Int

    init(fileManager: FileManager = .default, maxReports: Int = 200) {
        self.fileManager = fileManager
        self.maxReports = max(1, maxReports)
    }

    func append(_ report: CanonicalShadowReport, to logURL: URL) throws {
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(report)
        let line = String(data: encoded, encoding: .utf8) ?? "{}"
        let existingLines: [String]
        if fileManager.fileExists(atPath: logURL.path),
           let raw = try? String(contentsOf: logURL, encoding: .utf8) {
            existingLines = raw.split(separator: "\n").map(String.init)
        } else {
            existingLines = []
        }
        let nextLines = Array((existingLines + [line]).suffix(maxReports))
        try Data((nextLines.joined(separator: "\n") + "\n").utf8).write(to: logURL, options: .atomic)
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
