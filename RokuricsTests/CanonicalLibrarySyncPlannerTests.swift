//
//  CanonicalLibrarySyncPlannerTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalLibrarySyncPlannerTests {
    @Test func folderNoOpSendApplyConflictAndTombstoneArePlanned() {
        let same = CanonicalLibrarySyncPlanner().plan(
            local: manifest([folderObject(name: "Math")]),
            peer: manifest([folderObject(name: "Math")]),
            trigger: .periodic
        )
        let send = CanonicalLibrarySyncPlanner().plan(
            local: manifest([folderObject(name: "Local", modifiedAt: 3_000)]),
            peer: manifest([folderObject(name: "Peer", modifiedAt: 2_000)]),
            trigger: .periodic
        )
        let apply = CanonicalLibrarySyncPlanner().plan(
            local: manifest([folderObject(name: "Local", modifiedAt: 2_000)]),
            peer: manifest([folderObject(name: "Peer", modifiedAt: 3_000)]),
            trigger: .periodic
        )
        let conflict = CanonicalLibrarySyncPlanner().plan(
            local: manifest([folderObject(name: "Local", modifiedAt: 2_000)]),
            peer: manifest([folderObject(name: "Peer", modifiedAt: 2_000)]),
            trigger: .periodic
        )
        let tombstone = CanonicalLibrarySyncPlanner().plan(
            local: manifest([folderObject(name: "Math", modifiedAt: 2_000)]),
            peer: manifest([folderObject(name: "Math", modifiedAt: 3_000, isDeleted: true, deletedAt: 3_000)]),
            trigger: .periodic
        )

        #expect(same.actions.first?.kind == .folderMetadataNoOp)
        #expect(send.actions.first { $0.kind == .folderMetadataSend }?.source == .local)
        #expect(send.applyActions.first { $0.kind == .folderMetadataSend }?.bridgeHint == .legacyMetadataManifestSend)
        #expect(apply.actions.first { $0.kind == .folderMetadataApply }?.source == .peer)
        #expect(apply.applyActions.first { $0.kind == .folderMetadataApply }?.bridgeHint == .legacyMetadataManifestApply)
        #expect(conflict.conflicts.first?.kind == .folderMetadataConcurrentEdit)
        #expect(tombstone.actions.first { $0.kind == .folderTombstoneApply }?.source == .peer)
        #expect(tombstone.applyActions.first { $0.kind == .libraryTombstoneApply }?.bridgeHint == .legacyMetadataManifestApply)
        #expect(tombstone.tombstones.first?.policies.contains(.noPermanentDelete) == true)
    }

    @Test func studyItemActionsFallbackAndSuppressedTriggersStaySafe() {
        let send = CanonicalLibrarySyncPlanner().plan(
            local: manifest([studyObject(title: "Local", modifiedAt: 3_000)]),
            peer: manifest([studyObject(title: "Peer", modifiedAt: 2_000)]),
            trigger: .periodic
        )
        let tombstoneConflict = CanonicalLibrarySyncPlanner().plan(
            local: manifest([studyObject(title: "Restored", modifiedAt: 4_000)]),
            peer: manifest([studyObject(title: "Deleted", modifiedAt: 3_000, isDeleted: true, deletedAt: 3_000)]),
            trigger: .periodic
        )
        let viewRefresh = CanonicalLibrarySyncPlanner().plan(
            local: manifest([studyObject()]),
            peer: manifest([]),
            trigger: .viewRefresh
        )
        let retryDrainer = CanonicalLibrarySyncPlanner().plan(
            local: manifest([studyObject()]),
            peer: manifest([]),
            trigger: .retryDrainer
        )
        let missingCapability = CanonicalLibrarySyncPlanner().plan(
            local: manifest([studyObject()], includeCapability: false),
            peer: manifest([]),
            trigger: .periodic
        )

        #expect(send.actions.first { $0.kind == .studyItemMetadataSend }?.source == .local)
        #expect(send.applyActions.first { $0.kind == .studyItemMetadataSend }?.bridgeHint == .legacyMetadataManifestSend)
        #expect(tombstoneConflict.conflicts.first?.kind == .activeVsTombstone)
        #expect(tombstoneConflict.applyActions.contains { $0.kind == .conflictRecord })
        #expect(viewRefresh.actions.isEmpty)
        #expect(viewRefresh.diagnostics.contains { $0.detail == "viewRefreshProjectionOnly" })
        #expect(retryDrainer.actions.isEmpty)
        #expect(retryDrainer.diagnostics.contains { $0.detail == "retryDrainerNoFreshLibraryTransfer" })
        #expect(missingCapability.fallbackRequiredObjectIDs.map(\.rawValue) == ["item:note"])
    }

    private func manifest(
        _ objects: [CanonicalLibraryObject],
        includeCapability: Bool = true
    ) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(
                nodeID: "iphone-01",
                platform: "iPhone",
                capabilities: includeCapability ? [.canonicalLibraryObjectsV1] : []
            ),
            generatedAt: date(5_000),
            objects: [],
            libraryObjects: objects,
            manifestCapabilities: includeCapability ? [.canonicalLibraryObjectsV1] : []
        )
    }

    private func folderObject(
        name: String,
        modifiedAt: TimeInterval = 2_000,
        isDeleted: Bool = false,
        deletedAt: TimeInterval? = nil
    ) -> CanonicalLibraryObject {
        let folderID = CanonicalLibraryObjectID("folder:math")
        let metadata = CanonicalFolderMetadata(
            folderID: folderID,
            name: name,
            hierarchyPath: CanonicalHierarchyPath(["course", "math"]),
            hierarchyLevel: "subject",
            isDeleted: isDeleted,
            deletedAt: deletedAt.map(ts),
            businessModifiedAt: ts(modifiedAt)
        )
        let folder = CanonicalFolderObject(metadata: metadata)
        return CanonicalLibraryObject(objectID: folder.folderID, kind: .folder, folder: folder)
    }

    private func studyObject(
        title: String = "Note",
        modifiedAt: TimeInterval = 2_000,
        isDeleted: Bool = false,
        deletedAt: TimeInterval? = nil
    ) -> CanonicalLibraryObject {
        let itemID = CanonicalLibraryObjectID("item:note")
        let folderID = CanonicalLibraryObjectID("folder:math")
        let metadata = CanonicalStudyItemMetadata(
            itemID: itemID,
            itemKind: .standaloneNote,
            title: title,
            filingPath: CanonicalHierarchyPath(["course", "math"]),
            folderIDs: [folderID],
            isDeleted: isDeleted,
            deletedAt: deletedAt.map(ts),
            businessModifiedAt: ts(modifiedAt)
        )
        let item = CanonicalStudyItemObject(metadata: metadata)
        return CanonicalLibraryObject(
            objectID: item.itemID,
            kind: .standaloneNote,
            studyItem: item,
            standaloneNote: CanonicalStandaloneNoteObject(studyItem: item)
        )
    }

    private func ts(_ value: TimeInterval) -> CanonicalTimestamp {
        CanonicalTimestamp(date(value))
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}
