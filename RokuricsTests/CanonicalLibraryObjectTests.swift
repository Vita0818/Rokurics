//
//  CanonicalLibraryObjectTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import Rokurics

@MainActor
struct CanonicalLibraryObjectTests {
    @Test func folderAndStudyItemMetadataHashesUseBusinessFieldsOnly() throws {
        let baseFolder = folderObject(name: " Math ", parentID: "folder:root", color: "blue")
        let renamedFolder = folderObject(name: "Physics", parentID: "folder:root", color: "blue")
        let movedFolder = folderObject(name: "Math", parentID: "folder:science", color: "blue")
        let recoloredFolder = folderObject(name: "Math", parentID: "folder:root", color: "green")
        let stableItemA = studyItemObject(tags: [" Beta ", "alpha", "ALPHA"], resources: ["notes/item.md", "/private/audio.m4a"])
        let stableItemB = studyItemObject(tags: ["alpha", "beta"], resources: ["notes/item.md"])

        #expect(baseFolder.metadata.name == "Math")
        #expect(!sameHash(baseFolder.metadataHash, renamedFolder.metadataHash))
        #expect(!sameHash(baseFolder.metadataHash, movedFolder.metadataHash))
        #expect(!sameHash(baseFolder.metadataHash, recoloredFolder.metadataHash))
        #expect(stableItemA.metadata.tags == ["alpha", "beta"])
        #expect(stableItemA.metadata.logicalResourceTokens == ["notes/item.md"])
        #expect(sameHash(stableItemA.metadataHash, stableItemB.metadataHash))
    }

    @Test func standaloneNoteObjectEncodesDecodesAndKeepsReadOnlyCanonicalShape() throws {
        let item = studyItemObject(kind: .standaloneNote, title: " Note ")
        let object = CanonicalLibraryObject(
            objectID: item.itemID,
            kind: .standaloneNote,
            studyItem: item,
            standaloneNote: CanonicalStandaloneNoteObject(studyItem: item)
        )
        let decoded = try JSONDecoder().decode(CanonicalLibraryObject.self, from: JSONEncoder().encode(object))

        #expect(decoded.kind == .standaloneNote)
        #expect(decoded.standaloneNote?.metadataHash == item.metadataHash)
        #expect(decoded.metadataHash == item.metadataHash)
    }

    @Test func manifestDecodesOldPayloadAndHashesNewLibraryObjectsDeterministically() throws {
        let oldPayload = """
        {
          "schemaVersion": 1,
          "node": {"nodeID": "old-iphone", "platform": "iPhone", "capabilities": []},
          "generatedAt": {"date": 0},
          "objects": []
        }
        """
        let oldManifest = try JSONDecoder().decode(CanonicalManifest.self, from: Data(oldPayload.utf8))
        let folder = folderObject()
        let object = CanonicalLibraryObject(objectID: folder.folderID, kind: .folder, folder: folder)
        let first = manifest(libraryObjects: [object])
        let second = manifest(libraryObjects: [object])

        #expect(oldManifest.libraryObjects.isEmpty)
        #expect(oldManifest.libraryTombstones.isEmpty)
        #expect(first.hasValidManifestHash)
        #expect(sameHash(first.manifestHash, second.manifestHash))
        #expect(first.manifestCapabilities.contains(.canonicalLibraryObjectsV1))
    }

    @Test func iphoneLibraryAdapterProjectsFoldersStudyItemsStandaloneNotesAndTombstones() {
        let syncManifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-01",
            generatedAt: date(3_000),
            items: [legacyStudyItem()],
            folders: [legacyFolder()],
            tombstones: [
                StudyLibrarySyncTombstone(
                    id: "folder:folder-math",
                    entityKind: .folder,
                    entityID: "folder-math",
                    operation: .trash,
                    updatedAt: date(4_000),
                    modifiedByDeviceID: "iphone-01"
                )
            ]
        )
        let adapter = IPhoneCanonicalLibraryAdapter()
        let objects = adapter.makeLibraryObjects(from: syncManifest)
        let note = objects.first { $0.kind == .standaloneNote }
        let folder = objects.first { $0.kind == .folder }
        let tombstone = adapter.makeTombstones(from: syncManifest).first

        #expect(folder?.folder?.metadata.colorToken == "blue")
        #expect(note?.standaloneNote != nil)
        #expect(note?.studyItem?.metadata.logicalResourceTokens == ["notes/item-note/note.md"])
        #expect(note?.studyItem?.metadata.logicalResourceTokens.contains { $0.hasPrefix("/") } == false)
        #expect(tombstone?.objectKind == .folder)
        #expect(tombstone?.policies.contains(.noPhysicalDelete) == true)
    }

    private func folderObject(
        name: String = "Math",
        parentID: String? = nil,
        color: String? = "blue",
        modifiedAt: TimeInterval = 2_000,
        isDeleted: Bool = false,
        deletedAt: TimeInterval? = nil
    ) -> CanonicalFolderObject {
        let folderID = CanonicalLibraryObjectID("folder:math")
        let parent = parentID.map { CanonicalLibraryObjectID($0) }
        let metadata = CanonicalFolderMetadata(
            folderID: folderID,
            name: name,
            parentID: parent,
            hierarchyPath: CanonicalHierarchyPath(["course", "math"]),
            hierarchyLevel: "subject",
            colorToken: color,
            isDeleted: isDeleted,
            deletedAt: deletedAt.map(ts),
            businessModifiedAt: ts(modifiedAt)
        )
        return CanonicalFolderObject(metadata: metadata)
    }

    private func studyItemObject(
        kind: CanonicalStudyItemKind = .standaloneNote,
        title: String = "Note",
        tags: [String] = ["alpha"],
        resources: [String] = ["notes/item.md"],
        modifiedAt: TimeInterval = 2_000
    ) -> CanonicalStudyItemObject {
        let itemID = CanonicalLibraryObjectID("item:note")
        let folderID = CanonicalLibraryObjectID("folder:math")
        let parentReference = CanonicalParentReference(parentID: folderID, relation: "folder")
        let metadata = CanonicalStudyItemMetadata(
            itemID: itemID,
            itemKind: kind,
            title: title,
            filingPath: CanonicalHierarchyPath(["course", "math"]),
            folderIDs: [folderID],
            parentReferences: [parentReference],
            tags: tags,
            logicalResourceTokens: resources,
            businessModifiedAt: ts(modifiedAt)
        )
        return CanonicalStudyItemObject(metadata: metadata)
    }

    private func manifest(libraryObjects: [CanonicalLibraryObject]) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(
                nodeID: "iphone-01",
                platform: "iPhone",
                capabilities: [.recordingMetadata, .audioArtifact, .canonicalLibraryObjectsV1]
            ),
            generatedAt: date(3_000),
            objects: [],
            libraryObjects: libraryObjects,
            manifestCapabilities: [.canonicalLibraryObjectsV1]
        )
    }

    private func legacyFolder() -> StudyFolderMetadata {
        StudyFolderMetadata(
            folderID: "folder-math",
            name: "Math",
            level: .subject,
            path: StudyFilingPath(type: "course", subject: "math"),
            createdAt: date(1_000),
            updatedAt: date(2_000),
            colorToken: .blue
        )
    }

    private func legacyStudyItem() -> StudyItemMetadata {
        StudyItemMetadata(
            itemID: "item-note",
            kind: .standaloneNote,
            title: "Note",
            createdAt: date(1_000),
            updatedAt: date(2_000),
            filing: StudyFilingPath(type: "course", subject: "math"),
            tags: [StudyTag(namespace: "custom", value: "Beta"), StudyTag(namespace: "custom", value: "alpha")],
            folderIDs: ["folder-math"],
            audioRelativePath: "/private/audio.m4a",
            noteRelativePath: "notes/item-note/note.md"
        )
    }

    private func ts(_ value: TimeInterval) -> CanonicalTimestamp {
        CanonicalTimestamp(date(value))
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }

    private func sameHash(_ lhs: CanonicalHash, _ rhs: CanonicalHash) -> Bool {
        lhs.algorithm == rhs.algorithm && lhs.value == rhs.value
    }
}
