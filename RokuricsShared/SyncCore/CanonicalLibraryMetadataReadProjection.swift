//
//  CanonicalLibraryMetadataReadProjection.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated enum CanonicalLibraryMetadataReadProjectionSource: String, Codable, Equatable, Hashable, Sendable {
    case legacy
    case canonical
}

nonisolated enum CanonicalLibraryMetadataReadProjectionFailureKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case snapshotMissing
    case missingMetadata
    case unsupportedObject
    case pathLeakRisk
    case fullContentRejected
}

nonisolated struct CanonicalLibraryMetadataReadProjectionFailure: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "run", reason].joined(separator: "|") }

    var kind: CanonicalLibraryMetadataReadProjectionFailureKind
    var objectID: String?
    var objectKind: CanonicalObjectKind?
    var reason: String

    nonisolated init(
        kind: CanonicalLibraryMetadataReadProjectionFailureKind,
        objectID: String? = nil,
        objectKind: CanonicalObjectKind? = nil,
        reason: String
    ) {
        self.kind = kind
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "library-object") }
        self.objectKind = objectKind
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? kind.rawValue
    }
}

nonisolated struct CanonicalLibraryMetadataReadProjectionFolder: Codable, Equatable, Identifiable, Sendable {
    var id: String { folderID.rawValue }

    var objectID: CanonicalLibraryObjectID
    var folderID: CanonicalLibraryObjectID
    var title: String
    var parentID: CanonicalLibraryObjectID?
    var hierarchyPath: [String]
    var hierarchyLevel: String?
    var colorToken: String?
    var orderingKey: String?
    var isDeleted: Bool
    var metadataHashPrefix: String?

    nonisolated init(folder: CanonicalFolderObject) {
        self.objectID = folder.folderID
        self.folderID = folder.folderID
        self.title = folder.metadata.name
        self.parentID = folder.metadata.parentID
        self.hierarchyPath = folder.metadata.hierarchyPath.components
        self.hierarchyLevel = folder.metadata.hierarchyLevel
        self.colorToken = folder.metadata.colorToken
        self.orderingKey = folder.metadata.orderingKey
        self.isDeleted = folder.metadata.isDeleted
        self.metadataHashPrefix = CanonicalProductionRedaction.hashPrefix(folder.metadataHash.value)
    }

    nonisolated var hierarchyKey: String {
        hierarchyPath.joined(separator: ">")
    }
}

nonisolated struct CanonicalLibraryMetadataReadProjectionItem: Codable, Equatable, Identifiable, Sendable {
    var id: String { itemID.rawValue }

    var objectID: CanonicalLibraryObjectID
    var itemID: CanonicalLibraryObjectID
    var title: String
    var itemKind: CanonicalStudyItemKind
    var folderIDs: [CanonicalLibraryObjectID]
    var parentReferences: [CanonicalParentReference]
    var tags: [String]
    var filingComponents: [String]
    var resourceTokenSummary: String
    var isDeleted: Bool
    var metadataHashPrefix: String?
    var orderingKey: String?

    nonisolated init(item: CanonicalStudyItemObject, objectID: CanonicalLibraryObjectID? = nil) {
        self.objectID = objectID ?? item.itemID
        self.itemID = item.itemID
        self.title = item.metadata.title
        self.itemKind = item.metadata.itemKind
        self.folderIDs = item.metadata.folderIDs
        self.parentReferences = item.metadata.parentReferences
        self.tags = item.metadata.tags
        self.filingComponents = item.metadata.filingPath.components
        self.resourceTokenSummary = Self.safeResourceTokenSummary(item.metadata.logicalResourceTokens)
        self.isDeleted = item.metadata.isDeleted
        self.metadataHashPrefix = CanonicalProductionRedaction.hashPrefix(item.metadataHash.value)
        self.orderingKey = nil
    }

    nonisolated var filingKey: String {
        filingComponents.joined(separator: ">")
    }

    nonisolated var folderIDKey: String {
        folderIDs.map(\.rawValue).joined(separator: "|")
    }

    nonisolated var parentReferenceKey: String {
        parentReferences.map { "\($0.relation):\($0.parentID.rawValue)" }.joined(separator: "|")
    }

    nonisolated var tagKey: String {
        tags.joined(separator: "|")
    }

    nonisolated static func safeResourceTokenSummary(_ tokens: [String]) -> String {
        let safePrefixes = tokens.compactMap { token -> String? in
            guard CanonicalProjectionContract.safeLogicalResourceToken(token) != nil,
                  !CanonicalProductionRedaction.containsSensitivePathSignal(token) else {
                return nil
            }
            return CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(token).value)
        }
        return "count=\(safePrefixes.count),tokens=\(safePrefixes.joined(separator: "+"))"
    }
}

nonisolated struct CanonicalLibraryMetadataReadProjectionNote: Codable, Equatable, Identifiable, Sendable {
    var id: String { noteItemID.rawValue }

    var objectID: CanonicalLibraryObjectID
    var noteItemID: CanonicalLibraryObjectID
    var title: String
    var folderIDs: [CanonicalLibraryObjectID]
    var parentReferences: [CanonicalParentReference]
    var tags: [String]
    var filingComponents: [String]
    var resourceTokenSummary: String
    var isDeleted: Bool
    var metadataHashPrefix: String?
    var fullContentIncluded: Bool

    nonisolated init(item: CanonicalStudyItemObject, objectID: CanonicalLibraryObjectID? = nil) {
        self.objectID = objectID ?? item.itemID
        self.noteItemID = item.itemID
        self.title = item.metadata.title
        self.folderIDs = item.metadata.folderIDs
        self.parentReferences = item.metadata.parentReferences
        self.tags = item.metadata.tags
        self.filingComponents = item.metadata.filingPath.components
        self.resourceTokenSummary = CanonicalLibraryMetadataReadProjectionItem.safeResourceTokenSummary(item.metadata.logicalResourceTokens)
        self.isDeleted = item.metadata.isDeleted
        self.metadataHashPrefix = CanonicalProductionRedaction.hashPrefix(item.metadataHash.value)
        self.fullContentIncluded = false
    }

    nonisolated var filingKey: String {
        filingComponents.joined(separator: ">")
    }

    nonisolated var folderIDKey: String {
        folderIDs.map(\.rawValue).joined(separator: "|")
    }

    nonisolated var parentReferenceKey: String {
        parentReferences.map { "\($0.relation):\($0.parentID.rawValue)" }.joined(separator: "|")
    }

    nonisolated var tagKey: String {
        tags.joined(separator: "|")
    }
}

nonisolated struct CanonicalLibraryMetadataReadSnapshot: Codable, Equatable, Sendable {
    var source: CanonicalLibraryMetadataReadProjectionSource
    var generatedAt: CanonicalTimestamp
    var folders: [CanonicalLibraryMetadataReadProjectionFolder]
    var studyItems: [CanonicalLibraryMetadataReadProjectionItem]
    var standaloneNotes: [CanonicalLibraryMetadataReadProjectionNote]
    var failures: [CanonicalLibraryMetadataReadProjectionFailure]
    var contentExcludedCount: Int

    nonisolated init(
        source: CanonicalLibraryMetadataReadProjectionSource,
        generatedAt: Date = Date(),
        folders: [CanonicalLibraryMetadataReadProjectionFolder] = [],
        studyItems: [CanonicalLibraryMetadataReadProjectionItem] = [],
        standaloneNotes: [CanonicalLibraryMetadataReadProjectionNote] = [],
        failures: [CanonicalLibraryMetadataReadProjectionFailure] = [],
        contentExcludedCount: Int = 0
    ) {
        self.source = source
        self.generatedAt = CanonicalTimestamp(generatedAt)
        self.folders = folders.sorted { $0.folderID.rawValue < $1.folderID.rawValue }
        self.studyItems = studyItems.sorted { $0.itemID.rawValue < $1.itemID.rawValue }
        self.standaloneNotes = standaloneNotes.sorted { $0.noteItemID.rawValue < $1.noteItemID.rawValue }
        self.failures = failures.sorted { $0.id < $1.id }
        self.contentExcludedCount = max(0, contentExcludedCount)
    }

    nonisolated var objectCount: Int {
        folders.count + studyItems.count + standaloneNotes.count
    }

    nonisolated var unsupportedObjectCount: Int {
        failures.filter { $0.kind == .unsupportedObject || $0.kind == .missingMetadata }.count
    }

    nonisolated var pathLeakRiskCount: Int {
        failures.filter { $0.kind == .pathLeakRisk }.count
    }

    nonisolated var fullContentIncluded: Bool {
        standaloneNotes.contains { $0.fullContentIncluded }
    }

    nonisolated var diagnosticsSummary: String {
        [
            "source=\(source.rawValue)",
            "folders=\(folders.count)",
            "items=\(studyItems.count)",
            "notes=\(standaloneNotes.count)",
            "unsupported=\(unsupportedObjectCount)",
            "pathLeakRisk=\(pathLeakRiskCount)",
            "contentExcluded=\(contentExcludedCount)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalLibraryMetadataReadProjection: Codable, Equatable, Sendable {
    var snapshot: CanonicalLibraryMetadataReadSnapshot

    nonisolated init(snapshot: CanonicalLibraryMetadataReadSnapshot) {
        self.snapshot = snapshot
    }

    nonisolated static func build(
        source: CanonicalLibraryMetadataReadProjectionSource,
        manifest: CanonicalManifest?,
        generatedAt: Date = Date()
    ) -> CanonicalLibraryMetadataReadProjection {
        guard let manifest else {
            return CanonicalLibraryMetadataReadProjection(
                snapshot: CanonicalLibraryMetadataReadSnapshot(
                    source: source,
                    generatedAt: generatedAt,
                    failures: [
                        CanonicalLibraryMetadataReadProjectionFailure(
                            kind: .snapshotMissing,
                            reason: "canonicalManifestMissing"
                        )
                    ]
                )
            )
        }
        return build(source: source, objects: manifest.libraryObjects, generatedAt: generatedAt)
    }

    nonisolated static func build(
        source: CanonicalLibraryMetadataReadProjectionSource,
        objects: [CanonicalLibraryObject],
        generatedAt: Date = Date()
    ) -> CanonicalLibraryMetadataReadProjection {
        var folders: [CanonicalLibraryMetadataReadProjectionFolder] = []
        var studyItems: [CanonicalLibraryMetadataReadProjectionItem] = []
        var standaloneNotes: [CanonicalLibraryMetadataReadProjectionNote] = []
        var failures: [CanonicalLibraryMetadataReadProjectionFailure] = []

        for object in objects.sorted(by: { $0.objectID.rawValue < $1.objectID.rawValue }) {
            switch object.kind {
            case .folder:
                guard let folder = object.folder else {
                    failures.append(.init(kind: .missingMetadata, objectID: object.objectID.rawValue, objectKind: object.kind, reason: "folderMetadataMissing"))
                    continue
                }
                folders.append(CanonicalLibraryMetadataReadProjectionFolder(folder: folder))
            case .standaloneNote:
                guard let item = object.standaloneNote?.studyItem ?? object.studyItem else {
                    failures.append(.init(kind: .missingMetadata, objectID: object.objectID.rawValue, objectKind: object.kind, reason: "standaloneNoteMetadataMissing"))
                    continue
                }
                standaloneNotes.append(CanonicalLibraryMetadataReadProjectionNote(item: item, objectID: object.objectID))
            case .standaloneStudyItem, .recordingAssociatedStudyItem:
                guard let item = object.studyItem else {
                    failures.append(.init(kind: .missingMetadata, objectID: object.objectID.rawValue, objectKind: object.kind, reason: "studyItemMetadataMissing"))
                    continue
                }
                studyItems.append(CanonicalLibraryMetadataReadProjectionItem(item: item, objectID: object.objectID))
            case .recording, .generatedArtifactEnvelope, .unknownUnsupported:
                failures.append(.init(kind: .unsupportedObject, objectID: object.objectID.rawValue, objectKind: object.kind, reason: object.unsupportedReason ?? "unsupportedLibraryMetadataReadObject"))
            }
        }

        let contentExcludedCount = standaloneNotes.count
        return CanonicalLibraryMetadataReadProjection(
            snapshot: CanonicalLibraryMetadataReadSnapshot(
                source: source,
                generatedAt: generatedAt,
                folders: folders,
                studyItems: studyItems,
                standaloneNotes: standaloneNotes,
                failures: failures,
                contentExcludedCount: contentExcludedCount
            )
        )
    }
}

nonisolated enum CanonicalLibraryMetadataReadSideDivergenceKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingInCanonical
    case missingInLegacy
    case titleMismatch
    case parentMismatch
    case folderMembershipMismatch
    case filingMismatch
    case tagsMismatch
    case colorMismatch
    case orderingMismatch
    case trashStateMismatch
    case objectIDMismatch
    case unsupportedLegacyObject
    case unsupportedCanonicalObject
    case contentExcluded
    case pathLeakRisk
}

nonisolated struct CanonicalLibraryMetadataReadSideDivergence: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID, field ?? ""].joined(separator: "|") }

    var kind: CanonicalLibraryMetadataReadSideDivergenceKind
    var objectID: String
    var objectKind: CanonicalObjectKind?
    var field: String?
    var legacyValue: String?
    var canonicalValue: String?
    var fatal: Bool

    nonisolated init(
        kind: CanonicalLibraryMetadataReadSideDivergenceKind,
        objectID: String,
        objectKind: CanonicalObjectKind? = nil,
        field: String? = nil,
        legacyValue: String? = nil,
        canonicalValue: String? = nil,
        fatal: Bool = false
    ) {
        self.kind = kind
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "library-object")
        self.objectKind = objectKind
        self.field = CanonicalProductionRedaction.safeDiagnosticText(field)
        self.legacyValue = CanonicalProductionRedaction.safeDiagnosticText(legacyValue)
        self.canonicalValue = CanonicalProductionRedaction.safeDiagnosticText(canonicalValue)
        self.fatal = fatal || kind == .pathLeakRisk
    }

    nonisolated var isBlocking: Bool {
        switch kind {
        case .contentExcluded:
            return false
        default:
            return true
        }
    }
}

nonisolated struct CanonicalLibraryMetadataReadSideEquivalence: Codable, Equatable, Sendable {
    var equivalent: Bool
    var folderCount: Int
    var studyItemCount: Int
    var standaloneNoteCount: Int
    var contentExcludedCount: Int
    var diagnosticsSummary: String
}

nonisolated enum CanonicalLibraryMetadataReadSideBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case blockingDivergence
    case unsupportedObject
    case pathLeakRisk
    case missingLegacySnapshot
    case missingCanonicalSnapshot
}

nonisolated struct CanonicalLibraryMetadataReadSideDiffReport: Codable, Equatable, Sendable {
    var equivalence: CanonicalLibraryMetadataReadSideEquivalence
    var divergences: [CanonicalLibraryMetadataReadSideDivergence]
    var blockers: [CanonicalLibraryMetadataReadSideBlocker]
    var legacySnapshotSummary: String
    var canonicalSnapshotSummary: String
    var diagnosticsSummary: String

    nonisolated var equivalent: Bool {
        blockers.isEmpty && divergences.allSatisfy { !$0.isBlocking }
    }

    nonisolated var divergenceCount: Int {
        divergences.filter(\.isBlocking).count
    }

    nonisolated var unsupportedObjectCount: Int {
        divergences.filter {
            $0.kind == .unsupportedLegacyObject || $0.kind == .unsupportedCanonicalObject
        }.count
    }

    nonisolated var pathLeakRiskCount: Int {
        divergences.filter { $0.kind == .pathLeakRisk }.count
    }
}

nonisolated enum CanonicalLibraryMetadataReadSideParallelDiff {
    nonisolated static func compare(
        legacy: CanonicalLibraryMetadataReadSnapshot,
        canonical: CanonicalLibraryMetadataReadSnapshot
    ) -> CanonicalLibraryMetadataReadSideDiffReport {
        var divergences: [CanonicalLibraryMetadataReadSideDivergence] = []

        appendFailureDivergences(snapshot: legacy, into: &divergences)
        appendFailureDivergences(snapshot: canonical, into: &divergences)
        compareFolders(legacy.folders, canonical.folders, into: &divergences)
        compareItems(legacy.studyItems, canonical.studyItems, into: &divergences)
        compareNotes(legacy.standaloneNotes, canonical.standaloneNotes, into: &divergences)

        var blockers: [CanonicalLibraryMetadataReadSideBlocker] = []
        if legacy.failures.contains(where: { $0.kind == .snapshotMissing }) {
            blockers.append(.missingLegacySnapshot)
        }
        if canonical.failures.contains(where: { $0.kind == .snapshotMissing }) {
            blockers.append(.missingCanonicalSnapshot)
        }
        if divergences.contains(where: { $0.kind == .pathLeakRisk }) {
            blockers.append(.pathLeakRisk)
        }
        if divergences.contains(where: { $0.kind == .unsupportedLegacyObject || $0.kind == .unsupportedCanonicalObject }) {
            blockers.append(.unsupportedObject)
        }
        if divergences.contains(where: \.isBlocking) {
            blockers.append(.blockingDivergence)
        }
        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let equivalent = uniqueBlockers.isEmpty && divergences.allSatisfy { !$0.isBlocking }
        let equivalence = CanonicalLibraryMetadataReadSideEquivalence(
            equivalent: equivalent,
            folderCount: canonical.folders.count,
            studyItemCount: canonical.studyItems.count,
            standaloneNoteCount: canonical.standaloneNotes.count,
            contentExcludedCount: canonical.contentExcludedCount + legacy.contentExcludedCount,
            diagnosticsSummary: "equivalent=\(equivalent),folders=\(canonical.folders.count),items=\(canonical.studyItems.count),notes=\(canonical.standaloneNotes.count),contentExcluded=\(canonical.contentExcludedCount + legacy.contentExcludedCount)"
        )
        let divergenceSummary = Array(Set(divergences.map(\.kind.rawValue))).sorted().joined(separator: "+")
        return CanonicalLibraryMetadataReadSideDiffReport(
            equivalence: equivalence,
            divergences: divergences.sorted { $0.id < $1.id },
            blockers: uniqueBlockers,
            legacySnapshotSummary: legacy.diagnosticsSummary,
            canonicalSnapshotSummary: canonical.diagnosticsSummary,
            diagnosticsSummary: "domain=libraryMetadata,equivalent=\(equivalent),divergences=\(divergences.filter(\.isBlocking).count),unsupported=\(divergences.filter { $0.kind == .unsupportedLegacyObject || $0.kind == .unsupportedCanonicalObject }.count),pathLeakRisk=\(divergences.filter { $0.kind == .pathLeakRisk }.count),kinds=\(divergenceSummary)"
        )
    }

    nonisolated private static func appendFailureDivergences(
        snapshot: CanonicalLibraryMetadataReadSnapshot,
        into divergences: inout [CanonicalLibraryMetadataReadSideDivergence]
    ) {
        for failure in snapshot.failures {
            switch failure.kind {
            case .pathLeakRisk:
                divergences.append(.init(kind: .pathLeakRisk, objectID: failure.objectID ?? "run", objectKind: failure.objectKind, field: "projection", legacyValue: snapshot.source.rawValue, canonicalValue: failure.reason, fatal: true))
            case .unsupportedObject, .missingMetadata:
                divergences.append(.init(kind: snapshot.source == .legacy ? .unsupportedLegacyObject : .unsupportedCanonicalObject, objectID: failure.objectID ?? "run", objectKind: failure.objectKind, field: "object", legacyValue: snapshot.source.rawValue, canonicalValue: failure.reason))
            case .snapshotMissing:
                divergences.append(.init(kind: snapshot.source == .legacy ? .missingInLegacy : .missingInCanonical, objectID: "snapshot", field: "snapshot", legacyValue: snapshot.source.rawValue, canonicalValue: failure.reason))
            case .fullContentRejected:
                break
            }
        }
    }

    nonisolated private static func compareFolders(
        _ legacy: [CanonicalLibraryMetadataReadProjectionFolder],
        _ canonical: [CanonicalLibraryMetadataReadProjectionFolder],
        into divergences: inout [CanonicalLibraryMetadataReadSideDivergence]
    ) {
        let legacyByID = Dictionary(uniqueKeysWithValues: legacy.map { ($0.folderID.rawValue, $0) })
        let canonicalByID = Dictionary(uniqueKeysWithValues: canonical.map { ($0.folderID.rawValue, $0) })
        for id in Set(legacyByID.keys).union(canonicalByID.keys).sorted() {
            guard let legacy = legacyByID[id] else {
                divergences.append(.init(kind: .missingInLegacy, objectID: id, objectKind: .folder))
                continue
            }
            guard let canonical = canonicalByID[id] else {
                divergences.append(.init(kind: .missingInCanonical, objectID: id, objectKind: .folder))
                continue
            }
            appendMismatch(.titleMismatch, id, .folder, "title", legacy.title, canonical.title, into: &divergences)
            appendMismatch(.parentMismatch, id, .folder, "parentID", legacy.parentID?.rawValue ?? "root", canonical.parentID?.rawValue ?? "root", into: &divergences)
            appendMismatch(.parentMismatch, id, .folder, "hierarchyPath", legacy.hierarchyKey, canonical.hierarchyKey, into: &divergences)
            appendMismatch(.parentMismatch, id, .folder, "hierarchyLevel", legacy.hierarchyLevel ?? "none", canonical.hierarchyLevel ?? "none", into: &divergences)
            appendMismatch(.colorMismatch, id, .folder, "color", legacy.colorToken ?? "none", canonical.colorToken ?? "none", into: &divergences)
            appendMismatch(.orderingMismatch, id, .folder, "ordering", legacy.orderingKey ?? "none", canonical.orderingKey ?? "none", into: &divergences)
            appendMismatch(.trashStateMismatch, id, .folder, "trash", String(legacy.isDeleted), String(canonical.isDeleted), into: &divergences)
        }
    }

    nonisolated private static func compareItems(
        _ legacy: [CanonicalLibraryMetadataReadProjectionItem],
        _ canonical: [CanonicalLibraryMetadataReadProjectionItem],
        into divergences: inout [CanonicalLibraryMetadataReadSideDivergence]
    ) {
        let legacyByID = Dictionary(uniqueKeysWithValues: legacy.map { ($0.itemID.rawValue, $0) })
        let canonicalByID = Dictionary(uniqueKeysWithValues: canonical.map { ($0.itemID.rawValue, $0) })
        for id in Set(legacyByID.keys).union(canonicalByID.keys).sorted() {
            guard let legacy = legacyByID[id] else {
                divergences.append(.init(kind: .missingInLegacy, objectID: id, objectKind: .standaloneStudyItem))
                continue
            }
            guard let canonical = canonicalByID[id] else {
                divergences.append(.init(kind: .missingInCanonical, objectID: id, objectKind: .standaloneStudyItem))
                continue
            }
            compareItemFields(id: id, objectKind: .standaloneStudyItem, legacy: legacy, canonical: canonical, into: &divergences)
        }
    }

    nonisolated private static func compareNotes(
        _ legacy: [CanonicalLibraryMetadataReadProjectionNote],
        _ canonical: [CanonicalLibraryMetadataReadProjectionNote],
        into divergences: inout [CanonicalLibraryMetadataReadSideDivergence]
    ) {
        let legacyByID = Dictionary(uniqueKeysWithValues: legacy.map { ($0.noteItemID.rawValue, $0) })
        let canonicalByID = Dictionary(uniqueKeysWithValues: canonical.map { ($0.noteItemID.rawValue, $0) })
        for id in Set(legacyByID.keys).union(canonicalByID.keys).sorted() {
            guard let legacy = legacyByID[id] else {
                divergences.append(.init(kind: .missingInLegacy, objectID: id, objectKind: .standaloneNote))
                continue
            }
            guard let canonical = canonicalByID[id] else {
                divergences.append(.init(kind: .missingInCanonical, objectID: id, objectKind: .standaloneNote))
                continue
            }
            appendMismatch(.titleMismatch, id, .standaloneNote, "title", legacy.title, canonical.title, into: &divergences)
            appendMismatch(.folderMembershipMismatch, id, .standaloneNote, "folders", legacy.folderIDKey, canonical.folderIDKey, into: &divergences)
            appendMismatch(.parentMismatch, id, .standaloneNote, "parents", legacy.parentReferenceKey, canonical.parentReferenceKey, into: &divergences)
            appendMismatch(.filingMismatch, id, .standaloneNote, "filing", legacy.filingKey, canonical.filingKey, into: &divergences)
            appendMismatch(.tagsMismatch, id, .standaloneNote, "tags", legacy.tagKey, canonical.tagKey, into: &divergences)
            appendMismatch(.trashStateMismatch, id, .standaloneNote, "trash", String(legacy.isDeleted), String(canonical.isDeleted), into: &divergences)
            appendMismatch(.folderMembershipMismatch, id, .standaloneNote, "resourceSummary", legacy.resourceTokenSummary, canonical.resourceTokenSummary, into: &divergences)
        }
    }

    nonisolated private static func compareItemFields(
        id: String,
        objectKind: CanonicalObjectKind,
        legacy: CanonicalLibraryMetadataReadProjectionItem,
        canonical: CanonicalLibraryMetadataReadProjectionItem,
        into divergences: inout [CanonicalLibraryMetadataReadSideDivergence]
    ) {
        appendMismatch(.titleMismatch, id, objectKind, "title", legacy.title, canonical.title, into: &divergences)
        appendMismatch(.folderMembershipMismatch, id, objectKind, "folders", legacy.folderIDKey, canonical.folderIDKey, into: &divergences)
        appendMismatch(.parentMismatch, id, objectKind, "parents", legacy.parentReferenceKey, canonical.parentReferenceKey, into: &divergences)
        appendMismatch(.filingMismatch, id, objectKind, "filing", legacy.filingKey, canonical.filingKey, into: &divergences)
        appendMismatch(.tagsMismatch, id, objectKind, "tags", legacy.tagKey, canonical.tagKey, into: &divergences)
        appendMismatch(.objectIDMismatch, id, objectKind, "itemKind", legacy.itemKind.rawValue, canonical.itemKind.rawValue, into: &divergences)
        appendMismatch(.trashStateMismatch, id, objectKind, "trash", String(legacy.isDeleted), String(canonical.isDeleted), into: &divergences)
        appendMismatch(.folderMembershipMismatch, id, objectKind, "resourceSummary", legacy.resourceTokenSummary, canonical.resourceTokenSummary, into: &divergences)
    }

    nonisolated private static func appendMismatch(
        _ kind: CanonicalLibraryMetadataReadSideDivergenceKind,
        _ objectID: String,
        _ objectKind: CanonicalObjectKind,
        _ field: String,
        _ legacyValue: String,
        _ canonicalValue: String,
        into divergences: inout [CanonicalLibraryMetadataReadSideDivergence]
    ) {
        guard legacyValue != canonicalValue else {
            return
        }
        divergences.append(
            CanonicalLibraryMetadataReadSideDivergence(
                kind: kind,
                objectID: objectID,
                objectKind: objectKind,
                field: field,
                legacyValue: legacyValue,
                canonicalValue: canonicalValue
            )
        )
    }
}

nonisolated struct CanonicalLibraryMetadataWriteSideEvidenceLinkage: Codable, Equatable, Sendable {
    var canaryStageStatus: CanonicalLibraryMetadataStageEvidenceStatus
    var latestSuccessfulStage: CanonicalLibraryMetadataCanaryStage?
    var rollbackFailureCount: Int
    var duplicateSuppressionCount: Int
    var unresolvedConflictCount: Int
    var resourceMoveBlockedCount: Int
    var readSideDivergenceCount: Int
    var writeSideDomainCutoverComplete: Bool

    nonisolated init(
        canaryStageStatus: CanonicalLibraryMetadataStageEvidenceStatus = .missing,
        latestSuccessfulStage: CanonicalLibraryMetadataCanaryStage? = nil,
        rollbackFailureCount: Int = 0,
        duplicateSuppressionCount: Int = 0,
        unresolvedConflictCount: Int = 0,
        resourceMoveBlockedCount: Int = 0,
        readSideDivergenceCount: Int = 0,
        writeSideDomainCutoverComplete: Bool = false
    ) {
        self.canaryStageStatus = canaryStageStatus
        self.latestSuccessfulStage = latestSuccessfulStage
        self.rollbackFailureCount = max(0, rollbackFailureCount)
        self.duplicateSuppressionCount = max(0, duplicateSuppressionCount)
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.resourceMoveBlockedCount = max(0, resourceMoveBlockedCount)
        self.readSideDivergenceCount = max(0, readSideDivergenceCount)
        self.writeSideDomainCutoverComplete = writeSideDomainCutoverComplete
    }

    nonisolated static let missing = CanonicalLibraryMetadataWriteSideEvidenceLinkage()

    nonisolated static func from(
        stageEvidence: CanonicalLibraryMetadataCanaryStageEvidence?,
        writeSideDomainCutoverComplete: Bool = false
    ) -> CanonicalLibraryMetadataWriteSideEvidenceLinkage {
        guard let stageEvidence else {
            return .missing
        }
        return CanonicalLibraryMetadataWriteSideEvidenceLinkage(
            canaryStageStatus: stageEvidence.status,
            latestSuccessfulStage: stageEvidence.status == .passed ? stageEvidence.stage : nil,
            rollbackFailureCount: stageEvidence.rollbackFailureCount,
            duplicateSuppressionCount: stageEvidence.suppressedLegacyDuplicateCount,
            unresolvedConflictCount: stageEvidence.unresolvedConflictCount,
            resourceMoveBlockedCount: stageEvidence.resourceMoveAttemptCount,
            readSideDivergenceCount: stageEvidence.readSideParallelDivergenceCount,
            writeSideDomainCutoverComplete: writeSideDomainCutoverComplete
        )
    }

    nonisolated var hasCleanStagedCanaryEvidence: Bool {
        canaryStageStatus == .passed
            && latestSuccessfulStage != nil
            && rollbackFailureCount == 0
            && unresolvedConflictCount == 0
            && resourceMoveBlockedCount == 0
            && readSideDivergenceCount == 0
    }

    nonisolated var diagnosticsSummary: String {
        [
            "stageStatus=\(canaryStageStatus.rawValue)",
            "latestStage=\(latestSuccessfulStage?.rawValue ?? "none")",
            "rollbackFailures=\(rollbackFailureCount)",
            "duplicateSuppression=\(duplicateSuppressionCount)",
            "unresolvedConflicts=\(unresolvedConflictCount)",
            "resourceMoveBlocked=\(resourceMoveBlockedCount)",
            "readSideDivergence=\(readSideDivergenceCount)",
            "domainCutover=\(writeSideDomainCutoverComplete)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalLibraryMetadataReadSideCutoverMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case parallelOnly
    case canonicalReadCandidate
    case guardedCanonicalRead
    case blocked
}

nonisolated enum CanonicalLibraryMetadataReadSideCutoverFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable, Error {
    case disabled
    case blockingDivergence
    case unsupportedObject
    case missingWriteSideEvidence
    case fallbackMissing
    case pathLeakRisk
    case otherActiveDomain
    case rollbackFatal
    case legacyReadSuppressed
}

nonisolated enum CanonicalLibraryMetadataReadSideCutoverCandidateState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readyForGuardedCanonicalRead
    case blockedByDivergence
    case blockedByUnsupportedObject
    case blockedByMissingWriteSideEvidence
    case blockedByFallbackMissing
    case blockedByPathLeakRisk
    case blockedByOtherActiveDomain
    case disabled
}

nonisolated struct CanonicalLibraryMetadataReadSideCutoverPolicy: Codable, Equatable, Sendable {
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int
    var requireWriteSideEvidence: Bool
    var requireZeroDivergence: Bool
    var requireLegacyFallback: Bool
    var requireOnlyLibraryMetadataActivePilot: Bool

    nonisolated init(
        recordDiagnostics: Bool = true,
        maxDiagnosticsEvents: Int = 24,
        requireWriteSideEvidence: Bool = true,
        requireZeroDivergence: Bool = true,
        requireLegacyFallback: Bool = true,
        requireOnlyLibraryMetadataActivePilot: Bool = true
    ) {
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(0, maxDiagnosticsEvents)
        self.requireWriteSideEvidence = requireWriteSideEvidence
        self.requireZeroDivergence = requireZeroDivergence
        self.requireLegacyFallback = requireLegacyFallback
        self.requireOnlyLibraryMetadataActivePilot = requireOnlyLibraryMetadataActivePilot
    }
}

nonisolated struct CanonicalLibraryMetadataReadSideCutoverConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalLibraryMetadataReadSideCutoverMode
    var policy: CanonicalLibraryMetadataReadSideCutoverPolicy
    var writeSideEvidence: CanonicalLibraryMetadataWriteSideEvidenceLinkage
    var legacyFallbackAvailable: Bool

    nonisolated init(
        mode: CanonicalLibraryMetadataReadSideCutoverMode = .disabled,
        policy: CanonicalLibraryMetadataReadSideCutoverPolicy = CanonicalLibraryMetadataReadSideCutoverPolicy(),
        writeSideEvidence: CanonicalLibraryMetadataWriteSideEvidenceLinkage = .missing,
        legacyFallbackAvailable: Bool = true
    ) {
        self.mode = mode
        self.policy = policy
        self.writeSideEvidence = writeSideEvidence
        self.legacyFallbackAvailable = legacyFallbackAvailable
    }

    nonisolated static let disabled = CanonicalLibraryMetadataReadSideCutoverConfiguration()

    nonisolated var isEnabled: Bool {
        mode != .disabled && mode != .blocked
    }
}

nonisolated struct CanonicalLibraryMetadataReadSideCutoverCandidateResult: Codable, Equatable, Sendable {
    var state: CanonicalLibraryMetadataReadSideCutoverCandidateState
    var failures: [CanonicalLibraryMetadataReadSideCutoverFailure]
    var legacyFallbackAvailable: Bool
    var divergenceZero: Bool
    var unsupportedCount: Int
    var pathLeakRiskCount: Int
    var objectIDStable: Bool
    var noResourceMove: Bool
    var noTombstoneDeleteCutover: Bool
    var writeSideEvidence: CanonicalLibraryMetadataWriteSideEvidenceLinkage
    var diagnosticsSummary: String

    nonisolated var ready: Bool {
        state == .readyForGuardedCanonicalRead
    }
}

nonisolated struct CanonicalLibraryMetadataReadSideCutoverResult: Codable, Equatable, Sendable {
    var mode: CanonicalLibraryMetadataReadSideCutoverMode
    var diffReport: CanonicalLibraryMetadataReadSideDiffReport?
    var candidate: CanonicalLibraryMetadataReadSideCutoverCandidateResult
    var failures: [CanonicalLibraryMetadataReadSideCutoverFailure]
    var legacyReadFallbackAvailable: Bool
    var readPathSwitched: Bool
    var uiMutated: Bool
    var syncOrUploadTriggered: Bool
    var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic]
    var diagnosticsSummary: String
}

nonisolated enum CanonicalLibraryMetadataReadSideCutoverEvaluator {
    nonisolated static func evaluate(
        configuration: CanonicalLibraryMetadataReadSideCutoverConfiguration,
        legacySnapshot: CanonicalLibraryMetadataReadSnapshot,
        canonicalSnapshot: CanonicalLibraryMetadataReadSnapshot,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813(),
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String?
    ) -> CanonicalLibraryMetadataReadSideCutoverResult {
        if configuration.mode == .disabled || configuration.mode == .blocked {
            let candidate = CanonicalLibraryMetadataReadSideCutoverCandidateResult(
                state: .disabled,
                failures: [.disabled],
                legacyFallbackAvailable: configuration.legacyFallbackAvailable,
                divergenceZero: false,
                unsupportedCount: 0,
                pathLeakRiskCount: 0,
                objectIDStable: true,
                noResourceMove: true,
                noTombstoneDeleteCutover: true,
                writeSideEvidence: configuration.writeSideEvidence,
                diagnosticsSummary: "state=disabled"
            )
            return CanonicalLibraryMetadataReadSideCutoverResult(
                mode: configuration.mode,
                diffReport: nil,
                candidate: candidate,
                failures: [.disabled],
                legacyReadFallbackAvailable: configuration.legacyFallbackAvailable,
                readPathSwitched: false,
                uiMutated: false,
                syncOrUploadTriggered: false,
                diagnostics: [],
                diagnosticsSummary: "mode=\(configuration.mode.rawValue),state=disabled"
            )
        }

        let report = CanonicalLibraryMetadataReadSideParallelDiff.compare(
            legacy: legacySnapshot,
            canonical: canonicalSnapshot
        )
        let candidate = evaluateCandidate(
            configuration: configuration,
            report: report,
            matrix: matrix
        )
        var failures = candidate.failures
        if configuration.writeSideEvidence.rollbackFailureCount > 0 {
            failures.append(.rollbackFatal)
        }
        let diagnostics = configuration.policy.recordDiagnostics ? makeDiagnostics(
            configuration: configuration,
            report: report,
            candidate: candidate,
            trigger: trigger,
            nodeRole: nodeRole,
            syncRunID: syncRunID
        ) : []
        let limitedDiagnostics = Array(diagnostics.prefix(configuration.policy.maxDiagnosticsEvents))
        return CanonicalLibraryMetadataReadSideCutoverResult(
            mode: configuration.mode,
            diffReport: report,
            candidate: candidate,
            failures: Array(Set(failures)).sorted { $0.rawValue < $1.rawValue },
            legacyReadFallbackAvailable: configuration.legacyFallbackAvailable,
            readPathSwitched: false,
            uiMutated: false,
            syncOrUploadTriggered: false,
            diagnostics: limitedDiagnostics,
            diagnosticsSummary: "mode=\(configuration.mode.rawValue),candidate=\(candidate.state.rawValue),divergences=\(report.divergenceCount),fallback=\(configuration.legacyFallbackAvailable),readPathSwitched=false,uiMutated=false,syncOrUploadTriggered=false"
        )
    }

    nonisolated private static func evaluateCandidate(
        configuration: CanonicalLibraryMetadataReadSideCutoverConfiguration,
        report: CanonicalLibraryMetadataReadSideDiffReport,
        matrix: CanonicalMigrationDomainMatrix
    ) -> CanonicalLibraryMetadataReadSideCutoverCandidateResult {
        var failures: [CanonicalLibraryMetadataReadSideCutoverFailure] = []
        let matrixReport = matrix.validate()
        if configuration.policy.requireOnlyLibraryMetadataActivePilot,
           matrixReport.activePilotDomain != .libraryMetadata || matrixReport.blockers.contains(.multipleActivePilots) {
            failures.append(.otherActiveDomain)
        }
        if configuration.policy.requireLegacyFallback, !configuration.legacyFallbackAvailable {
            failures.append(.fallbackMissing)
        }
        if configuration.policy.requireWriteSideEvidence {
            let evidence = configuration.writeSideEvidence
            if !evidence.hasCleanStagedCanaryEvidence || evidence.rollbackFailureCount > 0 {
                failures.append(evidence.rollbackFailureCount > 0 ? .rollbackFatal : .missingWriteSideEvidence)
            }
        }
        if configuration.policy.requireZeroDivergence, report.divergenceCount > 0 {
            failures.append(.blockingDivergence)
        }
        if report.unsupportedObjectCount > 0 {
            failures.append(.unsupportedObject)
        }
        if report.pathLeakRiskCount > 0 {
            failures.append(.pathLeakRisk)
        }

        let uniqueFailures = Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
        let state: CanonicalLibraryMetadataReadSideCutoverCandidateState
        if uniqueFailures.contains(.pathLeakRisk) {
            state = .blockedByPathLeakRisk
        } else if uniqueFailures.contains(.unsupportedObject) {
            state = .blockedByUnsupportedObject
        } else if uniqueFailures.contains(.missingWriteSideEvidence) || uniqueFailures.contains(.rollbackFatal) {
            state = .blockedByMissingWriteSideEvidence
        } else if uniqueFailures.contains(.otherActiveDomain) {
            state = .blockedByOtherActiveDomain
        } else if uniqueFailures.contains(.fallbackMissing) {
            state = .blockedByFallbackMissing
        } else if uniqueFailures.contains(.blockingDivergence) {
            state = .blockedByDivergence
        } else {
            state = .readyForGuardedCanonicalRead
        }

        return CanonicalLibraryMetadataReadSideCutoverCandidateResult(
            state: state,
            failures: uniqueFailures,
            legacyFallbackAvailable: configuration.legacyFallbackAvailable,
            divergenceZero: report.divergenceCount == 0,
            unsupportedCount: report.unsupportedObjectCount,
            pathLeakRiskCount: report.pathLeakRiskCount,
            objectIDStable: !report.divergences.contains { $0.kind == .objectIDMismatch },
            noResourceMove: true,
            noTombstoneDeleteCutover: true,
            writeSideEvidence: configuration.writeSideEvidence,
            diagnosticsSummary: "state=\(state.rawValue),divergenceZero=\(report.divergenceCount == 0),unsupported=\(report.unsupportedObjectCount),pathLeakRisk=\(report.pathLeakRiskCount),fallback=\(configuration.legacyFallbackAvailable),writeSide=\(configuration.writeSideEvidence.diagnosticsSummary)"
        )
    }

    nonisolated private static func makeDiagnostics(
        configuration: CanonicalLibraryMetadataReadSideCutoverConfiguration,
        report: CanonicalLibraryMetadataReadSideDiffReport,
        candidate: CanonicalLibraryMetadataReadSideCutoverCandidateResult,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String?
    ) -> [CanonicalLibraryMetadataCutoverDiagnostic] {
        var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic] = [
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: .canonicalLibraryMetadataReadSideParallelStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: configuration.mode.rawValue,
                reason: "domain=libraryMetadata"
            )
        ]
        diagnostics.append(
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: report.equivalent ? .canonicalLibraryMetadataReadSideEquivalent : .canonicalLibraryMetadataReadSideDivergent,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: report.equivalent ? "equivalent" : "divergent",
                reason: report.diagnosticsSummary
            )
        )
        if report.unsupportedObjectCount > 0 {
            diagnostics.append(
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataReadSideUnsupportedObject,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "blocked",
                    reason: "unsupported=\(report.unsupportedObjectCount)"
                )
            )
        }
        if report.pathLeakRiskCount > 0 {
            diagnostics.append(
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataReadSidePathLeakBlocked,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "fatal",
                    reason: "pathLeakRisk=\(report.pathLeakRiskCount)"
                )
            )
        }
        diagnostics.append(
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: .canonicalLibraryMetadataReadSideParallelCompleted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: report.equivalent ? "equivalent" : "divergent",
                reason: "divergenceCount=\(report.divergenceCount)"
            )
        )
        diagnostics.append(
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: .canonicalLibraryMetadataReadSideCutoverCandidateEvaluated,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: candidate.state.rawValue,
                reason: candidate.diagnosticsSummary
            )
        )
        diagnostics.append(
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: candidate.ready ? .canonicalLibraryMetadataReadSideCutoverCandidateReady : .canonicalLibraryMetadataReadSideCutoverCandidateBlocked,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: candidate.ready ? "ready" : "blocked",
                reason: candidate.failures.map(\.rawValue).joined(separator: "+")
            )
        )
        diagnostics.append(
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: .canonicalLibraryMetadataLegacyReadFallbackAvailable,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: configuration.legacyFallbackAvailable ? "available" : "missing",
                reason: "fallbackPreserved"
            )
        )
        if configuration.mode == .guardedCanonicalRead {
            diagnostics.append(
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataGuardedCanonicalReadSuppressed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "suppressed",
                    reason: "defaultOffSeamNoUISwitch"
                )
            )
        }
        return diagnostics
    }
}

nonisolated enum CanonicalLibraryMetadataReadSourceMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case legacy
    case parallelCompare
    case canonicalCandidate
    case guardedCanonicalRead
    case blocked
}

nonisolated struct CanonicalLibraryMetadataReadSourceConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalLibraryMetadataReadSourceMode
    var explicitInternalTestConfiguration: Bool
    var uiCutoverGlobal: Bool
    var runtimeSwitchEnabled: Bool
    var strictFallbackOnDivergence: Bool
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int

    nonisolated init(
        mode: CanonicalLibraryMetadataReadSourceMode = .legacy,
        explicitInternalTestConfiguration: Bool = false,
        uiCutoverGlobal: Bool = false,
        runtimeSwitchEnabled: Bool = false,
        strictFallbackOnDivergence: Bool = true,
        recordDiagnostics: Bool = true,
        maxDiagnosticsEvents: Int = 32
    ) {
        self.mode = mode
        self.explicitInternalTestConfiguration = explicitInternalTestConfiguration
        self.uiCutoverGlobal = uiCutoverGlobal
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.strictFallbackOnDivergence = strictFallbackOnDivergence
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(0, maxDiagnosticsEvents)
    }

    nonisolated static let legacy = CanonicalLibraryMetadataReadSourceConfiguration()

    nonisolated static func explicitGuardedCanonicalRead() -> CanonicalLibraryMetadataReadSourceConfiguration {
        CanonicalLibraryMetadataReadSourceConfiguration(
            mode: .guardedCanonicalRead,
            explicitInternalTestConfiguration: true
        )
    }
}

nonisolated enum CanonicalLibraryMetadataReadFallback: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case none
    case legacyDefault
    case gateBlocked
    case canonicalProjectionMissing
    case unsupportedObject
    case divergenceDetected
    case pathLeakRisk
    case canonicalReadException
    case blockedMode
}

nonisolated struct CanonicalLibraryMetadataReadSource: Codable, Equatable, Sendable {
    var source: CanonicalLibraryMetadataReadProjectionSource
    var snapshot: CanonicalLibraryMetadataReadSnapshot
    var metadataOnly: Bool
    var coversFolderMetadata: Bool
    var coversStudyItemMetadata: Bool
    var coversStandaloneNoteMetadata: Bool
    var excludesAudioState: Bool
    var excludesGeneratedArtifactContent: Bool
    var excludesStandaloneNoteContent: Bool

    nonisolated init(
        source: CanonicalLibraryMetadataReadProjectionSource,
        snapshot: CanonicalLibraryMetadataReadSnapshot
    ) {
        self.source = source
        self.snapshot = snapshot
        self.metadataOnly = true
        self.coversFolderMetadata = true
        self.coversStudyItemMetadata = true
        self.coversStandaloneNoteMetadata = true
        self.excludesAudioState = true
        self.excludesGeneratedArtifactContent = true
        self.excludesStandaloneNoteContent = true
    }

    nonisolated var diagnosticsSummary: String {
        [
            "source=\(source.rawValue)",
            "metadataOnly=\(metadataOnly)",
            "folders=\(snapshot.folders.count)",
            "items=\(snapshot.studyItems.count)",
            "notes=\(snapshot.standaloneNotes.count)",
            "excludeAudio=\(excludesAudioState)",
            "excludeGeneratedContent=\(excludesGeneratedArtifactContent)",
            "excludeNoteContent=\(excludesStandaloneNoteContent)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalLibraryMetadataReadCutoverGateState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case allowed
    case blockedByWriteSideEvidence
    case blockedByDivergence
    case blockedByUnsupportedObject
    case blockedByPathLeakRisk
    case blockedByFallbackMissing
    case blockedByOtherActiveDomain
    case blockedByDefaultConfig
    case blocked
}

nonisolated enum CanonicalLibraryMetadataReadCutoverBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case activePilotNotLibraryMetadata
    case multipleActivePilots
    case writeSideCanaryEvidenceMissing
    case writeSideRollbackFatal
    case readSideDivergence
    case unsupportedObject
    case pathLeakRisk
    case legacyFallbackMissing
    case canonicalProjectionIncomplete
    case objectIDUnstable
    case resourceMoveRisk
    case contentWriteRisk
    case tombstoneDeleteCandidate
    case unresolvedConflict
    case explicitInternalTestConfigMissing
    case globalUICutoverRequested
    case runtimeSwitchEnabled
    case otherDomainNotStaticOnly
}

nonisolated struct CanonicalLibraryMetadataReadCutoverGateContext: Codable, Equatable, Sendable {
    var configuration: CanonicalLibraryMetadataReadSourceConfiguration
    var writeSideEvidence: CanonicalLibraryMetadataWriteSideEvidenceLinkage
    var legacyFallbackAvailable: Bool
    var canonicalProjectionComplete: Bool
    var objectIDStable: Bool
    var noResourceMove: Bool
    var noContentWrite: Bool
    var noTombstoneDeleteCandidate: Bool
    var unresolvedConflictCount: Int

    nonisolated init(
        configuration: CanonicalLibraryMetadataReadSourceConfiguration,
        writeSideEvidence: CanonicalLibraryMetadataWriteSideEvidenceLinkage,
        legacyFallbackAvailable: Bool = true,
        canonicalProjectionComplete: Bool = true,
        objectIDStable: Bool = true,
        noResourceMove: Bool = true,
        noContentWrite: Bool = true,
        noTombstoneDeleteCandidate: Bool = true,
        unresolvedConflictCount: Int = 0
    ) {
        self.configuration = configuration
        self.writeSideEvidence = writeSideEvidence
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.canonicalProjectionComplete = canonicalProjectionComplete
        self.objectIDStable = objectIDStable
        self.noResourceMove = noResourceMove
        self.noContentWrite = noContentWrite
        self.noTombstoneDeleteCandidate = noTombstoneDeleteCandidate
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
    }
}

nonisolated struct CanonicalLibraryMetadataReadCutoverGateResult: Codable, Equatable, Sendable {
    var state: CanonicalLibraryMetadataReadCutoverGateState
    var blockers: [CanonicalLibraryMetadataReadCutoverBlocker]
    var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic]
    var diagnosticsSummary: String

    nonisolated var allowed: Bool {
        state == .allowed && blockers.isEmpty
    }
}

nonisolated enum CanonicalLibraryMetadataReadCutoverGate {
    nonisolated static func evaluate(
        context: CanonicalLibraryMetadataReadCutoverGateContext,
        diffReport: CanonicalLibraryMetadataReadSideDiffReport,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813(),
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String?
    ) -> CanonicalLibraryMetadataReadCutoverGateResult {
        var blockers: [CanonicalLibraryMetadataReadCutoverBlocker] = []
        let matrixReport = matrix.validate()
        if matrixReport.activePilotDomain != .libraryMetadata {
            blockers.append(.activePilotNotLibraryMetadata)
        }
        if matrixReport.blockers.contains(.multipleActivePilots) {
            blockers.append(.multipleActivePilots)
        }
        if matrixReport.blockers.contains(.nonPilotDomainNotStaticOnly) {
            blockers.append(.otherDomainNotStaticOnly)
        }
        if !context.writeSideEvidence.hasCleanStagedCanaryEvidence {
            blockers.append(.writeSideCanaryEvidenceMissing)
        }
        if context.writeSideEvidence.rollbackFailureCount > 0 {
            blockers.append(.writeSideRollbackFatal)
        }
        if diffReport.divergenceCount > 0 || context.writeSideEvidence.readSideDivergenceCount > 0 {
            blockers.append(.readSideDivergence)
        }
        if diffReport.unsupportedObjectCount > 0 {
            blockers.append(.unsupportedObject)
        }
        if diffReport.pathLeakRiskCount > 0 {
            blockers.append(.pathLeakRisk)
        }
        if !context.legacyFallbackAvailable {
            blockers.append(.legacyFallbackMissing)
        }
        if !context.canonicalProjectionComplete {
            blockers.append(.canonicalProjectionIncomplete)
        }
        if !context.objectIDStable || diffReport.divergences.contains(where: { $0.kind == .objectIDMismatch }) {
            blockers.append(.objectIDUnstable)
        }
        if !context.noResourceMove {
            blockers.append(.resourceMoveRisk)
        }
        if !context.noContentWrite {
            blockers.append(.contentWriteRisk)
        }
        if !context.noTombstoneDeleteCandidate {
            blockers.append(.tombstoneDeleteCandidate)
        }
        if context.unresolvedConflictCount > 0 || context.writeSideEvidence.unresolvedConflictCount > 0 {
            blockers.append(.unresolvedConflict)
        }
        if !context.configuration.explicitInternalTestConfiguration {
            blockers.append(.explicitInternalTestConfigMissing)
        }
        if context.configuration.uiCutoverGlobal {
            blockers.append(.globalUICutoverRequested)
        }
        if context.configuration.runtimeSwitchEnabled || matrixReport.blockers.contains(.runtimeSwitchEnabled) {
            blockers.append(.runtimeSwitchEnabled)
        }

        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let state = state(for: uniqueBlockers)
        let diagnosticsSummary = [
            "state=\(state.rawValue)",
            "domain=libraryMetadata",
            "divergences=\(diffReport.divergenceCount)",
            "unsupported=\(diffReport.unsupportedObjectCount)",
            "pathLeakRisk=\(diffReport.pathLeakRiskCount)",
            "fallback=\(context.legacyFallbackAvailable)",
            "explicitInternal=\(context.configuration.explicitInternalTestConfiguration)",
            "runtimeSwitch=\(context.configuration.runtimeSwitchEnabled)",
            "uiGlobal=\(context.configuration.uiCutoverGlobal)",
            "blockers=\(uniqueBlockers.map(\.rawValue).joined(separator: "+"))"
        ].joined(separator: ",")
        let diagnostics = [
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: .canonicalLibraryMetadataReadCutoverGateEvaluated,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: state.rawValue,
                reason: diagnosticsSummary
            ),
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: uniqueBlockers.isEmpty ? .canonicalLibraryMetadataReadCutoverGateAllowed : .canonicalLibraryMetadataReadCutoverGateBlocked,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: uniqueBlockers.isEmpty ? "allowed" : "blocked",
                reason: uniqueBlockers.map(\.rawValue).joined(separator: "+")
            )
        ]
        return CanonicalLibraryMetadataReadCutoverGateResult(
            state: state,
            blockers: uniqueBlockers,
            diagnostics: diagnostics,
            diagnosticsSummary: diagnosticsSummary
        )
    }

    private nonisolated static func state(
        for blockers: [CanonicalLibraryMetadataReadCutoverBlocker]
    ) -> CanonicalLibraryMetadataReadCutoverGateState {
        if blockers.isEmpty {
            return .allowed
        }
        if blockers.contains(.explicitInternalTestConfigMissing) || blockers.contains(.globalUICutoverRequested) || blockers.contains(.runtimeSwitchEnabled) {
            return .blockedByDefaultConfig
        }
        if blockers.contains(.activePilotNotLibraryMetadata) || blockers.contains(.multipleActivePilots) || blockers.contains(.otherDomainNotStaticOnly) {
            return .blockedByOtherActiveDomain
        }
        if blockers.contains(.writeSideCanaryEvidenceMissing) || blockers.contains(.writeSideRollbackFatal) {
            return .blockedByWriteSideEvidence
        }
        if blockers.contains(.pathLeakRisk) {
            return .blockedByPathLeakRisk
        }
        if blockers.contains(.unsupportedObject) {
            return .blockedByUnsupportedObject
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

nonisolated struct CanonicalLibraryMetadataReadSourceResult: Codable, Equatable, Sendable {
    var mode: CanonicalLibraryMetadataReadSourceMode
    var returnedSource: CanonicalLibraryMetadataReadProjectionSource
    var readSource: CanonicalLibraryMetadataReadSource
    var legacySnapshot: CanonicalLibraryMetadataReadSnapshot
    var canonicalCandidate: CanonicalLibraryMetadataReadSnapshot?
    var diffReport: CanonicalLibraryMetadataReadSideDiffReport?
    var gateResult: CanonicalLibraryMetadataReadCutoverGateResult?
    var fallback: CanonicalLibraryMetadataReadFallback
    var fallbackCount: Int
    var canonicalReadServed: Bool
    var legacyReadReturned: Bool
    var canonicalCandidateBuilt: Bool
    var fatalForFutureStage: Bool
    var storeMutated: Bool
    var syncOrUploadTriggered: Bool
    var resourceMoved: Bool
    var contentWritten: Bool
    var uiMutated: Bool
    var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic]
    var diagnosticsSummary: String
}

nonisolated struct CanonicalLibraryMetadataReadSourceProvider: Sendable {
    var configuration: CanonicalLibraryMetadataReadSourceConfiguration
    var matrix: CanonicalMigrationDomainMatrix

    nonisolated init(
        configuration: CanonicalLibraryMetadataReadSourceConfiguration = .legacy,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813()
    ) {
        self.configuration = configuration
        self.matrix = matrix
    }

    nonisolated func read(
        legacySnapshot: CanonicalLibraryMetadataReadSnapshot,
        canonicalSnapshot: CanonicalLibraryMetadataReadSnapshot?,
        writeSideEvidence: CanonicalLibraryMetadataWriteSideEvidenceLinkage,
        legacyFallbackAvailable: Bool = true,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String? = nil,
        canonicalReadFailureReason: String? = nil,
        unresolvedConflictCount: Int = 0
    ) -> CanonicalLibraryMetadataReadSourceResult {
        let canonicalSnapshot = canonicalSnapshot
        let canonicalProjectionComplete = canonicalSnapshot.map { snapshot in
            !snapshot.failures.contains { failure in
                failure.kind == .snapshotMissing || failure.kind == .missingMetadata
            }
        } ?? false
        let diffReport = canonicalSnapshot.map {
            CanonicalLibraryMetadataReadSideParallelDiff.compare(legacy: legacySnapshot, canonical: $0)
        }
        let evaluatedDiagnostic = diagnostic(
            .canonicalLibraryMetadataReadSourceEvaluated,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: configuration.mode.rawValue,
            reason: "domain=libraryMetadata"
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
                diagnostics: [evaluatedDiagnostic, legacyReturnedDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "defaultLegacy")],
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
                diagnostics: [evaluatedDiagnostic, guardedBlockedDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "blockedMode"), fallbackDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "blockedMode")],
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
                let diagnostics = [
                    evaluatedDiagnostic,
                    guardedBlockedDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "canonicalProjectionMissing"),
                    fallbackDiagnostic(syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, reason: "canonicalProjectionMissing")
                ]
                return makeResult(
                    returnedSnapshot: legacySnapshot,
                    legacySnapshot: legacySnapshot,
                    canonicalSnapshot: canonicalSnapshot,
                    diffReport: nil,
                    gateResult: nil,
                    fallback: .canonicalProjectionMissing,
                    diagnostics: diagnostics,
                    fatalForFutureStage: true
                )
            }
            let gate = CanonicalLibraryMetadataReadCutoverGate.evaluate(
                context: CanonicalLibraryMetadataReadCutoverGateContext(
                    configuration: configuration,
                    writeSideEvidence: writeSideEvidence,
                    legacyFallbackAvailable: legacyFallbackAvailable,
                    canonicalProjectionComplete: canonicalProjectionComplete,
                    objectIDStable: !diffReport.divergences.contains { $0.kind == .objectIDMismatch },
                    noResourceMove: true,
                    noContentWrite: true,
                    noTombstoneDeleteCandidate: true,
                    unresolvedConflictCount: unresolvedConflictCount
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
                    fatalForFutureStage: diffReport.divergenceCount > 0 || diffReport.pathLeakRiskCount > 0
                )
            }
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataGuardedCanonicalReadAllowed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "allowed",
                    reason: "explicitInternalTestConfig"
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataGuardedCanonicalReadServed,
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
        returnedSnapshot: CanonicalLibraryMetadataReadSnapshot,
        legacySnapshot: CanonicalLibraryMetadataReadSnapshot,
        canonicalSnapshot: CanonicalLibraryMetadataReadSnapshot?,
        diffReport: CanonicalLibraryMetadataReadSideDiffReport?,
        gateResult: CanonicalLibraryMetadataReadCutoverGateResult?,
        fallback: CanonicalLibraryMetadataReadFallback,
        diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic],
        fatalForFutureStage: Bool
    ) -> CanonicalLibraryMetadataReadSourceResult {
        let returnedSource = returnedSnapshot.source
        let readSource = CanonicalLibraryMetadataReadSource(source: returnedSource, snapshot: returnedSnapshot)
        let limitedDiagnostics = configuration.recordDiagnostics
            ? Array(diagnostics.prefix(configuration.maxDiagnosticsEvents))
            : []
        return CanonicalLibraryMetadataReadSourceResult(
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
            resourceMoved: false,
            contentWritten: false,
            uiMutated: false,
            diagnostics: limitedDiagnostics,
            diagnosticsSummary: [
                "mode=\(configuration.mode.rawValue)",
                "returned=\(returnedSource.rawValue)",
                "fallback=\(fallback.rawValue)",
                "canonicalServed=\(returnedSource == .canonical && fallback == .none)",
                "folders=\(returnedSnapshot.folders.count)",
                "items=\(returnedSnapshot.studyItems.count)",
                "notes=\(returnedSnapshot.standaloneNotes.count)",
                "storeMutated=false",
                "syncOrUploadTriggered=false",
                "resourceMoved=false",
                "contentWritten=false",
                "uiMutated=false"
            ].joined(separator: ",")
        )
    }

    private nonisolated func diagnostic(
        _ kind: CanonicalLibraryMetadataCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        result: String,
        reason: String
    ) -> CanonicalLibraryMetadataCutoverDiagnostic {
        CanonicalLibraryMetadataCutoverDiagnostic(
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
    ) -> CanonicalLibraryMetadataCutoverDiagnostic {
        diagnostic(.canonicalLibraryMetadataReadSourceLegacyReturned, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "legacy", reason: reason)
    }

    private nonisolated func canonicalCandidateDiagnostic(
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        reason: String
    ) -> CanonicalLibraryMetadataCutoverDiagnostic {
        diagnostic(.canonicalLibraryMetadataReadSourceCanonicalCandidateBuilt, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "candidate", reason: reason)
    }

    private nonisolated func guardedBlockedDiagnostic(
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        reason: String
    ) -> CanonicalLibraryMetadataCutoverDiagnostic {
        diagnostic(.canonicalLibraryMetadataGuardedCanonicalReadBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked", reason: reason)
    }

    private nonisolated func fallbackDiagnostic(
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        reason: String
    ) -> CanonicalLibraryMetadataCutoverDiagnostic {
        diagnostic(.canonicalLibraryMetadataGuardedCanonicalReadFallback, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "legacy", reason: reason)
    }

    private nonisolated func outputDiagnostic(
        diffReport: CanonicalLibraryMetadataReadSideDiffReport?,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> CanonicalLibraryMetadataCutoverDiagnostic {
        diagnostic(
            diffReport?.equivalent == true ? .canonicalLibraryMetadataReadOutputEquivalent : .canonicalLibraryMetadataReadOutputDivergent,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: diffReport?.equivalent == true ? "equivalent" : "divergent",
            reason: diffReport?.diagnosticsSummary ?? "canonicalCandidateMissing"
        )
    }

    private nonisolated func fallback(for gate: CanonicalLibraryMetadataReadCutoverGateResult) -> CanonicalLibraryMetadataReadFallback {
        if gate.blockers.contains(.pathLeakRisk) {
            return .pathLeakRisk
        }
        if gate.blockers.contains(.unsupportedObject) {
            return .unsupportedObject
        }
        if gate.blockers.contains(.readSideDivergence) {
            return .divergenceDetected
        }
        if gate.blockers.contains(.canonicalProjectionIncomplete) {
            return .canonicalProjectionMissing
        }
        return .gateBlocked
    }

    private nonisolated func fallbackReason(for gate: CanonicalLibraryMetadataReadCutoverGateResult) -> String {
        let reason = gate.blockers.map(\.rawValue).joined(separator: "+")
        return reason.isEmpty ? "gateBlocked" : reason
    }
}

nonisolated struct CanonicalLibraryMetadataRetirementCandidateEvidence: Codable, Equatable, Sendable {
    var writeSideCanarySuccessEvidence: Bool
    var guardedReadSourceEvidence: Bool
    var observationWindowComplete: Bool
    var legacyFallbackReady: Bool
    var divergenceZero: Bool
    var unsupportedObjectCount: Int
    var unresolvedConflictCount: Int
    var rollbackFatalCount: Int
    var readSourceStable: Bool
    var otherDomainsUnaffected: Bool

    nonisolated init(
        writeSideCanarySuccessEvidence: Bool,
        guardedReadSourceEvidence: Bool,
        observationWindowComplete: Bool,
        legacyFallbackReady: Bool,
        divergenceZero: Bool,
        unsupportedObjectCount: Int = 0,
        unresolvedConflictCount: Int = 0,
        rollbackFatalCount: Int = 0,
        readSourceStable: Bool = true,
        otherDomainsUnaffected: Bool = true
    ) {
        self.writeSideCanarySuccessEvidence = writeSideCanarySuccessEvidence
        self.guardedReadSourceEvidence = guardedReadSourceEvidence
        self.observationWindowComplete = observationWindowComplete
        self.legacyFallbackReady = legacyFallbackReady
        self.divergenceZero = divergenceZero
        self.unsupportedObjectCount = max(0, unsupportedObjectCount)
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.rollbackFatalCount = max(0, rollbackFatalCount)
        self.readSourceStable = readSourceStable
        self.otherDomainsUnaffected = otherDomainsUnaffected
    }
}

nonisolated enum CanonicalLibraryMetadataRetirementReadiness: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case notCandidate
    case ready
    case blocked
}

nonisolated enum CanonicalLibraryMetadataRetirementBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingWriteSideDomainCutoverEvidence
    case missingReadSideCutoverEvidence
    case observationWindowIncomplete
    case fallbackMissing
    case divergencePresent
    case unresolvedConflict
    case unsupportedObject
    case missingWriteSideCanarySuccessEvidence
    case missingGuardedReadSourceEvidence
    case rollbackFatal
    case readSourceUnstable
    case otherDomainsAffected
    case manualAuditRequired
    case unsafeSideEffect
    case pathLeakRisk
    case runtimeSwitchEnabled
    case defaultReadOrWriteCutoverEnabled
    case legacyDeleted
    case legacyDisabled
    case retirementExecutionAttempted
    case resourceMoveAttempted
    case contentWriteAttempted
    case tombstoneDeleteAttempted
}

nonisolated struct CanonicalLibraryMetadataRetirementCandidate: Codable, Equatable, Sendable {
    var isCandidate: Bool
    var readiness: CanonicalLibraryMetadataRetirementReadiness
    var blockers: [CanonicalLibraryMetadataRetirementBlocker]
}

nonisolated struct CanonicalLibraryMetadataRetirementReport: Codable, Equatable, Sendable {
    var candidate: CanonicalLibraryMetadataRetirementCandidate
    var legacyDeleted: Bool
    var legacyDisabled: Bool
    var reportOnly: Bool
    var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic]
    var diagnosticsSummary: String
}

nonisolated enum CanonicalLibraryMetadataRetirementCandidateEvaluator {
    nonisolated static func evaluate(
        writeSideEvidence: CanonicalLibraryMetadataWriteSideEvidenceLinkage,
        readSideCutoverEvidenceAvailable: Bool,
        observationWindowComplete: Bool,
        fallbackAvailable: Bool,
        diffReport: CanonicalLibraryMetadataReadSideDiffReport,
        unresolvedConflictCount: Int = 0,
        trigger: CanonicalSyncPlanTrigger = .periodic,
        nodeRole: CanonicalProductionExecutionDomainRole = .testHarness,
        syncRunID: String? = nil
    ) -> CanonicalLibraryMetadataRetirementReport {
        var blockers: [CanonicalLibraryMetadataRetirementBlocker] = []
        if !writeSideEvidence.writeSideDomainCutoverComplete {
            blockers.append(.missingWriteSideDomainCutoverEvidence)
        }
        if !readSideCutoverEvidenceAvailable {
            blockers.append(.missingReadSideCutoverEvidence)
        }
        if !observationWindowComplete {
            blockers.append(.observationWindowIncomplete)
        }
        if !fallbackAvailable {
            blockers.append(.fallbackMissing)
        }
        if diffReport.divergenceCount > 0 {
            blockers.append(.divergencePresent)
        }
        if unresolvedConflictCount > 0 || writeSideEvidence.unresolvedConflictCount > 0 {
            blockers.append(.unresolvedConflict)
        }
        if diffReport.unsupportedObjectCount > 0 {
            blockers.append(.unsupportedObject)
        }
        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let candidate = CanonicalLibraryMetadataRetirementCandidate(
            isCandidate: uniqueBlockers.isEmpty,
            readiness: uniqueBlockers.isEmpty ? .ready : .blocked,
            blockers: uniqueBlockers
        )
        let evaluated = CanonicalLibraryMetadataCutoverDiagnostic(
            kind: .canonicalLibraryMetadataRetirementCandidateEvaluated,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: candidate.readiness.rawValue,
            reason: "reportOnly=true"
        )
        let outcome = CanonicalLibraryMetadataCutoverDiagnostic(
            kind: candidate.isCandidate ? .canonicalLibraryMetadataRetirementCandidateReady : .canonicalLibraryMetadataRetirementCandidateBlocked,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: candidate.isCandidate ? "ready" : "blocked",
            reason: uniqueBlockers.map(\.rawValue).joined(separator: "+")
        )
        return CanonicalLibraryMetadataRetirementReport(
            candidate: candidate,
            legacyDeleted: false,
            legacyDisabled: false,
            reportOnly: true,
            diagnostics: [evaluated, outcome],
            diagnosticsSummary: "candidate=\(candidate.isCandidate),readiness=\(candidate.readiness.rawValue),blockers=\(uniqueBlockers.map(\.rawValue).joined(separator: "+")),legacyDeleted=false,legacyDisabled=false,reportOnly=true"
        )
    }

    nonisolated static func updateAfterGuardedRead(
        evidence: CanonicalLibraryMetadataRetirementCandidateEvidence,
        trigger: CanonicalSyncPlanTrigger = .periodic,
        nodeRole: CanonicalProductionExecutionDomainRole = .testHarness,
        syncRunID: String? = nil
    ) -> CanonicalLibraryMetadataRetirementReport {
        var blockers: [CanonicalLibraryMetadataRetirementBlocker] = []
        if !evidence.writeSideCanarySuccessEvidence {
            blockers.append(.missingWriteSideCanarySuccessEvidence)
        }
        if !evidence.guardedReadSourceEvidence {
            blockers.append(.missingGuardedReadSourceEvidence)
        }
        if !evidence.observationWindowComplete {
            blockers.append(.observationWindowIncomplete)
        }
        if !evidence.legacyFallbackReady {
            blockers.append(.fallbackMissing)
        }
        if !evidence.divergenceZero {
            blockers.append(.divergencePresent)
        }
        if evidence.unsupportedObjectCount > 0 {
            blockers.append(.unsupportedObject)
        }
        if evidence.unresolvedConflictCount > 0 {
            blockers.append(.unresolvedConflict)
        }
        if evidence.rollbackFatalCount > 0 {
            blockers.append(.rollbackFatal)
        }
        if !evidence.readSourceStable {
            blockers.append(.readSourceUnstable)
        }
        if !evidence.otherDomainsUnaffected {
            blockers.append(.otherDomainsAffected)
        }
        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let candidate = CanonicalLibraryMetadataRetirementCandidate(
            isCandidate: uniqueBlockers.isEmpty,
            readiness: uniqueBlockers.isEmpty ? .ready : .blocked,
            blockers: uniqueBlockers
        )
        let updated = CanonicalLibraryMetadataCutoverDiagnostic(
            kind: .canonicalLibraryMetadataRetirementCandidateUpdated,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: candidate.readiness.rawValue,
            reason: "reportOnly=true"
        )
        let outcome = CanonicalLibraryMetadataCutoverDiagnostic(
            kind: uniqueBlockers.isEmpty ? .canonicalLibraryMetadataRetirementCandidateReady : .canonicalLibraryMetadataRetirementStillBlocked,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: uniqueBlockers.isEmpty ? "candidate" : "blocked",
            reason: uniqueBlockers.map(\.rawValue).joined(separator: "+")
        )
        return CanonicalLibraryMetadataRetirementReport(
            candidate: candidate,
            legacyDeleted: false,
            legacyDisabled: false,
            reportOnly: true,
            diagnostics: [updated, outcome],
            diagnosticsSummary: "candidate=\(candidate.isCandidate),readiness=\(candidate.readiness.rawValue),blockers=\(uniqueBlockers.map(\.rawValue).joined(separator: "+")),legacyDeleted=false,legacyDisabled=false,reportOnly=true"
        )
    }
}
