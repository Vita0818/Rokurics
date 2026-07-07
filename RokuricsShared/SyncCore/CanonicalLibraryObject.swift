//
//  CanonicalLibraryObject.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated struct CanonicalLibraryObjectID: Codable, Equatable, Hashable, Sendable {
    var rawValue: String

    nonisolated init(_ rawValue: String, fallback: String = "unknownUnsupported:unknown") {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallback
    }
}

nonisolated enum CanonicalObjectKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recording
    case folder
    case standaloneStudyItem
    case standaloneNote
    case recordingAssociatedStudyItem
    case generatedArtifactEnvelope
    case unknownUnsupported
}

nonisolated enum CanonicalStudyItemKind: String, Codable, Equatable, Hashable, Sendable {
    case recordingBundle
    case standaloneNote
    case externalResource
    case unknown
}

nonisolated struct CanonicalParentReference: Codable, Equatable, Hashable, Sendable {
    var parentID: CanonicalLibraryObjectID
    var relation: String

    nonisolated init(parentID: CanonicalLibraryObjectID, relation: String = "parent") {
        self.parentID = parentID
        self.relation = relation.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "parent"
    }
}

nonisolated struct CanonicalHierarchyPath: Codable, Equatable, Hashable, Sendable {
    var components: [String]

    nonisolated init(_ components: [String] = []) {
        self.components = components.compactMap(Self.normalized)
    }

    nonisolated var stableKey: String {
        components.joined(separator: "\u{1F}")
    }

    nonisolated private static func normalized(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

nonisolated struct CanonicalFolderMetadata: Codable, Equatable, Sendable {
    var folderID: CanonicalLibraryObjectID
    var name: String
    var parentID: CanonicalLibraryObjectID?
    var hierarchyPath: CanonicalHierarchyPath
    var hierarchyLevel: String?
    var colorToken: String?
    var orderingKey: String?
    var isDeleted: Bool
    var deletedAt: CanonicalTimestamp?
    var businessModifiedAt: CanonicalTimestamp

    nonisolated init(
        folderID: CanonicalLibraryObjectID,
        name: String,
        parentID: CanonicalLibraryObjectID? = nil,
        hierarchyPath: CanonicalHierarchyPath = CanonicalHierarchyPath(),
        hierarchyLevel: String? = nil,
        colorToken: String? = nil,
        orderingKey: String? = nil,
        isDeleted: Bool = false,
        deletedAt: CanonicalTimestamp? = nil,
        businessModifiedAt: CanonicalTimestamp
    ) {
        self.folderID = folderID
        self.name = CanonicalProjectionContract.normalizeFolderName(name)
        self.parentID = parentID
        self.hierarchyPath = hierarchyPath
        self.hierarchyLevel = hierarchyLevel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.colorToken = colorToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.orderingKey = orderingKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.isDeleted = isDeleted
        self.deletedAt = isDeleted ? deletedAt : nil
        self.businessModifiedAt = businessModifiedAt
    }

    nonisolated var metadataHash: CanonicalHash {
        CanonicalLibraryMetadataHashSchema.v1.hash(CanonicalLibraryMetadataBusinessFields(folder: self))
    }
}

nonisolated struct CanonicalStudyItemMetadata: Codable, Equatable, Sendable {
    var itemID: CanonicalLibraryObjectID
    var itemKind: CanonicalStudyItemKind
    var title: String
    var filingPath: CanonicalHierarchyPath
    var folderIDs: [CanonicalLibraryObjectID]
    var parentReferences: [CanonicalParentReference]
    var tags: [String]
    var logicalResourceTokens: [String]
    var associatedRecordingID: String?
    var isDeleted: Bool
    var deletedAt: CanonicalTimestamp?
    var businessModifiedAt: CanonicalTimestamp

    nonisolated init(
        itemID: CanonicalLibraryObjectID,
        itemKind: CanonicalStudyItemKind,
        title: String,
        filingPath: CanonicalHierarchyPath = CanonicalHierarchyPath(),
        folderIDs: [CanonicalLibraryObjectID] = [],
        parentReferences: [CanonicalParentReference] = [],
        tags: [String] = [],
        logicalResourceTokens: [String] = [],
        associatedRecordingID: String? = nil,
        isDeleted: Bool = false,
        deletedAt: CanonicalTimestamp? = nil,
        businessModifiedAt: CanonicalTimestamp
    ) {
        self.itemID = itemID
        self.itemKind = itemKind
        self.title = CanonicalProjectionContract.normalizeStudyItemTitle(title, itemKind: itemKind)
        self.filingPath = CanonicalProjectionContract.normalizeFilingPath(filingPath)
        self.folderIDs = Array(Set(folderIDs)).sorted { $0.rawValue < $1.rawValue }
        self.parentReferences = CanonicalProjectionContract.normalizeParentReferences(parentReferences)
        self.tags = CanonicalProjectionContract.normalizeTags(tags)
        self.logicalResourceTokens = Array(Set(logicalResourceTokens.compactMap {
            CanonicalProjectionContract.safeLogicalResourceToken($0)
        })).sorted()
        self.associatedRecordingID = associatedRecordingID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.isDeleted = isDeleted
        self.deletedAt = isDeleted ? deletedAt : nil
        self.businessModifiedAt = businessModifiedAt
    }

    nonisolated var metadataHash: CanonicalHash {
        CanonicalLibraryMetadataHashSchema.v1.hash(CanonicalLibraryMetadataBusinessFields(item: self))
    }
}

nonisolated struct CanonicalLibraryMetadataBusinessFields: Codable, Equatable, Sendable {
    var objectID: CanonicalLibraryObjectID
    var objectKind: CanonicalObjectKind
    var title: String
    var itemKind: CanonicalStudyItemKind?
    var parentID: CanonicalLibraryObjectID?
    var hierarchyPath: CanonicalHierarchyPath
    var hierarchyLevel: String?
    var filingPath: CanonicalHierarchyPath
    var folderIDs: [CanonicalLibraryObjectID]
    var parentReferences: [CanonicalParentReference]
    var tags: [String]
    var colorToken: String?
    var orderingKey: String?
    var associatedRecordingID: String?
    var isDeleted: Bool
    var deletedAt: CanonicalTimestamp?
    var businessModifiedAt: CanonicalTimestamp

    nonisolated init(folder: CanonicalFolderMetadata) {
        self.objectID = folder.folderID
        self.objectKind = .folder
        self.title = folder.name
        self.itemKind = nil
        self.parentID = folder.parentID
        self.hierarchyPath = folder.hierarchyPath
        self.hierarchyLevel = folder.hierarchyLevel
        self.filingPath = CanonicalHierarchyPath()
        self.folderIDs = []
        self.parentReferences = []
        self.tags = []
        self.colorToken = folder.colorToken
        self.orderingKey = folder.orderingKey
        self.associatedRecordingID = nil
        self.isDeleted = folder.isDeleted
        self.deletedAt = folder.deletedAt
        self.businessModifiedAt = folder.businessModifiedAt
    }

    nonisolated init(item: CanonicalStudyItemMetadata, objectKind: CanonicalObjectKind? = nil) {
        self.objectID = item.itemID
        self.objectKind = objectKind ?? Self.derivedObjectKind(for: item)
        self.title = item.title
        self.itemKind = item.itemKind
        self.parentID = nil
        self.hierarchyPath = CanonicalHierarchyPath()
        self.hierarchyLevel = nil
        self.filingPath = item.filingPath
        self.folderIDs = item.folderIDs
        self.parentReferences = item.parentReferences
        self.tags = item.tags
        self.colorToken = nil
        self.orderingKey = nil
        self.associatedRecordingID = item.associatedRecordingID
        self.isDeleted = item.isDeleted
        self.deletedAt = item.deletedAt
        self.businessModifiedAt = item.businessModifiedAt
    }

    nonisolated init?(object: CanonicalLibraryObject) {
        switch object.kind {
        case .folder:
            guard let folder = object.folder?.metadata else { return nil }
            self.init(folder: folder)
        case .standaloneStudyItem, .recordingAssociatedStudyItem:
            guard let item = object.studyItem?.metadata else { return nil }
            self.init(item: item, objectKind: object.kind)
        case .standaloneNote:
            guard let item = object.standaloneNote?.studyItem.metadata ?? object.studyItem?.metadata else { return nil }
            self.init(item: item, objectKind: .standaloneNote)
        case .recording, .generatedArtifactEnvelope, .unknownUnsupported:
            return nil
        }
    }

    nonisolated var stableBusinessHashInput: [String: String] {
        [
            "schema": CanonicalLibraryMetadataHashSchema.version,
            "objectID": objectID.rawValue,
            "objectKind": objectKind.rawValue,
            "title": title,
            "itemKind": itemKind?.rawValue ?? "",
            "parentID": parentID?.rawValue ?? "",
            "hierarchyPath": hierarchyPath.stableKey,
            "hierarchyLevel": hierarchyLevel ?? "",
            "filingPath": filingPath.stableKey,
            "folderIDs": folderIDs.map(\.rawValue).joined(separator: "\u{1F}"),
            "parentReferences": parentReferences.map { "\($0.relation):\($0.parentID.rawValue)" }.joined(separator: "\u{1F}"),
            "tags": tags.joined(separator: "\u{1F}"),
            "colorToken": colorToken ?? "",
            "orderingKey": orderingKey ?? "",
            "associatedRecordingID": associatedRecordingID ?? "",
            "isDeleted": isDeleted ? "true" : "false",
            "deletedAt": deletedAt.map(Self.timestampString) ?? "",
            "businessModifiedAt": Self.timestampString(businessModifiedAt)
        ]
    }

    private nonisolated static func derivedObjectKind(for item: CanonicalStudyItemMetadata) -> CanonicalObjectKind {
        if item.itemKind == .standaloneNote {
            return .standaloneNote
        }
        if item.associatedRecordingID != nil || item.itemKind == .recordingBundle {
            return .recordingAssociatedStudyItem
        }
        return .standaloneStudyItem
    }

    private nonisolated static func timestampString(_ timestamp: CanonicalTimestamp) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), timestamp.date.timeIntervalSince1970)
    }
}

nonisolated struct CanonicalLibraryMetadataHashSchema: Codable, Equatable, Sendable {
    static let version = "canonical-library-metadata-v1"
    static let v1 = CanonicalLibraryMetadataHashSchema()

    var schemaVersion: String
    var includedStableBusinessFields: [String]
    var excludedFields: [String]

    nonisolated init(
        schemaVersion: String = CanonicalLibraryMetadataHashSchema.version,
        includedStableBusinessFields: [String] = [
            "schema",
            "objectID",
            "objectKind",
            "title",
            "itemKind",
            "parentID",
            "hierarchyPath",
            "hierarchyLevel",
            "filingPath",
            "folderIDs",
            "parentReferences",
            "tags",
            "colorToken",
            "orderingKey",
            "associatedRecordingID",
            "isDeleted",
            "deletedAt",
            "businessModifiedAt"
        ],
        excludedFields: [String] = [
            "noteFullContent",
            "generatedArtifactContent",
            "audioAvailability",
            "audioHash",
            "audioByteSize",
            "localPath",
            "resourcePath",
            "logicalResourceTokens",
            "uploadStatus",
            "receiveStatus",
            "syncEngineStatus",
            "diagnostics",
            "providerRequest",
            "providerResponse",
            "securitySecret"
        ]
    ) {
        self.schemaVersion = schemaVersion
        self.includedStableBusinessFields = includedStableBusinessFields
        self.excludedFields = excludedFields
    }

    nonisolated func hash(_ fields: CanonicalLibraryMetadataBusinessFields) -> CanonicalHash {
        CanonicalHash.sha256(of: fields.stableBusinessHashInput)
    }
}

nonisolated enum CanonicalLibraryMetadataDecisionAction: String, Codable, Equatable, Sendable {
    case legacyFallback
    case noOp
    case sendLocal
    case applyPeer
    case deferTie
    case conflictBlocked
}

nonisolated struct CanonicalLibraryMetadataDecisionInput: Codable, Equatable, Sendable {
    var objectID: CanonicalLibraryObjectID
    var objectKind: CanonicalObjectKind
    var local: CanonicalLibraryObject?
    var peer: CanonicalLibraryObject?
    var localSchemaVersion: String
    var peerSchemaVersion: String?
    var businessModifiedAtAvailable: Bool

    nonisolated init(
        objectID: CanonicalLibraryObjectID,
        objectKind: CanonicalObjectKind,
        local: CanonicalLibraryObject?,
        peer: CanonicalLibraryObject?,
        localSchemaVersion: String = CanonicalLibraryMetadataHashSchema.version,
        peerSchemaVersion: String? = CanonicalLibraryMetadataHashSchema.version,
        businessModifiedAtAvailable: Bool = true
    ) {
        self.objectID = objectID
        self.objectKind = objectKind
        self.local = local
        self.peer = peer
        self.localSchemaVersion = localSchemaVersion
        self.peerSchemaVersion = peerSchemaVersion
        self.businessModifiedAtAvailable = businessModifiedAtAvailable
    }
}

nonisolated struct CanonicalLibraryMetadataDecisionResult: Codable, Equatable, Sendable {
    var action: CanonicalLibraryMetadataDecisionAction
    var reason: String
    var localHashPrefix: String?
    var peerHashPrefix: String?
    var hashEqual: Bool
    var hashChanged: Bool
    var lwwApplied: Bool

    nonisolated init(
        action: CanonicalLibraryMetadataDecisionAction,
        reason: String,
        localHash: CanonicalHash? = nil,
        peerHash: CanonicalHash? = nil,
        hashEqual: Bool = false,
        hashChanged: Bool = false,
        lwwApplied: Bool = false
    ) {
        self.action = action
        self.reason = reason
        self.localHashPrefix = localHash.map(Self.hashPrefix)
        self.peerHashPrefix = peerHash.map(Self.hashPrefix)
        self.hashEqual = hashEqual
        self.hashChanged = hashChanged
        self.lwwApplied = lwwApplied
    }

    private nonisolated static func hashPrefix(_ hash: CanonicalHash) -> String {
        String(hash.value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
    }
}

nonisolated struct CanonicalLibraryMetadataModifiedAtPolicy: Codable, Equatable, Sendable {
    enum MissingBusinessModifiedAtPolicy: String, Codable, Equatable, Sendable {
        case blockPrimaryUnlessDocumentedFallback
        case allowDocumentedFallback
    }

    enum EqualModifiedAtTiePolicy: String, Codable, Equatable, Sendable {
        case deferAsConflict
    }

    static let current = CanonicalLibraryMetadataModifiedAtPolicy()

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

    nonisolated func decide(_ input: CanonicalLibraryMetadataDecisionInput) -> CanonicalLibraryMetadataDecisionResult {
        guard input.localSchemaVersion == CanonicalLibraryMetadataHashSchema.version,
              input.peerSchemaVersion == nil || input.peerSchemaVersion == CanonicalLibraryMetadataHashSchema.version else {
            return CanonicalLibraryMetadataDecisionResult(action: .legacyFallback, reason: "schemaMismatch")
        }
        guard input.businessModifiedAtAvailable || missingBusinessModifiedAtPolicy == .allowDocumentedFallback else {
            return CanonicalLibraryMetadataDecisionResult(action: .legacyFallback, reason: "businessModifiedAtUnavailable")
        }

        switch (input.local, input.peer) {
        case let (.some(local), .some(peer)):
            let localHash = local.metadataHash
            let peerHash = peer.metadataHash
            if localHash == peerHash {
                return CanonicalLibraryMetadataDecisionResult(
                    action: .noOp,
                    reason: "metadataHashEqual",
                    localHash: localHash,
                    peerHash: peerHash,
                    hashEqual: true
                )
            }
            guard let localModifiedAt = local.businessModifiedAt,
                  let peerModifiedAt = peer.businessModifiedAt else {
                return CanonicalLibraryMetadataDecisionResult(
                    action: .conflictBlocked,
                    reason: "metadataModifiedAtUnavailable",
                    localHash: localHash,
                    peerHash: peerHash,
                    hashChanged: true
                )
            }
            if localModifiedAt > peerModifiedAt {
                return CanonicalLibraryMetadataDecisionResult(
                    action: .sendLocal,
                    reason: "localMetadataNewer",
                    localHash: localHash,
                    peerHash: peerHash,
                    hashChanged: true,
                    lwwApplied: true
                )
            }
            if peerModifiedAt > localModifiedAt {
                return CanonicalLibraryMetadataDecisionResult(
                    action: .applyPeer,
                    reason: "peerMetadataNewer",
                    localHash: localHash,
                    peerHash: peerHash,
                    hashChanged: true,
                    lwwApplied: true
                )
            }
            return CanonicalLibraryMetadataDecisionResult(
                action: .deferTie,
                reason: "metadataTieConflict",
                localHash: localHash,
                peerHash: peerHash,
                hashChanged: true
            )
        case let (.some(local), .none):
            return CanonicalLibraryMetadataDecisionResult(
                action: .sendLocal,
                reason: "peerMissingMetadata",
                localHash: local.metadataHash,
                hashChanged: true,
                lwwApplied: true
            )
        case let (.none, .some(peer)):
            return CanonicalLibraryMetadataDecisionResult(
                action: .applyPeer,
                reason: "localMissingMetadata",
                peerHash: peer.metadataHash,
                hashChanged: true,
                lwwApplied: true
            )
        case (.none, .none):
            return CanonicalLibraryMetadataDecisionResult(action: .legacyFallback, reason: "metadataMissing")
        }
    }
}

nonisolated struct CanonicalLibraryMetadata: Codable, Equatable, Sendable {
    var objectID: CanonicalLibraryObjectID
    var objectKind: CanonicalObjectKind
    var title: String
    var metadataHash: CanonicalHash
    var businessModifiedAt: CanonicalTimestamp?
    var isDeleted: Bool
    var deletedAt: CanonicalTimestamp?
}

nonisolated struct CanonicalFolderObject: Codable, Equatable, Identifiable, Sendable {
    var id: String { folderID.rawValue }
    var folderID: CanonicalLibraryObjectID
    var metadata: CanonicalFolderMetadata
    var metadataHash: CanonicalHash

    nonisolated init(metadata: CanonicalFolderMetadata) {
        self.folderID = metadata.folderID
        self.metadata = metadata
        self.metadataHash = metadata.metadataHash
    }
}

nonisolated struct CanonicalStudyItemObject: Codable, Equatable, Identifiable, Sendable {
    var id: String { itemID.rawValue }
    var itemID: CanonicalLibraryObjectID
    var metadata: CanonicalStudyItemMetadata
    var metadataHash: CanonicalHash

    nonisolated init(metadata: CanonicalStudyItemMetadata) {
        self.itemID = metadata.itemID
        self.metadata = metadata
        self.metadataHash = metadata.metadataHash
    }
}

nonisolated struct CanonicalStandaloneNoteObject: Codable, Equatable, Identifiable, Sendable {
    var id: String { noteID.rawValue }
    var noteID: CanonicalLibraryObjectID
    var studyItem: CanonicalStudyItemObject
    var metadataHash: CanonicalHash

    nonisolated init(studyItem: CanonicalStudyItemObject) {
        self.noteID = studyItem.itemID
        self.studyItem = studyItem
        self.metadataHash = studyItem.metadataHash
    }
}

nonisolated struct CanonicalRecordingEnvelopeObject: Codable, Equatable, Identifiable, Sendable {
    var id: String { recordingID }
    var recordingID: String
    var studyItemID: CanonicalLibraryObjectID?
    var folderIDs: [CanonicalLibraryObjectID]
    var filingPath: CanonicalHierarchyPath
    var tags: [String]

    nonisolated init(
        recordingID: String,
        studyItemID: CanonicalLibraryObjectID? = nil,
        folderIDs: [CanonicalLibraryObjectID] = [],
        filingPath: CanonicalHierarchyPath = CanonicalHierarchyPath(),
        tags: [String] = []
    ) {
        self.recordingID = recordingID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "unknown-recording"
        self.studyItemID = studyItemID
        self.folderIDs = Array(Set(folderIDs)).sorted { $0.rawValue < $1.rawValue }
        self.filingPath = filingPath
        self.tags = CanonicalProjectionContract.normalizeTags(tags)
    }
}

nonisolated struct CanonicalLibraryObject: Codable, Equatable, Identifiable, Sendable {
    var id: String { objectID.rawValue }
    var objectID: CanonicalLibraryObjectID
    var kind: CanonicalObjectKind
    var folder: CanonicalFolderObject?
    var studyItem: CanonicalStudyItemObject?
    var standaloneNote: CanonicalStandaloneNoteObject?
    var recordingEnvelope: CanonicalRecordingEnvelopeObject?
    var unsupportedReason: String?

    nonisolated init(
        objectID: CanonicalLibraryObjectID,
        kind: CanonicalObjectKind,
        folder: CanonicalFolderObject? = nil,
        studyItem: CanonicalStudyItemObject? = nil,
        standaloneNote: CanonicalStandaloneNoteObject? = nil,
        recordingEnvelope: CanonicalRecordingEnvelopeObject? = nil,
        unsupportedReason: String? = nil
    ) {
        self.objectID = objectID
        self.kind = kind
        self.folder = folder
        self.studyItem = studyItem
        self.standaloneNote = standaloneNote
        self.recordingEnvelope = recordingEnvelope
        self.unsupportedReason = unsupportedReason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    nonisolated var metadataHash: CanonicalHash {
        switch kind {
        case .folder:
            return folder?.metadataHash ?? CanonicalHash.sha256String(objectID.rawValue)
        case .standaloneStudyItem, .recordingAssociatedStudyItem:
            return studyItem?.metadataHash ?? CanonicalHash.sha256String(objectID.rawValue)
        case .standaloneNote:
            return standaloneNote?.metadataHash ?? studyItem?.metadataHash ?? CanonicalHash.sha256String(objectID.rawValue)
        case .recording:
            return CanonicalHash.sha256String(recordingEnvelope?.recordingID ?? objectID.rawValue)
        case .generatedArtifactEnvelope, .unknownUnsupported:
            return CanonicalHash.sha256(of: [
                "schema": "canonical-library-object-unsupported-v1",
                "objectID": objectID.rawValue,
                "kind": kind.rawValue,
                "reason": unsupportedReason ?? ""
            ])
        }
    }

    nonisolated var businessModifiedAt: CanonicalTimestamp? {
        folder?.metadata.businessModifiedAt ?? studyItem?.metadata.businessModifiedAt
    }

    nonisolated var isDeleted: Bool {
        folder?.metadata.isDeleted ?? studyItem?.metadata.isDeleted ?? false
    }

    nonisolated var deletedAt: CanonicalTimestamp? {
        folder?.metadata.deletedAt ?? studyItem?.metadata.deletedAt
    }
}

nonisolated enum CanonicalLibraryTombstoneReason: String, Codable, Equatable, Sendable {
    case softDelete
    case peerTombstoneNewer
    case localTombstoneNewer
    case antiResurrection
}

nonisolated struct CanonicalLibraryTombstone: Codable, Equatable, Identifiable, Sendable {
    var id: String { tombstoneID }
    var tombstoneID: String
    var objectID: CanonicalLibraryObjectID
    var objectKind: CanonicalObjectKind
    var deletedAt: CanonicalTimestamp?
    var sourceNodeID: String?
    var reason: CanonicalLibraryTombstoneReason
    var policies: [CanonicalTombstonePolicy]

    nonisolated init(
        objectID: CanonicalLibraryObjectID,
        objectKind: CanonicalObjectKind,
        deletedAt: CanonicalTimestamp?,
        sourceNodeID: String? = nil,
        reason: CanonicalLibraryTombstoneReason,
        policies: [CanonicalTombstonePolicy] = [.softDeleteOnly, .antiResurrection, .noPhysicalDelete, .noPermanentDelete, .noGarbageCollection]
    ) {
        self.objectID = objectID
        self.objectKind = objectKind
        self.deletedAt = deletedAt
        self.sourceNodeID = sourceNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.reason = reason
        self.policies = Array(Set(policies)).sorted { $0.rawValue < $1.rawValue }
        self.tombstoneID = ["libraryTombstone", objectKind.rawValue, objectID.rawValue].joined(separator: "|")
    }
}

nonisolated enum CanonicalLibraryConflictKind: String, Codable, Equatable, Sendable {
    case folderMetadataConcurrentEdit
    case studyItemMetadataConcurrentEdit
    case activeVsTombstone
    case recordingEnvelopeMetadataDisagreement
    case unsupportedLibraryObject
}

nonisolated struct CanonicalLibraryConflict: Codable, Equatable, Identifiable, Sendable {
    var id: String { conflictID }
    var conflictID: String
    var kind: CanonicalLibraryConflictKind
    var objectID: CanonicalLibraryObjectID
    var objectKind: CanonicalObjectKind
    var localHashPrefix: String?
    var peerHashPrefix: String?
    var localModifiedAt: CanonicalTimestamp?
    var peerModifiedAt: CanonicalTimestamp?
    var detail: String?

    nonisolated init(
        kind: CanonicalLibraryConflictKind,
        objectID: CanonicalLibraryObjectID,
        objectKind: CanonicalObjectKind,
        localHash: CanonicalHash? = nil,
        peerHash: CanonicalHash? = nil,
        localModifiedAt: CanonicalTimestamp? = nil,
        peerModifiedAt: CanonicalTimestamp? = nil,
        detail: String? = nil
    ) {
        self.kind = kind
        self.objectID = objectID
        self.objectKind = objectKind
        self.localHashPrefix = localHash.map { String($0.value.prefix(12)) }
        self.peerHashPrefix = peerHash.map { String($0.value.prefix(12)) }
        self.localModifiedAt = localModifiedAt
        self.peerModifiedAt = peerModifiedAt
        self.detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.conflictID = ["libraryConflict", kind.rawValue, objectKind.rawValue, objectID.rawValue].joined(separator: "|")
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
