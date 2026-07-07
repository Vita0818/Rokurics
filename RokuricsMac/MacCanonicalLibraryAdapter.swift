//
//  MacCanonicalLibraryAdapter.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated struct MacCanonicalLibraryAdapter {
    func makeLibraryObjects(from manifest: StudyLibrarySyncManifest) -> [CanonicalLibraryObject] {
        let folders = manifest.folders.map(makeFolderObject)
        let studyItems = manifest.items.map(makeStudyItemObject)
        let folderObjects = folders.map { folder in
            CanonicalLibraryObject(
                objectID: folder.folderID,
                kind: .folder,
                folder: folder
            )
        }
        let itemObjects = studyItems.map { item in
            let kind: CanonicalObjectKind
            switch item.metadata.itemKind {
            case .recordingBundle:
                kind = .recordingAssociatedStudyItem
            case .standaloneNote:
                kind = .standaloneNote
            case .externalResource:
                kind = .standaloneStudyItem
            case .unknown:
                kind = .unknownUnsupported
            }
            return CanonicalLibraryObject(
                objectID: item.itemID,
                kind: kind,
                studyItem: item,
                standaloneNote: kind == .standaloneNote ? CanonicalStandaloneNoteObject(studyItem: item) : nil,
                recordingEnvelope: item.metadata.associatedRecordingID.map { recordingID in
                    CanonicalRecordingEnvelopeObject(
                        recordingID: recordingID,
                        studyItemID: item.itemID,
                        folderIDs: item.metadata.folderIDs,
                        filingPath: item.metadata.filingPath,
                        tags: item.metadata.tags
                    )
                },
                unsupportedReason: kind == .unknownUnsupported ? "unknownStudyItemKind" : nil
            )
        }
        return (folderObjects + itemObjects).sorted { $0.objectID.rawValue < $1.objectID.rawValue }
    }

    func makeTombstones(from manifest: StudyLibrarySyncManifest) -> [CanonicalLibraryTombstone] {
        manifest.tombstones.map { tombstone in
            CanonicalLibraryTombstone(
                objectID: CanonicalLibraryObjectID(tombstone.entityID),
                objectKind: tombstone.entityKind == .folder ? .folder : .standaloneStudyItem,
                deletedAt: CanonicalTimestamp(tombstone.updatedAt),
                sourceNodeID: tombstone.modifiedByDeviceID,
                reason: .softDelete
            )
        }
    }

    func makeUnsupportedObjects(from manifest: StudyLibrarySyncManifest) -> [CanonicalInventoryUnsupportedObject] {
        manifest.items.compactMap { item in
            guard canonicalStudyItemKind(item.kind) == .unknown else {
                return nil
            }
            return CanonicalInventoryUnsupportedObject(
                objectID: CanonicalLibraryObjectID(item.itemID),
                objectKind: .unknownUnsupported,
                reason: "unknownStudyItemKind"
            )
        }
    }

    private func makeFolderObject(_ folder: StudyFolderMetadata) -> CanonicalFolderObject {
        let folderID = CanonicalLibraryObjectID(folder.folderID)
        let parentID = folder.parentFolderID.map { CanonicalLibraryObjectID($0) }
        let deletedAt = folder.trashedAt.map { CanonicalTimestamp($0) }
        let metadata = CanonicalFolderMetadata(
            folderID: folderID,
            name: folder.name,
            parentID: parentID,
            hierarchyPath: CanonicalHierarchyPath(folder.pathComponents),
            hierarchyLevel: folder.level.rawValue,
            colorToken: folder.colorToken?.rawValue,
            orderingKey: nil,
            isDeleted: folder.isTrashed,
            deletedAt: deletedAt,
            businessModifiedAt: CanonicalTimestamp(folder.updatedAt)
        )
        return CanonicalFolderObject(metadata: metadata)
    }

    private func makeStudyItemObject(_ item: StudyItemMetadata) -> CanonicalStudyItemObject {
        let itemID = CanonicalLibraryObjectID(item.itemID)
        let folderIDs = item.folderIDs.map { CanonicalLibraryObjectID($0) }
        let parentReferences = folderIDs.map { CanonicalParentReference(parentID: $0, relation: "folder") }
        let tags = item.tags.map { "\($0.namespace):\($0.value)" }
        let deletedAt = item.trashedAt.map { CanonicalTimestamp($0) }
        let metadata = CanonicalStudyItemMetadata(
            itemID: itemID,
            itemKind: canonicalStudyItemKind(item.kind),
            title: item.title,
            filingPath: CanonicalHierarchyPath(filingComponents(item.filing)),
            folderIDs: folderIDs,
            parentReferences: parentReferences,
            tags: tags,
            logicalResourceTokens: resourceTokens(for: item),
            associatedRecordingID: item.recordingID,
            isDeleted: item.isTrashed,
            deletedAt: deletedAt,
            businessModifiedAt: CanonicalTimestamp(item.updatedAt)
        )
        return CanonicalStudyItemObject(metadata: metadata)
    }

    private func canonicalStudyItemKind(_ kind: StudyItemKind) -> CanonicalStudyItemKind {
        switch kind {
        case .recordingBundle:
            return .recordingBundle
        case .standaloneNote:
            return .standaloneNote
        }
    }

    private func filingComponents(_ filing: StudyFilingPath) -> [String] {
        [
            filing.type,
            filing.subject,
            filing.chapter,
            filing.topic
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    }

    private func resourceTokens(for item: StudyItemMetadata) -> [String] {
        [
            item.audioRelativePath,
            item.receiveRelativePath,
            item.transcriptRelativePath,
            item.transcriptMarkdownRelativePath,
            item.noteRelativePath
        ].compactMap(CanonicalProjectionContract.safeLogicalResourceToken)
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
