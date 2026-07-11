//
//  CanonicalCore.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/1.
//

import CryptoKit
import Foundation

nonisolated struct CanonicalTimestamp: Codable, Equatable, Hashable, Comparable, Sendable {
    var date: Date

    nonisolated init(_ date: Date) {
        self.date = Self.wireNormalized(date)
    }

    private enum CodingKeys: String, CodingKey {
        case date
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = Self.wireNormalized(try container.decode(Date.self, forKey: .date))
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
    }

    nonisolated static func < (left: CanonicalTimestamp, right: CanonicalTimestamp) -> Bool {
        left.date < right.date
    }

    /// Canonical payloads use Foundation's `.iso8601` date strategy on the wire.
    /// That strategy has whole-second precision, so retaining sub-second values in
    /// the in-memory hash input makes a freshly-created manifest fail validation
    /// immediately after an encode/decode round trip.
    nonisolated private static func wireNormalized(_ date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite else {
            return date
        }
        return Date(timeIntervalSince1970: floor(seconds))
    }
}

nonisolated struct CanonicalHash: Codable, Equatable, Hashable, Sendable {
    var algorithm: String
    var value: String

    nonisolated init(_ value: String, algorithm: String = "sha256") {
        self.algorithm = algorithm
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated static func sha256<Value: Encodable>(of value: Value) -> CanonicalHash {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data()
        return sha256(data: data)
    }

    nonisolated static func sha256String(_ value: String) -> CanonicalHash {
        sha256(data: Data(value.utf8))
    }

    nonisolated private static func sha256(data: Data) -> CanonicalHash {
        let digest = SHA256.hash(data: data)
        return CanonicalHash(digest.map { String(format: "%02x", $0) }.joined())
    }
}

nonisolated enum CanonicalCapability: String, Codable, Equatable, CaseIterable, Sendable {
    case recordingMetadata
    case audioArtifact
    case receiveRecord
    case transcriptArtifact
    case noteArtifact
    case summaryArtifact
    case objectProjection
    case canonicalLibraryObjectsV1
    case canonicalFolderObjectsV1
    case canonicalStudyItemObjectsV1
    case canonicalTransferStateV1
    case canonicalObjectProjectionV1
    case canonicalInventoryBuilderV1
    case canonicalRetirementReadinessV1
}

nonisolated struct CanonicalNode: Codable, Equatable, Identifiable, Sendable {
    var id: String { nodeID }

    var nodeID: String
    var platform: String
    var displayName: String?
    var capabilities: [CanonicalCapability]

    nonisolated init(
        nodeID: String,
        platform: String,
        displayName: String? = nil,
        capabilities: [CanonicalCapability] = []
    ) {
        self.nodeID = nodeID
        self.platform = platform
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.capabilities = capabilities.sorted { $0.rawValue < $1.rawValue }
    }
}

nonisolated struct CanonicalRecordingMetadata: Codable, Equatable, Sendable {
    nonisolated static let businessMetadataHashSchemaVersion = "canonical-recording-business-metadata-v1"

    struct Filing: Codable, Equatable, Hashable, Sendable {
        var type: String?
        var subject: String?
        var chapter: String?
        var topic: String?

        nonisolated init(type: String? = nil, subject: String? = nil, chapter: String? = nil, topic: String? = nil) {
            self.type = Self.normalized(type)
            self.subject = Self.normalized(subject)
            self.chapter = Self.normalized(chapter)
            self.topic = Self.normalized(topic)
        }

        nonisolated var isEmpty: Bool {
            type == nil && subject == nil && chapter == nil && topic == nil
        }

        nonisolated private static func normalized(_ value: String?) -> String? {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
    }

    // objectID is the stable cross-device identity for the same recording.
    var objectID: String
    var title: String
    // createdAt is the recording creation time. It is not Mac receivedAt.
    var createdAt: CanonicalTimestamp
    // modifiedAt is the business metadata clock for LWW. Local receivedAt/observedAt must not feed it.
    var modifiedAt: CanonicalTimestamp
    var duration: TimeInterval?
    var filing: Filing?
    var tags: [String]
    var isDeleted: Bool
    var deletedAt: CanonicalTimestamp?

    nonisolated init(
        objectID: String,
        title: String,
        createdAt: CanonicalTimestamp,
        modifiedAt: CanonicalTimestamp,
        duration: TimeInterval? = nil,
        filing: Filing? = nil,
        tags: [String] = [],
        isDeleted: Bool = false,
        deletedAt: CanonicalTimestamp? = nil
    ) {
        self.objectID = Self.normalizedRequired(objectID, fallback: "unknown-recording")
        self.title = Self.normalizedRequiredPreservingInput(title, fallback: "未命名录音")
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.duration = duration
        self.filing = filing?.isEmpty == true ? nil : filing
        self.tags = Self.normalizedTags(tags)
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }

    // metadataHash hashes only canonical business fields that define user-visible
    // recording metadata equality. It intentionally excludes createdAt, modifiedAt,
    // duration, upload/receive/processing state, ledgers, local paths, audio facts,
    // diagnostics, receivedAt, and observedAt.
    nonisolated var metadataHash: CanonicalHash {
        CanonicalHash.sha256(of: [
            "schema": Self.businessMetadataHashSchemaVersion,
            "objectID": objectID,
            "title": title,
            "filing.type": filing?.type ?? "",
            "filing.subject": filing?.subject ?? "",
            "filing.chapter": filing?.chapter ?? "",
            "filing.topic": filing?.topic ?? "",
            "tags": tags.joined(separator: "\u{1F}"),
            "isDeleted": isDeleted ? "true" : "false",
            "deletedAt": deletedAt.map(Self.timestampString) ?? ""
        ])
    }

    nonisolated private static func normalizedRequired(_ value: String, fallback: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallback
    }

    nonisolated private static func normalizedRequiredPreservingInput(_ value: String, fallback: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
    }

    nonisolated private static func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.compactMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.lowercased()
        })).sorted()
    }

    nonisolated private static func timestampString(_ timestamp: CanonicalTimestamp) -> String {
        numberString(timestamp.date.timeIntervalSince1970)
    }

    nonisolated private static func numberString(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

nonisolated struct CanonicalRecordingMetadataBusinessFields: Codable, Equatable, Sendable {
    var objectID: String
    var title: String
    var createdAt: CanonicalTimestamp
    var modifiedAt: CanonicalTimestamp
    var duration: TimeInterval?
    var filing: CanonicalRecordingMetadata.Filing?
    var tags: [String]
    var isDeleted: Bool
    var deletedAt: CanonicalTimestamp?

    nonisolated init(metadata: CanonicalRecordingMetadata) {
        self.objectID = metadata.objectID
        self.title = metadata.title
        self.createdAt = metadata.createdAt
        self.modifiedAt = metadata.modifiedAt
        self.duration = metadata.duration
        self.filing = metadata.filing
        self.tags = metadata.tags
        self.isDeleted = metadata.isDeleted
        self.deletedAt = metadata.deletedAt
    }

    nonisolated init(
        objectID: String,
        title: String,
        createdAt: CanonicalTimestamp,
        modifiedAt: CanonicalTimestamp,
        duration: TimeInterval? = nil,
        filing: CanonicalRecordingMetadata.Filing? = nil,
        tags: [String] = [],
        isDeleted: Bool = false,
        deletedAt: CanonicalTimestamp? = nil
    ) {
        self.init(metadata: CanonicalRecordingMetadata(
            objectID: objectID,
            title: title,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            duration: duration,
            filing: filing,
            tags: tags,
            isDeleted: isDeleted,
            deletedAt: deletedAt
        ))
    }

    nonisolated var canonicalMetadata: CanonicalRecordingMetadata {
        CanonicalRecordingMetadata(
            objectID: objectID,
            title: title,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            duration: duration,
            filing: filing,
            tags: tags,
            isDeleted: isDeleted,
            deletedAt: deletedAt
        )
    }

    nonisolated var stableBusinessHashInput: [String: String] {
        [
            "schema": CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
            "objectID": objectID,
            "title": title,
            "filing.type": filing?.type ?? "",
            "filing.subject": filing?.subject ?? "",
            "filing.chapter": filing?.chapter ?? "",
            "filing.topic": filing?.topic ?? "",
            "tags": tags.joined(separator: "\u{1F}"),
            "isDeleted": isDeleted ? "true" : "false",
            "deletedAt": deletedAt.map(Self.timestampString) ?? ""
        ]
    }

    nonisolated var metadataHash: CanonicalHash {
        CanonicalRecordingMetadataHashSchema.v1.hash(self)
    }

    private nonisolated static func timestampString(_ timestamp: CanonicalTimestamp) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), timestamp.date.timeIntervalSince1970)
    }
}

nonisolated struct CanonicalRecordingMetadataHashSchema: Codable, Equatable, Sendable {
    static let version = CanonicalRecordingMetadata.businessMetadataHashSchemaVersion
    static let v1 = CanonicalRecordingMetadataHashSchema()

    var schemaVersion: String
    var includedStableBusinessFields: [String]
    var excludedFields: [String]

    nonisolated init(
        schemaVersion: String = CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
        includedStableBusinessFields: [String] = [
            "schema",
            "objectID",
            "title",
            "filing.type",
            "filing.subject",
            "filing.chapter",
            "filing.topic",
            "tags",
            "isDeleted",
            "deletedAt"
        ],
        excludedFields: [String] = [
            "createdAt",
            "modifiedAt",
            "duration",
            "uploadProgress",
            "uploadLedgerState",
            "receiveStatus",
            "receivedAt",
            "observedAt",
            "localPath",
            "audioFilePath",
            "audioHash",
            "audioByteSize",
            "transcriptContent",
            "noteContent",
            "summaryContent",
            "processingStatus",
            "diagnostics",
            "providerResponse"
        ]
    ) {
        self.schemaVersion = schemaVersion
        self.includedStableBusinessFields = includedStableBusinessFields
        self.excludedFields = excludedFields
    }

    nonisolated func hash(_ fields: CanonicalRecordingMetadataBusinessFields) -> CanonicalHash {
        CanonicalHash.sha256(of: fields.stableBusinessHashInput)
    }
}

nonisolated enum CanonicalRecordingMetadataDecisionAction: String, Codable, Equatable, Sendable {
    case legacyFallback
    case noOp
    case sendLocal
    case applyPeer
    case deferTie
    case conflictBlocked
}

nonisolated struct CanonicalRecordingMetadataDecisionInput: Codable, Equatable, Sendable {
    var local: CanonicalRecordingMetadata?
    var peer: CanonicalRecordingMetadata?
    var localSchemaVersion: String
    var peerSchemaVersion: String?
    var businessModifiedAtAvailable: Bool

    nonisolated init(
        local: CanonicalRecordingMetadata?,
        peer: CanonicalRecordingMetadata?,
        localSchemaVersion: String = CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
        peerSchemaVersion: String? = CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
        businessModifiedAtAvailable: Bool = true
    ) {
        self.local = local
        self.peer = peer
        self.localSchemaVersion = localSchemaVersion
        self.peerSchemaVersion = peerSchemaVersion
        self.businessModifiedAtAvailable = businessModifiedAtAvailable
    }
}

nonisolated struct CanonicalRecordingMetadataDecisionResult: Codable, Equatable, Sendable {
    var action: CanonicalRecordingMetadataDecisionAction
    var reason: String
    var localHashPrefix: String?
    var peerHashPrefix: String?
    var hashEqual: Bool
    var hashChanged: Bool
    var lwwApplied: Bool

    nonisolated init(
        action: CanonicalRecordingMetadataDecisionAction,
        reason: String,
        localHash: CanonicalHash? = nil,
        peerHash: CanonicalHash? = nil,
        hashEqual: Bool = false,
        hashChanged: Bool = false,
        lwwApplied: Bool = false
    ) {
        self.action = action
        self.reason = reason
        self.localHashPrefix = localHash?.value.shortCanonicalPrefix
        self.peerHashPrefix = peerHash?.value.shortCanonicalPrefix
        self.hashEqual = hashEqual
        self.hashChanged = hashChanged
        self.lwwApplied = lwwApplied
    }
}

nonisolated struct CanonicalRecordingMetadataModifiedAtPolicy: Codable, Equatable, Sendable {
    enum MissingBusinessModifiedAtPolicy: String, Codable, Equatable, Sendable {
        case blockPrimaryUnlessDocumentedFallback
        case allowDocumentedFallback
    }

    enum EqualModifiedAtTiePolicy: String, Codable, Equatable, Sendable {
        case deferAsConflict
    }

    static let current = CanonicalRecordingMetadataModifiedAtPolicy()

    var clockSource: String
    var missingBusinessModifiedAtPolicy: MissingBusinessModifiedAtPolicy
    var equalModifiedAtTiePolicy: EqualModifiedAtTiePolicy

    nonisolated init(
        clockSource: String = "businessModifiedAt",
        missingBusinessModifiedAtPolicy: MissingBusinessModifiedAtPolicy = .blockPrimaryUnlessDocumentedFallback,
        equalModifiedAtTiePolicy: EqualModifiedAtTiePolicy = .deferAsConflict
    ) {
        self.clockSource = clockSource
        self.missingBusinessModifiedAtPolicy = missingBusinessModifiedAtPolicy
        self.equalModifiedAtTiePolicy = equalModifiedAtTiePolicy
    }

    nonisolated func decide(_ input: CanonicalRecordingMetadataDecisionInput) -> CanonicalRecordingMetadataDecisionResult {
        guard input.localSchemaVersion == CanonicalRecordingMetadataHashSchema.version,
              input.peerSchemaVersion == nil || input.peerSchemaVersion == CanonicalRecordingMetadataHashSchema.version else {
            return CanonicalRecordingMetadataDecisionResult(action: .legacyFallback, reason: "schemaMismatch")
        }
        guard input.businessModifiedAtAvailable || missingBusinessModifiedAtPolicy == .allowDocumentedFallback else {
            return CanonicalRecordingMetadataDecisionResult(action: .legacyFallback, reason: "businessModifiedAtUnavailable")
        }
        guard let local = input.local else {
            return CanonicalRecordingMetadataDecisionResult(action: .legacyFallback, reason: "localSnapshotMissing")
        }
        guard let peer = input.peer else {
            return CanonicalRecordingMetadataDecisionResult(action: .legacyFallback, reason: "peerSnapshotMissing")
        }

        let localHash = local.metadataHash
        let peerHash = peer.metadataHash
        if localHash == peerHash {
            return CanonicalRecordingMetadataDecisionResult(
                action: .noOp,
                reason: "metadataHashEqual",
                localHash: localHash,
                peerHash: peerHash,
                hashEqual: true
            )
        }

        if local.modifiedAt > peer.modifiedAt {
            return CanonicalRecordingMetadataDecisionResult(
                action: .sendLocal,
                reason: "localBusinessModifiedAtNewer",
                localHash: localHash,
                peerHash: peerHash,
                hashChanged: true,
                lwwApplied: true
            )
        }
        if peer.modifiedAt > local.modifiedAt {
            return CanonicalRecordingMetadataDecisionResult(
                action: .applyPeer,
                reason: "peerBusinessModifiedAtNewer",
                localHash: localHash,
                peerHash: peerHash,
                hashChanged: true,
                lwwApplied: true
            )
        }
        return CanonicalRecordingMetadataDecisionResult(
            action: .deferTie,
            reason: "equalBusinessModifiedAtTieDeferred",
            localHash: localHash,
            peerHash: peerHash,
            hashChanged: true
        )
    }
}

nonisolated struct CanonicalArtifact: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
        case audio
        case metadata
        case receiveRecord
        case transcriptJSON
        case transcriptMarkdown
        case noteMarkdown
        case noteJSON
        case summaryJSON

        nonisolated func artifactID(for objectID: String) -> String {
            "\(rawValue):\(objectID)"
        }
    }

    enum Availability: String, Codable, Equatable, Sendable {
        case unknown
        case missing
        case availableWithoutHash
        case available
    }

    var id: String { artifactID }

    var artifactID: String
    var objectID: String
    var kind: Kind
    var availability: Availability
    var contentHash: CanonicalHash?
    var byteSize: Int64?
    var logicalName: String?
    var logicalPathToken: String?
    var modifiedAt: CanonicalTimestamp?
    // observedAt is node-local observation time and never participates in metadataHash or LWW.
    var observedAt: CanonicalTimestamp?
    var producedBy: CanonicalArtifactProducer?
    var producedByNodeID: String?
    var tombstone: Bool?

    nonisolated init(
        artifactID: String,
        objectID: String,
        kind: Kind,
        availability: Availability,
        contentHash: CanonicalHash? = nil,
        byteSize: Int64? = nil,
        logicalName: String? = nil,
        logicalPathToken: String? = nil,
        modifiedAt: CanonicalTimestamp? = nil,
        observedAt: CanonicalTimestamp? = nil,
        producedBy: CanonicalArtifactProducer? = nil,
        producedByNodeID: String? = nil,
        tombstone: Bool? = nil
    ) {
        self.artifactID = artifactID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? kind.artifactID(for: objectID)
        self.objectID = objectID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.availability = availability
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.logicalName = logicalName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.logicalPathToken = CanonicalProjectionContract.safeLogicalPathToken(logicalPathToken)
        self.modifiedAt = modifiedAt
        self.observedAt = observedAt
        self.producedBy = producedBy
        self.producedByNodeID = producedByNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.tombstone = tombstone
    }

    nonisolated var provesCanonicalAudioAvailability: Bool {
        kind == .audio && availability == .available && contentHash != nil && byteSize != nil && tombstone != true
    }

    nonisolated var provesCanonicalGeneratedArtifactAvailability: Bool {
        CanonicalProjectionContract.provesGeneratedArtifactAvailability(self)
    }

    nonisolated var isCanonicalGeneratedArtifact: Bool {
        CanonicalProjectionContract.generatedArtifactKinds.contains(kind)
    }
}

typealias CanonicalGeneratedArtifactKind = CanonicalArtifact.Kind
typealias CanonicalGeneratedArtifactAvailability = CanonicalArtifact.Availability

nonisolated struct CanonicalGeneratedArtifactBusinessFields: Codable, Equatable, Sendable {
    var artifactID: String
    var objectID: String
    var kind: CanonicalGeneratedArtifactKind
    var availability: CanonicalGeneratedArtifactAvailability
    var contentHash: CanonicalHash?
    var byteSize: Int64?
    var businessModifiedAt: CanonicalTimestamp?

    nonisolated init?(
        artifact: CanonicalArtifact
    ) {
        guard CanonicalProjectionContract.generatedArtifactKinds.contains(artifact.kind),
              artifact.tombstone != true else {
            return nil
        }
        self.artifactID = artifact.artifactID
        self.objectID = artifact.objectID
        self.kind = artifact.kind
        self.availability = artifact.availability
        self.contentHash = artifact.contentHash
        self.byteSize = artifact.byteSize
        self.businessModifiedAt = artifact.modifiedAt
    }

    nonisolated var stableBusinessHashInput: [String: String] {
        [
            "schema": CanonicalGeneratedArtifactHashSchema.version,
            "artifactID": artifactID,
            "objectID": objectID,
            "kind": kind.rawValue,
            "availability": availability.rawValue,
            "contentHash.algorithm": contentHash?.algorithm ?? "",
            "contentHash.value": contentHash?.value ?? "",
            "byteSize": byteSize.map(String.init) ?? "",
            "businessModifiedAt": businessModifiedAt.map(Self.timestampString) ?? ""
        ]
    }

    private nonisolated static func timestampString(_ timestamp: CanonicalTimestamp) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), timestamp.date.timeIntervalSince1970)
    }
}

nonisolated struct CanonicalGeneratedArtifactHashSchema: Codable, Equatable, Sendable {
    static let version = "canonical-generated-artifact-v1"
    static let v1 = CanonicalGeneratedArtifactHashSchema()

    var schemaVersion: String
    var includedStableBusinessFields: [String]
    var excludedFields: [String]

    nonisolated init(
        schemaVersion: String = CanonicalGeneratedArtifactHashSchema.version,
        includedStableBusinessFields: [String] = [
            "schema",
            "artifactID",
            "objectID",
            "kind",
            "availability",
            "contentHash.algorithm",
            "contentHash.value",
            "byteSize",
            "businessModifiedAt"
        ],
        excludedFields: [String] = [
            "logicalName",
            "logicalPathToken",
            "localPath",
            "absolutePath",
            "observedAt",
            "producedByNodeID",
            "providerRequest",
            "providerResponse",
            "transcriptContent",
            "noteContent",
            "summaryContent",
            "diagnostics",
            "uploadLedgerState",
            "receiveStatus",
            "audioBytes",
            "securitySecret",
            "tombstone"
        ]
    ) {
        self.schemaVersion = schemaVersion
        self.includedStableBusinessFields = includedStableBusinessFields
        self.excludedFields = excludedFields
    }

    nonisolated func hash(_ fields: CanonicalGeneratedArtifactBusinessFields) -> CanonicalHash {
        CanonicalHash.sha256(of: fields.stableBusinessHashInput)
    }
}

extension CanonicalArtifact {
    nonisolated var generatedArtifactBusinessHash: CanonicalHash? {
        CanonicalGeneratedArtifactBusinessFields(artifact: self).map {
            CanonicalGeneratedArtifactHashSchema.v1.hash($0)
        }
    }
}

nonisolated enum CanonicalGeneratedArtifactDecisionAction: String, Codable, Equatable, Sendable {
    case legacyFallback
    case noOp
    case sendLocal
    case applyPeer
    case deferMissingContent
    case deferTie
    case conflictBlocked
    case unsupportedKindBlocked
}

nonisolated struct CanonicalGeneratedArtifactDecisionInput: Codable, Equatable, Sendable {
    var local: CanonicalArtifact?
    var peer: CanonicalArtifact?
    var localSchemaVersion: String
    var peerSchemaVersion: String?
    var businessModifiedAtAvailable: Bool

    nonisolated init(
        local: CanonicalArtifact?,
        peer: CanonicalArtifact?,
        localSchemaVersion: String = CanonicalGeneratedArtifactHashSchema.version,
        peerSchemaVersion: String? = CanonicalGeneratedArtifactHashSchema.version,
        businessModifiedAtAvailable: Bool = true
    ) {
        self.local = local
        self.peer = peer
        self.localSchemaVersion = localSchemaVersion
        self.peerSchemaVersion = peerSchemaVersion
        self.businessModifiedAtAvailable = businessModifiedAtAvailable
    }
}

nonisolated struct CanonicalGeneratedArtifactDecisionResult: Codable, Equatable, Sendable {
    var action: CanonicalGeneratedArtifactDecisionAction
    var reason: String
    var localHashPrefix: String?
    var peerHashPrefix: String?
    var hashEqual: Bool
    var hashChanged: Bool
    var lwwApplied: Bool
    var contentMissing: Bool
    var providerResponseIgnored: Bool

    nonisolated init(
        action: CanonicalGeneratedArtifactDecisionAction,
        reason: String,
        localHash: CanonicalHash? = nil,
        peerHash: CanonicalHash? = nil,
        hashEqual: Bool = false,
        hashChanged: Bool = false,
        lwwApplied: Bool = false,
        contentMissing: Bool = false,
        providerResponseIgnored: Bool = true
    ) {
        self.action = action
        self.reason = reason
        self.localHashPrefix = localHash?.value.shortCanonicalPrefix
        self.peerHashPrefix = peerHash?.value.shortCanonicalPrefix
        self.hashEqual = hashEqual
        self.hashChanged = hashChanged
        self.lwwApplied = lwwApplied
        self.contentMissing = contentMissing
        self.providerResponseIgnored = providerResponseIgnored
    }
}

nonisolated struct CanonicalGeneratedArtifactModifiedAtPolicy: Codable, Equatable, Sendable {
    enum MissingBusinessModifiedAtPolicy: String, Codable, Equatable, Sendable {
        case blockPrimaryUnlessDocumentedFallback
        case allowDocumentedFallback
    }

    enum EqualModifiedAtTiePolicy: String, Codable, Equatable, Sendable {
        case deferAsConflict
    }

    static let current = CanonicalGeneratedArtifactModifiedAtPolicy()

    var clockSource: String
    var missingBusinessModifiedAtPolicy: MissingBusinessModifiedAtPolicy
    var equalModifiedAtTiePolicy: EqualModifiedAtTiePolicy

    nonisolated init(
        clockSource: String = "businessModifiedAt",
        missingBusinessModifiedAtPolicy: MissingBusinessModifiedAtPolicy = .blockPrimaryUnlessDocumentedFallback,
        equalModifiedAtTiePolicy: EqualModifiedAtTiePolicy = .deferAsConflict
    ) {
        self.clockSource = clockSource
        self.missingBusinessModifiedAtPolicy = missingBusinessModifiedAtPolicy
        self.equalModifiedAtTiePolicy = equalModifiedAtTiePolicy
    }

    nonisolated func decide(_ input: CanonicalGeneratedArtifactDecisionInput) -> CanonicalGeneratedArtifactDecisionResult {
        guard input.localSchemaVersion == CanonicalGeneratedArtifactHashSchema.version,
              input.peerSchemaVersion == nil || input.peerSchemaVersion == CanonicalGeneratedArtifactHashSchema.version else {
            return CanonicalGeneratedArtifactDecisionResult(action: .legacyFallback, reason: "schemaMismatch")
        }
        guard input.businessModifiedAtAvailable || missingBusinessModifiedAtPolicy == .allowDocumentedFallback else {
            return CanonicalGeneratedArtifactDecisionResult(action: .legacyFallback, reason: "businessModifiedAtUnavailable")
        }
        guard [input.local, input.peer].compactMap({ $0 }).allSatisfy(Self.isSupportedGeneratedArtifact) else {
            return CanonicalGeneratedArtifactDecisionResult(action: .unsupportedKindBlocked, reason: "unsupportedGeneratedArtifactKind")
        }

        switch (input.local, input.peer) {
        case (.none, .none):
            return CanonicalGeneratedArtifactDecisionResult(action: .legacyFallback, reason: "artifactSnapshotsMissing")
        case let (.some(local), .none):
            let localHash = local.generatedArtifactBusinessHash
            guard Self.provesAvailability(local) else {
                return CanonicalGeneratedArtifactDecisionResult(action: .deferMissingContent, reason: "localContentMissing", localHash: localHash, contentMissing: true)
            }
            guard local.modifiedAt != nil || missingBusinessModifiedAtPolicy == .allowDocumentedFallback else {
                return CanonicalGeneratedArtifactDecisionResult(action: .conflictBlocked, reason: "artifactModifiedAtUnavailable", localHash: localHash, hashChanged: true)
            }
            return CanonicalGeneratedArtifactDecisionResult(action: .sendLocal, reason: "peerArtifactMissing", localHash: localHash, hashChanged: true, lwwApplied: true)
        case let (.none, .some(peer)):
            let peerHash = peer.generatedArtifactBusinessHash
            guard Self.provesAvailability(peer) else {
                return CanonicalGeneratedArtifactDecisionResult(action: .deferMissingContent, reason: "peerContentMissing", peerHash: peerHash, contentMissing: true)
            }
            guard peer.modifiedAt != nil || missingBusinessModifiedAtPolicy == .allowDocumentedFallback else {
                return CanonicalGeneratedArtifactDecisionResult(action: .conflictBlocked, reason: "artifactModifiedAtUnavailable", peerHash: peerHash, hashChanged: true)
            }
            return CanonicalGeneratedArtifactDecisionResult(action: .applyPeer, reason: "localArtifactMissing", peerHash: peerHash, hashChanged: true, lwwApplied: true)
        case let (.some(local), .some(peer)):
            let localHash = local.generatedArtifactBusinessHash
            let peerHash = peer.generatedArtifactBusinessHash
            guard local.objectID == peer.objectID, local.kind == peer.kind else {
                return CanonicalGeneratedArtifactDecisionResult(action: .conflictBlocked, reason: "artifactIdentityMismatch", localHash: localHash, peerHash: peerHash, hashChanged: true)
            }
            guard Self.provesAvailability(local), Self.provesAvailability(peer) else {
                return CanonicalGeneratedArtifactDecisionResult(action: .deferMissingContent, reason: "artifactContentMissing", localHash: localHash, peerHash: peerHash, contentMissing: true)
            }
            if CanonicalProjectionContract.sameContent(local, peer) {
                return CanonicalGeneratedArtifactDecisionResult(action: .noOp, reason: "contentHashAndByteSizeEqual", localHash: localHash, peerHash: peerHash, hashEqual: localHash == peerHash, hashChanged: localHash != peerHash)
            }
            guard let localModifiedAt = local.modifiedAt,
                  let peerModifiedAt = peer.modifiedAt else {
                return CanonicalGeneratedArtifactDecisionResult(action: .conflictBlocked, reason: "artifactModifiedAtUnavailable", localHash: localHash, peerHash: peerHash, hashChanged: true)
            }
            if localModifiedAt > peerModifiedAt {
                return CanonicalGeneratedArtifactDecisionResult(action: .sendLocal, reason: "localArtifactNewer", localHash: localHash, peerHash: peerHash, hashChanged: true, lwwApplied: true)
            }
            if peerModifiedAt > localModifiedAt {
                return CanonicalGeneratedArtifactDecisionResult(action: .applyPeer, reason: "peerArtifactNewer", localHash: localHash, peerHash: peerHash, hashChanged: true, lwwApplied: true)
            }
            return CanonicalGeneratedArtifactDecisionResult(action: .deferTie, reason: "equalArtifactModifiedAtTieDeferred", localHash: localHash, peerHash: peerHash, hashChanged: true)
        }
    }

    private nonisolated static func isSupportedGeneratedArtifact(_ artifact: CanonicalArtifact) -> Bool {
        CanonicalProjectionContract.generatedArtifactKinds.contains(artifact.kind) && artifact.tombstone != true
    }

    private nonisolated static func provesAvailability(_ artifact: CanonicalArtifact) -> Bool {
        CanonicalProjectionContract.provesGeneratedArtifactAvailability(artifact)
    }
}

nonisolated struct CanonicalArtifactFact: Codable, Equatable, Sendable {
    var kind: CanonicalArtifact.Kind
    var availability: CanonicalArtifact.Availability
    var contentHash: CanonicalHash?
    var byteSize: Int64?
    var logicalName: String?
    var logicalPathToken: String?
    var modifiedAt: CanonicalTimestamp?
    var observedAt: CanonicalTimestamp?
    var producedBy: CanonicalArtifactProducer?
    var producedByNodeID: String?
    var tombstone: Bool?

    nonisolated init(
        kind: CanonicalArtifact.Kind,
        availability: CanonicalArtifact.Availability,
        contentHash: CanonicalHash? = nil,
        byteSize: Int64? = nil,
        logicalName: String? = nil,
        logicalPathToken: String? = nil,
        modifiedAt: CanonicalTimestamp? = nil,
        observedAt: CanonicalTimestamp? = nil,
        producedBy: CanonicalArtifactProducer? = nil,
        producedByNodeID: String? = nil,
        tombstone: Bool? = nil
    ) {
        self.kind = kind
        self.availability = availability
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.logicalName = logicalName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.logicalPathToken = CanonicalProjectionContract.safeLogicalPathToken(logicalPathToken)
        self.modifiedAt = modifiedAt
        self.observedAt = observedAt
        self.producedBy = producedBy
        self.producedByNodeID = producedByNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.tombstone = tombstone
    }

    nonisolated static func audio(
        availability: CanonicalArtifact.Availability,
        contentHash: CanonicalHash? = nil,
        byteSize: Int64? = nil,
        logicalName: String? = nil,
        logicalPathToken: String? = nil,
        modifiedAt: CanonicalTimestamp? = nil,
        observedAt: CanonicalTimestamp? = nil,
        producedByNodeID: String? = nil
    ) -> CanonicalArtifactFact {
        CanonicalArtifactFact(
            kind: .audio,
            availability: availability,
            contentHash: contentHash,
            byteSize: byteSize,
            logicalName: logicalName,
            logicalPathToken: logicalPathToken,
            modifiedAt: modifiedAt,
            observedAt: observedAt,
            producedBy: .audioCapture,
            producedByNodeID: producedByNodeID
        )
    }

    nonisolated func makeArtifact(objectID: String, producedByNodeID fallbackProducedByNodeID: String? = nil) -> CanonicalArtifact {
        CanonicalArtifact(
            artifactID: CanonicalProjectionContract.artifactID(objectID: objectID, kind: kind),
            objectID: objectID,
            kind: kind,
            availability: availability,
            contentHash: contentHash,
            byteSize: byteSize,
            logicalName: logicalName,
            logicalPathToken: logicalPathToken,
            modifiedAt: modifiedAt,
            observedAt: observedAt,
            producedBy: producedBy,
            producedByNodeID: producedByNodeID ?? fallbackProducedByNodeID,
            tombstone: tombstone
        )
    }
}

nonisolated enum CanonicalSyncState: String, Codable, Equatable, Sendable {
    case unknown
    case localOnly
    case synced
    case diverged
    case deleted
    case conflict
}

nonisolated enum CanonicalTransferState: String, Codable, Equatable, Sendable {
    case none
    case queued
    case inFlight
    case retryPending
    case completed
    case failed
    case conflict
}

nonisolated struct CanonicalProcessingState: Codable, Equatable, Sendable {
    enum Stage: String, Codable, Equatable, Sendable {
        case notStarted
        case queued
        case processing
        case completed
        case failed
        case unknown
    }

    var transcription: Stage
    var note: Stage

    nonisolated static let unknown = CanonicalProcessingState(transcription: .unknown, note: .unknown)
}

nonisolated struct CanonicalRecordingObject: Codable, Equatable, Identifiable, Sendable {
    var id: String { objectID }

    var objectID: String
    var nodeID: String?
    var metadata: CanonicalRecordingMetadata {
        didSet {
            metadataHash = metadata.metadataHash
        }
    }
    var metadataHash: CanonicalHash
    var artifacts: [CanonicalArtifact]
    var syncState: CanonicalSyncState
    var transferState: CanonicalTransferState
    var processingState: CanonicalProcessingState
    var receivedAt: CanonicalTimestamp?
    var observedAt: CanonicalTimestamp?

    nonisolated init(
        objectID: String,
        nodeID: String? = nil,
        metadata: CanonicalRecordingMetadata,
        artifacts: [CanonicalArtifact] = [],
        syncState: CanonicalSyncState = .unknown,
        transferState: CanonicalTransferState = .none,
        processingState: CanonicalProcessingState = .unknown,
        receivedAt: CanonicalTimestamp? = nil,
        observedAt: CanonicalTimestamp? = nil
    ) {
        self.objectID = objectID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? metadata.objectID
        self.nodeID = nodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.metadata = metadata
        self.metadataHash = metadata.metadataHash
        self.artifacts = artifacts.sorted { $0.artifactID < $1.artifactID }
        self.syncState = syncState
        self.transferState = transferState
        self.processingState = processingState
        self.receivedAt = receivedAt
        self.observedAt = observedAt
    }

    nonisolated var audioArtifact: CanonicalArtifact? {
        artifacts.first { $0.kind == .audio }
    }

    // audioAvailable is proven only by canonical audio artifact availability + byteSize + contentHash.
    nonisolated var audioAvailable: Bool {
        audioArtifact?.provesCanonicalAudioAvailability == true
    }

    nonisolated func replacingArtifacts(_ artifacts: [CanonicalArtifact]) -> CanonicalRecordingObject {
        CanonicalRecordingObject(
            objectID: objectID,
            nodeID: nodeID,
            metadata: metadata,
            artifacts: artifacts,
            syncState: syncState,
            transferState: transferState,
            processingState: processingState,
            receivedAt: receivedAt,
            observedAt: observedAt
        )
    }
}

nonisolated struct CanonicalManifest: Codable, Equatable, Sendable {
    nonisolated static let currentSchemaVersion = 1

    var schemaVersion: Int
    var node: CanonicalNode
    var generatedAt: CanonicalTimestamp
    var objects: [CanonicalRecordingObject]
    var libraryObjects: [CanonicalLibraryObject]
    var folders: [CanonicalFolderObject]
    var studyItems: [CanonicalStudyItemObject]
    var standaloneNotes: [CanonicalStandaloneNoteObject]
    var libraryTombstones: [CanonicalLibraryTombstone]
    var manifestCapabilities: [CanonicalCapability]
    var manifestHash: CanonicalHash

    nonisolated static func make(
        node: CanonicalNode,
        generatedAt: Date = Date(),
        objects: [CanonicalRecordingObject],
        libraryObjects: [CanonicalLibraryObject] = [],
        folders: [CanonicalFolderObject] = [],
        studyItems: [CanonicalStudyItemObject] = [],
        standaloneNotes: [CanonicalStandaloneNoteObject] = [],
        libraryTombstones: [CanonicalLibraryTombstone] = [],
        manifestCapabilities: [CanonicalCapability] = []
    ) -> CanonicalManifest {
        let sortedObjects = objects.sorted { $0.objectID < $1.objectID }
        let sortedLibraryObjects = libraryObjects.sorted { $0.objectID.rawValue < $1.objectID.rawValue }
        let sortedFolders = folders.sorted { $0.folderID.rawValue < $1.folderID.rawValue }
        let sortedStudyItems = studyItems.sorted { $0.itemID.rawValue < $1.itemID.rawValue }
        let sortedStandaloneNotes = standaloneNotes.sorted { $0.noteID.rawValue < $1.noteID.rawValue }
        let sortedTombstones = libraryTombstones.sorted { $0.tombstoneID < $1.tombstoneID }
        var manifest = CanonicalManifest(
            schemaVersion: currentSchemaVersion,
            node: node,
            generatedAt: CanonicalTimestamp(generatedAt),
            objects: sortedObjects,
            libraryObjects: sortedLibraryObjects,
            folders: sortedFolders,
            studyItems: sortedStudyItems,
            standaloneNotes: sortedStandaloneNotes,
            libraryTombstones: sortedTombstones,
            manifestCapabilities: Array(Set(manifestCapabilities)).sorted { $0.rawValue < $1.rawValue },
            manifestHash: CanonicalHash("")
        )
        manifest.manifestHash = manifest.computedManifestHash()
        return manifest
    }

    nonisolated init(
        schemaVersion: Int,
        node: CanonicalNode,
        generatedAt: CanonicalTimestamp,
        objects: [CanonicalRecordingObject],
        libraryObjects: [CanonicalLibraryObject] = [],
        folders: [CanonicalFolderObject] = [],
        studyItems: [CanonicalStudyItemObject] = [],
        standaloneNotes: [CanonicalStandaloneNoteObject] = [],
        libraryTombstones: [CanonicalLibraryTombstone] = [],
        manifestCapabilities: [CanonicalCapability] = [],
        manifestHash: CanonicalHash
    ) {
        self.schemaVersion = schemaVersion
        self.node = node
        self.generatedAt = generatedAt
        self.objects = objects.sorted { $0.objectID < $1.objectID }
        self.libraryObjects = libraryObjects.sorted { $0.objectID.rawValue < $1.objectID.rawValue }
        self.folders = folders.sorted { $0.folderID.rawValue < $1.folderID.rawValue }
        self.studyItems = studyItems.sorted { $0.itemID.rawValue < $1.itemID.rawValue }
        self.standaloneNotes = standaloneNotes.sorted { $0.noteID.rawValue < $1.noteID.rawValue }
        self.libraryTombstones = libraryTombstones.sorted { $0.tombstoneID < $1.tombstoneID }
        self.manifestCapabilities = Array(Set(manifestCapabilities)).sorted { $0.rawValue < $1.rawValue }
        self.manifestHash = manifestHash
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case node
        case generatedAt
        case objects
        case libraryObjects
        case objectsV2
        case folders
        case studyItems
        case standaloneNotes
        case tombstones
        case libraryTombstones
        case capabilities
        case manifestCapabilities
        case manifestHash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        node = try container.decode(CanonicalNode.self, forKey: .node)
        generatedAt = try container.decodeIfPresent(CanonicalTimestamp.self, forKey: .generatedAt) ?? CanonicalTimestamp(Date(timeIntervalSince1970: 0))
        objects = try container.decodeIfPresent([CanonicalRecordingObject].self, forKey: .objects) ?? []
        let decodedLibraryObjects = try container.decodeIfPresent([CanonicalLibraryObject].self, forKey: .libraryObjects)
            ?? container.decodeIfPresent([CanonicalLibraryObject].self, forKey: .objectsV2)
            ?? []
        libraryObjects = decodedLibraryObjects.sorted { $0.objectID.rawValue < $1.objectID.rawValue }
        folders = try container.decodeIfPresent([CanonicalFolderObject].self, forKey: .folders) ?? []
        studyItems = try container.decodeIfPresent([CanonicalStudyItemObject].self, forKey: .studyItems) ?? []
        standaloneNotes = try container.decodeIfPresent([CanonicalStandaloneNoteObject].self, forKey: .standaloneNotes) ?? []
        libraryTombstones = try container.decodeIfPresent([CanonicalLibraryTombstone].self, forKey: .libraryTombstones)
            ?? container.decodeIfPresent([CanonicalLibraryTombstone].self, forKey: .tombstones)
            ?? []
        manifestCapabilities = try container.decodeIfPresent([CanonicalCapability].self, forKey: .manifestCapabilities)
            ?? container.decodeIfPresent([CanonicalCapability].self, forKey: .capabilities)
            ?? []
        manifestCapabilities = Array(Set(manifestCapabilities)).sorted { $0.rawValue < $1.rawValue }
        manifestHash = try container.decodeIfPresent(CanonicalHash.self, forKey: .manifestHash) ?? CanonicalHash("")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(node, forKey: .node)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(objects, forKey: .objects)
        try container.encode(libraryObjects, forKey: .libraryObjects)
        try container.encode(folders, forKey: .folders)
        try container.encode(studyItems, forKey: .studyItems)
        try container.encode(standaloneNotes, forKey: .standaloneNotes)
        try container.encode(libraryTombstones, forKey: .libraryTombstones)
        try container.encode(manifestCapabilities, forKey: .manifestCapabilities)
        try container.encode(manifestHash, forKey: .manifestHash)
    }

    nonisolated func object(withID objectID: String) -> CanonicalRecordingObject? {
        objects.first { $0.objectID == objectID }
    }

    nonisolated func computedManifestHash() -> CanonicalHash {
        CanonicalHash.sha256(of: [
            "schemaVersion": String(schemaVersion),
            "nodeID": node.nodeID,
            "nodePlatform": node.platform,
            "nodeCapabilities": node.capabilities.map(\.rawValue).joined(separator: "\u{1F}"),
            "manifestCapabilities": manifestCapabilities.map(\.rawValue).joined(separator: "\u{1F}"),
            "generatedAt": Self.timestampString(generatedAt),
            "objects": objects.map(Self.objectHashSummary).joined(separator: "\u{1E}"),
            "libraryObjects": libraryObjects.map(Self.libraryObjectHashSummary).joined(separator: "\u{1E}"),
            "folders": folders.map { $0.metadataHash.value }.joined(separator: "\u{1E}"),
            "studyItems": studyItems.map { $0.metadataHash.value }.joined(separator: "\u{1E}"),
            "standaloneNotes": standaloneNotes.map { $0.metadataHash.value }.joined(separator: "\u{1E}"),
            "libraryTombstones": libraryTombstones.map(Self.libraryTombstoneHashSummary).joined(separator: "\u{1E}")
        ])
    }

    nonisolated var hasValidManifestHash: Bool {
        let computed = computedManifestHash()
        return manifestHash.algorithm == computed.algorithm && manifestHash.value == computed.value
    }

    nonisolated private static func objectHashSummary(_ object: CanonicalRecordingObject) -> String {
        let artifacts = object.artifacts.map { artifact in
            [
                artifact.artifactID,
                artifact.kind.rawValue,
                artifact.availability.rawValue,
                artifact.contentHash?.value ?? "",
                artifact.byteSize.map(String.init) ?? ""
            ].joined(separator: "\u{1F}")
        }.joined(separator: "\u{1D}")
        return [
            object.objectID,
            object.metadataHash.value,
            object.metadataHash.algorithm,
            object.syncState.rawValue,
            object.transferState.rawValue,
            object.metadata.isDeleted ? "deleted" : "active",
            artifacts
        ].joined(separator: "\u{1F}")
    }

    nonisolated private static func libraryObjectHashSummary(_ object: CanonicalLibraryObject) -> String {
        [
            object.objectID.rawValue,
            object.kind.rawValue,
            object.metadataHash.value,
            object.isDeleted ? "deleted" : "active",
            object.businessModifiedAt.map(timestampString) ?? ""
        ].joined(separator: "\u{1F}")
    }

    nonisolated private static func libraryTombstoneHashSummary(_ tombstone: CanonicalLibraryTombstone) -> String {
        [
            tombstone.tombstoneID,
            tombstone.objectID.rawValue,
            tombstone.objectKind.rawValue,
            tombstone.deletedAt.map(timestampString) ?? "",
            tombstone.reason.rawValue
        ].joined(separator: "\u{1F}")
    }

    nonisolated private static func timestampString(_ timestamp: CanonicalTimestamp) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), timestamp.date.timeIntervalSince1970)
    }
}

nonisolated enum ConflictReason: String, Codable, Equatable, Sendable {
    case objectIdentityCollision
    case metadataModifiedOnBothSides
    case artifactHashMismatch
    case artifactSizeMismatch
    case artifactUnavailableMismatch
}

nonisolated struct SyncDecision: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case noOp
        case uploadMetadata
        case downloadMetadata
        case deferUntilPeerKnown
        case conflict
    }

    var kind: Kind
    var objectID: String
    var reason: String
    var conflictReason: ConflictReason?

    nonisolated static func metadata(local: CanonicalRecordingObject, peer: CanonicalRecordingObject?) -> SyncDecision {
        guard let peer else {
            return SyncDecision(kind: .uploadMetadata, objectID: local.objectID, reason: "peer_missing_metadata")
        }

        if sameHash(local.metadataHash, peer.metadataHash) {
            return SyncDecision(kind: .noOp, objectID: local.objectID, reason: "metadata_hash_equal")
        }

        if local.metadata.modifiedAt.date > peer.metadata.modifiedAt.date {
            return SyncDecision(kind: .uploadMetadata, objectID: local.objectID, reason: "local_metadata_newer")
        }

        if peer.metadata.modifiedAt.date > local.metadata.modifiedAt.date {
            return SyncDecision(kind: .downloadMetadata, objectID: local.objectID, reason: "peer_metadata_newer")
        }

        return SyncDecision(
            kind: .conflict,
            objectID: local.objectID,
            reason: "metadata_hash_mismatch_same_modified_at",
            conflictReason: .metadataModifiedOnBothSides
        )
    }

    nonisolated private static func sameHash(_ left: CanonicalHash, _ right: CanonicalHash) -> Bool {
        left.algorithm == right.algorithm && left.value == right.value
    }
}

nonisolated struct TransferDecision: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case noOp
        case upload
        case download
        case deferUntilPeerKnown
        case conflict
        case localUnavailable
    }

    var kind: Kind
    var objectID: String
    var artifactID: String?
    var reason: String
    var conflictReason: ConflictReason?

    nonisolated static func audio(local: CanonicalRecordingObject, peer: CanonicalRecordingObject?) -> TransferDecision {
        let localAudio = local.audioArtifact
        let peerAudio = peer?.audioArtifact
        let artifactID = localAudio?.artifactID ?? peerAudio?.artifactID

        guard let localAudio, localAudio.provesCanonicalAudioAvailability else {
            return TransferDecision(
                kind: .localUnavailable,
                objectID: local.objectID,
                artifactID: artifactID,
                reason: "local_audio_unproven"
            )
        }

        guard peer != nil else {
            return TransferDecision(
                kind: .deferUntilPeerKnown,
                objectID: local.objectID,
                artifactID: artifactID,
                reason: "peer_unknown_is_not_missing"
            )
        }

        guard let peerAudio else {
            return TransferDecision(
                kind: .upload,
                objectID: local.objectID,
                artifactID: artifactID,
                reason: "peer_audio_missing"
            )
        }

        if peerAudio.availability == .missing {
            return TransferDecision(
                kind: .upload,
                objectID: local.objectID,
                artifactID: artifactID,
                reason: "peer_audio_missing"
            )
        }

        guard peerAudio.provesCanonicalAudioAvailability else {
            return TransferDecision(
                kind: .deferUntilPeerKnown,
                objectID: local.objectID,
                artifactID: artifactID,
                reason: "peer_audio_unproven"
            )
        }

        if !sameHash(localAudio.contentHash, peerAudio.contentHash) {
            return TransferDecision(
                kind: .conflict,
                objectID: local.objectID,
                artifactID: artifactID,
                reason: "audio_hash_mismatch",
                conflictReason: .artifactHashMismatch
            )
        }

        if localAudio.byteSize != peerAudio.byteSize {
            return TransferDecision(
                kind: .conflict,
                objectID: local.objectID,
                artifactID: artifactID,
                reason: "audio_size_mismatch",
                conflictReason: .artifactSizeMismatch
            )
        }

        return TransferDecision(
            kind: .noOp,
            objectID: local.objectID,
            artifactID: artifactID,
            reason: "peer_audio_same_hash_and_size"
        )
    }

    nonisolated private static func sameHash(_ left: CanonicalHash?, _ right: CanonicalHash?) -> Bool {
        left?.algorithm == right?.algorithm && left?.value == right?.value
    }
}

nonisolated struct ObjectProjection: Codable, Equatable, Identifiable, Sendable {
    var id: String { objectID }

    var objectID: String
    var displayTitle: String
    var metadataHash: CanonicalHash
    var audioAvailable: Bool
    var syncState: CanonicalSyncState
    var transferState: CanonicalTransferState
    var processingState: CanonicalProcessingState
    var conflictReasons: [ConflictReason]

    // UI display state is derived from core facts only. It must never drive sync or upload.
    nonisolated static func make(from object: CanonicalRecordingObject, conflictReasons: [ConflictReason] = []) -> ObjectProjection {
        ObjectProjection(
            objectID: object.objectID,
            displayTitle: object.metadata.title,
            metadataHash: object.metadataHash,
            audioAvailable: object.audioAvailable,
            syncState: object.syncState,
            transferState: object.transferState,
            processingState: object.processingState,
            conflictReasons: conflictReasons
        )
    }
}

nonisolated enum CanonicalRecordingExistenceState: String, Codable, Equatable, Sendable {
    case absent
    case metadataOnly
    case receiveRecordOnly
    case studyItemOnly
    case metadataAndStudyItem
    case audioAvailable
    case audioHashSizeMatched
    case audioConflict
    case peerUnknown
    case tombstoned
    case unsupported

    nonisolated var isAudioProof: Bool {
        self == .audioAvailable || self == .audioHashSizeMatched
    }
}

nonisolated enum CanonicalRecordingExistenceSource: String, Codable, Equatable, Hashable, Sendable {
    case canonicalManifest
    case studyLibraryManifest
    case localInventory
    case peerInventory
    case recordingMetadata
    case receiveRecord
    case studyItem
    case audioArtifact
    case completedUploadLedger
    case canonicalExistenceLedger
}

nonisolated enum CanonicalRecordingExistenceDecision: String, Codable, Equatable, Sendable {
    case noOp
    case applyMetadataOnlyBridge
    case uploadAudioCandidate
    case audioSameNoOp
    case conflict
    case deferred
    case blocked
    case unsupported
}

nonisolated enum CanonicalRecordingExistenceBlocker: String, Codable, Equatable, Hashable, Sendable {
    case tombstonedParent
    case peerUnknown
    case missingLocalAudio
    case localAudioUnproven
    case peerAudioUnproven
    case audioHashMismatch
    case audioSizeMismatch
    case completedLedgerNotAudioProof
    case metadataOnlyNotAudioProof
    case receiveRecordNotAudioProof
    case studyItemNotAudioProof
    case unsupportedObject
}

nonisolated struct CanonicalRecordingExistenceTruth: Codable, Equatable, Sendable {
    var objectID: String
    var localState: CanonicalRecordingExistenceState
    var peerState: CanonicalRecordingExistenceState
    var decision: CanonicalRecordingExistenceDecision
    var sources: [CanonicalRecordingExistenceSource]
    var blockers: [CanonicalRecordingExistenceBlocker]
    var localMetadataHashPrefix: String?
    var peerMetadataHashPrefix: String?
    var localAudioHashPrefix: String?
    var peerAudioHashPrefix: String?
    var localByteSize: Int64?
    var peerByteSize: Int64?

    nonisolated var peerAudioAvailable: Bool {
        peerState.isAudioProof
    }

    nonisolated var shouldCreateUploadCandidate: Bool {
        decision == .uploadAudioCandidate
    }

    nonisolated var requiresMetadataApplyBridge: Bool {
        decision == .applyMetadataOnlyBridge
    }

    nonisolated static func evaluate(
        objectID: String,
        local: CanonicalRecordingObject?,
        peer: CanonicalRecordingObject?,
        peerKnown: Bool = true,
        peerStudyItemExists: Bool = false,
        peerReceiveRecordExists: Bool = false,
        peerCompletedLedgerOnly: Bool = false,
        tombstonedParent: Bool = false
    ) -> CanonicalRecordingExistenceTruth {
        let normalizedObjectID = objectID.trimmingCharacters(in: .whitespacesAndNewlines)
        var sources: Set<CanonicalRecordingExistenceSource> = [.canonicalManifest]
        if local != nil {
            sources.insert(.localInventory)
            sources.insert(.recordingMetadata)
        }
        if peer != nil {
            sources.insert(.peerInventory)
            sources.insert(.recordingMetadata)
        }
        if peerStudyItemExists {
            sources.insert(.studyItem)
        }
        if peerReceiveRecordExists {
            sources.insert(.receiveRecord)
        }
        if peerCompletedLedgerOnly {
            sources.insert(.completedUploadLedger)
        }

        let localState = existenceState(
            object: local,
            known: true,
            studyItemExists: false,
            receiveRecordExists: false,
            completedLedgerOnly: false,
            tombstonedParent: tombstonedParent
        )
        var peerState = existenceState(
            object: peer,
            known: peerKnown,
            studyItemExists: peerStudyItemExists,
            receiveRecordExists: peerReceiveRecordExists,
            completedLedgerOnly: peerCompletedLedgerOnly,
            tombstonedParent: tombstonedParent
        )
        var blockers: Set<CanonicalRecordingExistenceBlocker> = []

        if tombstonedParent {
            blockers.insert(.tombstonedParent)
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: .tombstoned,
                decision: .blocked,
                sources: sources,
                blockers: blockers
            )
        }

        guard peerKnown else {
            blockers.insert(.peerUnknown)
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: .peerUnknown,
                decision: .deferred,
                sources: sources,
                blockers: blockers
            )
        }

        guard let localAudio = local?.audioArtifact else {
            blockers.insert(.missingLocalAudio)
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: peerState,
                decision: peerState == .absent ? .applyMetadataOnlyBridge : .noOp,
                sources: sources,
                blockers: blockers
            )
        }

        guard localAudio.provesCanonicalAudioAvailability else {
            blockers.insert(.localAudioUnproven)
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: peerState,
                decision: .blocked,
                sources: sources,
                blockers: blockers
            )
        }

        switch peerState {
        case .absent:
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: peerState,
                decision: .applyMetadataOnlyBridge,
                sources: sources,
                blockers: blockers
            )
        case .metadataOnly:
            blockers.insert(.metadataOnlyNotAudioProof)
            if peerCompletedLedgerOnly {
                blockers.insert(.completedLedgerNotAudioProof)
            }
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: peerState,
                decision: .uploadAudioCandidate,
                sources: sources,
                blockers: blockers
            )
        case .receiveRecordOnly:
            blockers.insert(.receiveRecordNotAudioProof)
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: peerState,
                decision: .uploadAudioCandidate,
                sources: sources,
                blockers: blockers
            )
        case .studyItemOnly:
            blockers.insert(.studyItemNotAudioProof)
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: peerState,
                decision: .uploadAudioCandidate,
                sources: sources,
                blockers: blockers
            )
        case .metadataAndStudyItem:
            blockers.insert(.metadataOnlyNotAudioProof)
            blockers.insert(.studyItemNotAudioProof)
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: peerState,
                decision: .uploadAudioCandidate,
                sources: sources,
                blockers: blockers
            )
        case .audioAvailable:
            guard let peerAudio = peer?.audioArtifact,
                  peerAudio.provesCanonicalAudioAvailability else {
                blockers.insert(.peerAudioUnproven)
                return truth(
                    objectID: normalizedObjectID,
                    local: local,
                    peer: peer,
                    localState: localState,
                    peerState: .unsupported,
                    decision: .deferred,
                    sources: sources,
                    blockers: blockers
                )
            }
            if localAudio.contentHash != peerAudio.contentHash {
                blockers.insert(.audioHashMismatch)
                peerState = .audioConflict
                return truth(
                    objectID: normalizedObjectID,
                    local: local,
                    peer: peer,
                    localState: localState,
                    peerState: peerState,
                    decision: .conflict,
                    sources: sources,
                    blockers: blockers
                )
            }
            if localAudio.byteSize != peerAudio.byteSize {
                blockers.insert(.audioSizeMismatch)
                peerState = .audioConflict
                return truth(
                    objectID: normalizedObjectID,
                    local: local,
                    peer: peer,
                    localState: localState,
                    peerState: peerState,
                    decision: .conflict,
                    sources: sources,
                    blockers: blockers
                )
            }
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: .audioHashSizeMatched,
                decision: .audioSameNoOp,
                sources: sources,
                blockers: blockers
            )
        case .audioHashSizeMatched:
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: .audioHashSizeMatched,
                decision: .audioSameNoOp,
                sources: sources,
                blockers: blockers
            )
        case .audioConflict:
            blockers.insert(.audioHashMismatch)
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: peerState,
                decision: .conflict,
                sources: sources,
                blockers: blockers
            )
        case .peerUnknown:
            blockers.insert(.peerUnknown)
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: peerState,
                decision: .deferred,
                sources: sources,
                blockers: blockers
            )
        case .tombstoned:
            blockers.insert(.tombstonedParent)
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: peerState,
                decision: .blocked,
                sources: sources,
                blockers: blockers
            )
        case .unsupported:
            blockers.insert(.unsupportedObject)
            return truth(
                objectID: normalizedObjectID,
                local: local,
                peer: peer,
                localState: localState,
                peerState: peerState,
                decision: .unsupported,
                sources: sources,
                blockers: blockers
            )
        }
    }

    nonisolated func diagnostics(
        syncRunID: String?,
        mode: CanonicalSyncRuntimeMode
    ) -> [CanonicalSyncRuntimeDiagnostic] {
        var output = [
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalExistenceTruthEvaluated,
                syncRunID: syncRunID,
                mode: mode,
                objectID: objectID,
                hashPrefix: localAudioHashPrefix ?? peerAudioHashPrefix ?? localMetadataHashPrefix ?? peerMetadataHashPrefix,
                count: localByteSize.map(Int.init),
                detail: "\(localState.rawValue)->\(peerState.rawValue):\(decision.rawValue)"
            )
        ]
        switch decision {
        case .applyMetadataOnlyBridge:
            output.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistencePeerAbsentMetadataBridgeRequired, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: localMetadataHashPrefix, detail: peerState.rawValue))
        case .uploadAudioCandidate:
            output.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistencePeerMetadataOnlyUploadCandidate, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: localAudioHashPrefix, count: localByteSize.map(Int.init), detail: peerState.rawValue))
        case .audioSameNoOp:
            output.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistenceAudioSameNoOp, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: localAudioHashPrefix, count: localByteSize.map(Int.init), detail: "sameHashAndSize"))
        case .conflict:
            output.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistenceAudioConflict, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: localAudioHashPrefix, count: localByteSize.map(Int.init), detail: blockers.map(\.rawValue).joined(separator: "+")))
        case .deferred where peerState == .peerUnknown:
            output.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistencePeerUnknownDeferred, syncRunID: syncRunID, mode: mode, objectID: objectID, detail: "peerUnknown"))
        default:
            break
        }
        return output
    }

    nonisolated private static func existenceState(
        object: CanonicalRecordingObject?,
        known: Bool,
        studyItemExists: Bool,
        receiveRecordExists: Bool,
        completedLedgerOnly: Bool,
        tombstonedParent: Bool
    ) -> CanonicalRecordingExistenceState {
        guard known else {
            return .peerUnknown
        }
        if tombstonedParent || object?.syncState == .deleted {
            return .tombstoned
        }
        guard let object else {
            if receiveRecordExists {
                return .receiveRecordOnly
            }
            if studyItemExists {
                return .studyItemOnly
            }
            return completedLedgerOnly ? .metadataOnly : .absent
        }
        if object.audioAvailable {
            return .audioAvailable
        }
        if receiveRecordExists, studyItemExists {
            return .metadataAndStudyItem
        }
        if receiveRecordExists {
            return .receiveRecordOnly
        }
        if studyItemExists {
            return .metadataAndStudyItem
        }
        return .metadataOnly
    }

    nonisolated private static func truth(
        objectID: String,
        local: CanonicalRecordingObject?,
        peer: CanonicalRecordingObject?,
        localState: CanonicalRecordingExistenceState,
        peerState: CanonicalRecordingExistenceState,
        decision: CanonicalRecordingExistenceDecision,
        sources: Set<CanonicalRecordingExistenceSource>,
        blockers: Set<CanonicalRecordingExistenceBlocker>
    ) -> CanonicalRecordingExistenceTruth {
        CanonicalRecordingExistenceTruth(
            objectID: objectID,
            localState: localState,
            peerState: peerState,
            decision: decision,
            sources: sources.sorted { $0.rawValue < $1.rawValue },
            blockers: blockers.sorted { $0.rawValue < $1.rawValue },
            localMetadataHashPrefix: local?.metadataHash.value.shortCanonicalPrefix,
            peerMetadataHashPrefix: peer?.metadataHash.value.shortCanonicalPrefix,
            localAudioHashPrefix: local?.audioArtifact?.contentHash?.value.shortCanonicalPrefix,
            peerAudioHashPrefix: peer?.audioArtifact?.contentHash?.value.shortCanonicalPrefix,
            localByteSize: local?.audioArtifact?.byteSize,
            peerByteSize: peer?.audioArtifact?.byteSize
        )
    }
}

nonisolated enum CanonicalExistenceApplyRuntimeMode: String, Codable, Equatable, Sendable {
    case disabled
    case diagnosticsOnly
    case noCommit
    case metadataOnlyBridge
    case testRootApply
    case productionRootApply
    case blocked

    nonisolated var evaluatesCandidates: Bool {
        self != .blocked
    }

    nonisolated var canCommitMetadataOnlyRecord: Bool {
        self == .metadataOnlyBridge || self == .testRootApply || self == .productionRootApply
    }
}

nonisolated struct CanonicalExistenceApplyRuntimePolicy: Codable, Equatable, Sendable {
    var debugInternalBuild: Bool
    var ownerApproved: Bool
    var releaseDefaultBuild: Bool
    var diagnosticsRedacted: Bool
    var legacyFallbackAvailable: Bool
    var rootBoundRequired: Bool
    var rollbackRequired: Bool
    var atomicWriteRequired: Bool
    var postconditionRequired: Bool
    var writeAudioAllowed: Bool
    var markAudioAvailableAllowed: Bool

    nonisolated init(
        debugInternalBuild: Bool = false,
        ownerApproved: Bool = false,
        releaseDefaultBuild: Bool = true,
        diagnosticsRedacted: Bool = true,
        legacyFallbackAvailable: Bool = true,
        rootBoundRequired: Bool = true,
        rollbackRequired: Bool = true,
        atomicWriteRequired: Bool = true,
        postconditionRequired: Bool = true,
        writeAudioAllowed: Bool = false,
        markAudioAvailableAllowed: Bool = false
    ) {
        self.debugInternalBuild = debugInternalBuild
        self.ownerApproved = ownerApproved
        self.releaseDefaultBuild = releaseDefaultBuild
        self.diagnosticsRedacted = diagnosticsRedacted
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.rootBoundRequired = rootBoundRequired
        self.rollbackRequired = rollbackRequired
        self.atomicWriteRequired = atomicWriteRequired
        self.postconditionRequired = postconditionRequired
        self.writeAudioAllowed = writeAudioAllowed
        self.markAudioAvailableAllowed = markAudioAvailableAllowed
    }
}

nonisolated struct CanonicalExistenceApplyRuntimeConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalExistenceApplyRuntimeMode
    var policy: CanonicalExistenceApplyRuntimePolicy

    nonisolated init(
        mode: CanonicalExistenceApplyRuntimeMode = .disabled,
        policy: CanonicalExistenceApplyRuntimePolicy = CanonicalExistenceApplyRuntimePolicy()
    ) {
        self.mode = mode
        self.policy = policy
    }

    nonisolated static let disabled = CanonicalExistenceApplyRuntimeConfiguration()

    nonisolated var canWriteMetadataOnlyRecord: Bool {
        guard mode.canCommitMetadataOnlyRecord,
              policy.diagnosticsRedacted,
              policy.legacyFallbackAvailable,
              policy.rootBoundRequired,
              policy.rollbackRequired,
              policy.atomicWriteRequired,
              policy.postconditionRequired,
              !policy.writeAudioAllowed,
              !policy.markAudioAvailableAllowed else {
            return false
        }
        if mode == .productionRootApply {
            return policy.debugInternalBuild && policy.ownerApproved && !policy.releaseDefaultBuild
        }
        return mode == .metadataOnlyBridge || mode == .testRootApply
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    nonisolated var shortCanonicalPrefix: String {
        String(trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
    }
}
