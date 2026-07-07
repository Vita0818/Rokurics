//
//  MacCanonicalRecordingAdapter.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/1.
//

import Foundation

nonisolated struct MacCanonicalRecordingAdapter {
    func makeObject(
        receiveRecord: RecordingReceiveRecord?,
        studyItem: StudyItemMetadata?,
        artifacts: [CanonicalArtifact],
        nodeID: String? = nil
    ) -> CanonicalRecordingObject {
        guard let objectID = Self.recordingID(receiveRecord: receiveRecord, studyItem: studyItem)
            ?? Self.recordingID(artifacts: artifacts) else {
            preconditionFailure("Canonical recording objects require a recordingID/objectID")
        }

        let title = Self.title(receiveRecord: receiveRecord, studyItem: studyItem)
        let artifactObservedAt = Self.artifactObservedAt(artifacts)
        let createdAt = studyItem?.createdAt ?? receiveRecord?.createdAt ?? receiveRecord?.receivedAt ?? artifactObservedAt ?? Date(timeIntervalSince1970: 0)
        let filing = Self.filing(receiveRecord: receiveRecord, studyItem: studyItem)
        let tags = Self.tags(receiveRecord: receiveRecord, studyItem: studyItem)
        let isDeleted = studyItem?.isTrashed ?? receiveRecord?.isDeleted ?? false
        let deletedAt = studyItem?.trashedAt ?? receiveRecord?.deletedAt
        let modifiedAt = Self.businessModifiedAt(
            receiveRecord: receiveRecord,
            studyItem: studyItem,
            createdAt: createdAt,
            isDeleted: isDeleted,
            deletedAt: deletedAt
        )
        let canonicalMetadata = CanonicalRecordingMetadata(
            objectID: objectID,
            title: title,
            createdAt: CanonicalTimestamp(createdAt),
            modifiedAt: CanonicalTimestamp(modifiedAt),
            duration: studyItem?.duration ?? receiveRecord?.duration,
            filing: filing,
            tags: tags,
            isDeleted: isDeleted,
            deletedAt: isDeleted ? deletedAt.map(CanonicalTimestamp.init) : nil
        )

        return CanonicalRecordingObject(
            objectID: objectID,
            nodeID: nodeID,
            metadata: canonicalMetadata,
            artifacts: artifacts,
            syncState: Self.syncState(isDeleted: isDeleted, studyItem: studyItem),
            transferState: Self.transferState(receiveRecord?.localNetworkTransferState),
            processingState: CanonicalProcessingState(
                transcription: Self.processingStage(studyItem?.transcriptionStatus ?? receiveRecord?.transcriptionStatus),
                note: Self.processingStage(studyItem?.noteStatus ?? receiveRecord?.noteStatus)
            ),
            receivedAt: receiveRecord.map { CanonicalTimestamp($0.receivedAt) },
            observedAt: receiveRecord.map { CanonicalTimestamp($0.receivedAt) }
        )
    }

    func makeObject(
        inboxItem: MacRecordingInboxItem?,
        studyItem: StudyItemMetadata?,
        artifacts: [CanonicalArtifact],
        nodeID: String? = nil
    ) -> CanonicalRecordingObject {
        guard let objectID = Self.recordingID(inboxItem: inboxItem, studyItem: studyItem)
            ?? Self.recordingID(artifacts: artifacts) else {
            preconditionFailure("Canonical recording objects require a recordingID/objectID")
        }

        let title = studyItem?.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? inboxItem?.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "未命名录音"
        let artifactObservedAt = Self.artifactObservedAt(artifacts)
        let createdAt = studyItem?.createdAt ?? inboxItem?.receivedAt ?? artifactObservedAt ?? Date(timeIntervalSince1970: 0)
        let filing: CanonicalRecordingMetadata.Filing?
        if let itemFiling = studyItem?.studyFiling, !itemFiling.isEmpty {
            filing = CanonicalRecordingMetadata.Filing(itemFiling)
        } else {
            filing = CanonicalRecordingMetadata.Filing(inboxItem?.studyFiling)
        }
        let tags = studyItem?.tags.map(\.value) ?? []
        let isDeleted = studyItem?.isTrashed ?? inboxItem?.isDeleted ?? false
        let deletedAt = studyItem?.trashedAt ?? inboxItem?.deletedAt
        let modifiedAt = Self.businessModifiedAt(
            inboxItem: inboxItem,
            studyItem: studyItem,
            createdAt: createdAt,
            isDeleted: isDeleted,
            deletedAt: deletedAt
        )
        let canonicalMetadata = CanonicalRecordingMetadata(
            objectID: objectID,
            title: title,
            createdAt: CanonicalTimestamp(createdAt),
            modifiedAt: CanonicalTimestamp(modifiedAt),
            duration: studyItem?.duration ?? inboxItem?.duration,
            filing: filing,
            tags: tags,
            isDeleted: isDeleted,
            deletedAt: isDeleted ? deletedAt.map(CanonicalTimestamp.init) : nil
        )

        return CanonicalRecordingObject(
            objectID: objectID,
            nodeID: nodeID,
            metadata: canonicalMetadata,
            artifacts: artifacts,
            syncState: Self.syncState(isDeleted: isDeleted, studyItem: studyItem),
            transferState: Self.transferState(inboxItem?.transferProgress?.state.rawValue),
            processingState: CanonicalProcessingState(
                transcription: Self.processingStage(studyItem?.transcriptionStatus ?? inboxItem?.transcriptionStatus),
                note: Self.processingStage(studyItem?.noteStatus ?? inboxItem?.noteStatus)
            ),
            receivedAt: inboxItem.map { CanonicalTimestamp($0.receivedAt) },
            observedAt: inboxItem.map { CanonicalTimestamp($0.receivedAt) }
        )
    }

    func makeManifest(
        inboxItems: [MacRecordingInboxItem],
        studyItems: [StudyItemMetadata],
        artifactFactsByRecordingID: [String: [CanonicalArtifact]],
        libraryObjects: [CanonicalLibraryObject] = [],
        libraryTombstones: [CanonicalLibraryTombstone] = [],
        manifestCapabilities: [CanonicalCapability] = [],
        node: CanonicalNode,
        generatedAt: Date = Date()
    ) -> CanonicalManifest {
        let inboxItemsByID = Dictionary(inboxItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let itemsByRecordingID = Dictionary(studyItems.compactMap { item -> (String, StudyItemMetadata)? in
            guard let recordingID = item.recordingID else {
                return nil
            }
            return (recordingID, item)
        }, uniquingKeysWith: { first, _ in first })
        let objects = makeObjects(
            inboxItemsByID: inboxItemsByID,
            itemsByRecordingID: itemsByRecordingID,
            artifactFactsByRecordingID: artifactFactsByRecordingID,
            nodeID: node.nodeID
        )

        return CanonicalManifest.make(
            node: node,
            generatedAt: generatedAt,
            objects: objects,
            libraryObjects: libraryObjects,
            libraryTombstones: libraryTombstones,
            manifestCapabilities: manifestCapabilities
        )
    }

    func makeObjects(
        inboxItems: [MacRecordingInboxItem],
        studyItems: [StudyItemMetadata],
        artifactFactsByRecordingID: [String: [CanonicalArtifact]],
        nodeID: String? = nil
    ) -> [CanonicalRecordingObject] {
        let inboxItemsByID = Dictionary(inboxItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let itemsByRecordingID = Dictionary(studyItems.compactMap { item -> (String, StudyItemMetadata)? in
            guard let recordingID = item.recordingID else {
                return nil
            }
            return (recordingID, item)
        }, uniquingKeysWith: { first, _ in first })
        return makeObjects(
            inboxItemsByID: inboxItemsByID,
            itemsByRecordingID: itemsByRecordingID,
            artifactFactsByRecordingID: artifactFactsByRecordingID,
            nodeID: nodeID
        )
    }

    private func makeObjects(
        inboxItemsByID: [String: MacRecordingInboxItem],
        itemsByRecordingID: [String: StudyItemMetadata],
        artifactFactsByRecordingID: [String: [CanonicalArtifact]],
        nodeID: String? = nil
    ) -> [CanonicalRecordingObject] {
        let objectIDs = Set(inboxItemsByID.keys)
            .union(itemsByRecordingID.keys)
            .union(artifactFactsByRecordingID.keys)
            .sorted()
        return objectIDs.map { objectID in
            makeObject(
                inboxItem: inboxItemsByID[objectID],
                studyItem: itemsByRecordingID[objectID],
                artifacts: artifactFactsByRecordingID[objectID] ?? [],
                nodeID: nodeID
            )
        }
    }

    func makeManifest(
        receiveRecords: [RecordingReceiveRecord],
        studyItems: [StudyItemMetadata],
        artifactFactsByRecordingID: [String: [CanonicalArtifact]],
        libraryObjects: [CanonicalLibraryObject] = [],
        libraryTombstones: [CanonicalLibraryTombstone] = [],
        manifestCapabilities: [CanonicalCapability] = [],
        node: CanonicalNode,
        generatedAt: Date = Date()
    ) -> CanonicalManifest {
        let recordsByID = Dictionary(receiveRecords.map { ($0.recordingID, $0) }, uniquingKeysWith: { first, _ in first })
        let itemsByRecordingID = Dictionary(studyItems.compactMap { item -> (String, StudyItemMetadata)? in
            guard let recordingID = item.recordingID else {
                return nil
            }
            return (recordingID, item)
        }, uniquingKeysWith: { first, _ in first })
        let objects = makeObjects(
            recordsByID: recordsByID,
            itemsByRecordingID: itemsByRecordingID,
            artifactFactsByRecordingID: artifactFactsByRecordingID,
            nodeID: node.nodeID
        )

        return CanonicalManifest.make(
            node: node,
            generatedAt: generatedAt,
            objects: objects,
            libraryObjects: libraryObjects,
            libraryTombstones: libraryTombstones,
            manifestCapabilities: manifestCapabilities
        )
    }

    func makeObjects(
        receiveRecords: [RecordingReceiveRecord],
        studyItems: [StudyItemMetadata],
        artifactFactsByRecordingID: [String: [CanonicalArtifact]],
        nodeID: String? = nil
    ) -> [CanonicalRecordingObject] {
        let recordsByID = Dictionary(receiveRecords.map { ($0.recordingID, $0) }, uniquingKeysWith: { first, _ in first })
        let itemsByRecordingID = Dictionary(studyItems.compactMap { item -> (String, StudyItemMetadata)? in
            guard let recordingID = item.recordingID else {
                return nil
            }
            return (recordingID, item)
        }, uniquingKeysWith: { first, _ in first })
        return makeObjects(
            recordsByID: recordsByID,
            itemsByRecordingID: itemsByRecordingID,
            artifactFactsByRecordingID: artifactFactsByRecordingID,
            nodeID: nodeID
        )
    }

    private func makeObjects(
        recordsByID: [String: RecordingReceiveRecord],
        itemsByRecordingID: [String: StudyItemMetadata],
        artifactFactsByRecordingID: [String: [CanonicalArtifact]],
        nodeID: String? = nil
    ) -> [CanonicalRecordingObject] {
        let objectIDs = Set(recordsByID.keys)
            .union(itemsByRecordingID.keys)
            .union(artifactFactsByRecordingID.keys)
            .sorted()
        return objectIDs.map { objectID in
            makeObject(
                receiveRecord: recordsByID[objectID],
                studyItem: itemsByRecordingID[objectID],
                artifacts: artifactFactsByRecordingID[objectID] ?? [],
                nodeID: nodeID
            )
        }
    }

    private static func recordingID(receiveRecord: RecordingReceiveRecord?, studyItem: StudyItemMetadata?) -> String? {
        (studyItem?.recordingID ?? receiveRecord?.recordingID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func recordingID(inboxItem: MacRecordingInboxItem?, studyItem: StudyItemMetadata?) -> String? {
        (studyItem?.recordingID ?? inboxItem?.id)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func recordingID(artifacts: [CanonicalArtifact]) -> String? {
        artifacts
            .map(\.objectID)
            .compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .sorted()
            .first
    }

    private static func artifactObservedAt(_ artifacts: [CanonicalArtifact]) -> Date? {
        artifacts
            .compactMap { $0.modifiedAt?.date ?? $0.observedAt?.date }
            .sorted()
            .first
    }

    private static func title(receiveRecord: RecordingReceiveRecord?, studyItem: StudyItemMetadata?) -> String {
        studyItem?.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? receiveRecord?.normalizedTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? receiveRecord?.originalTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "未命名录音"
    }

    private static func filing(
        receiveRecord: RecordingReceiveRecord?,
        studyItem: StudyItemMetadata?
    ) -> CanonicalRecordingMetadata.Filing? {
        if let itemFiling = studyItem?.studyFiling, !itemFiling.isEmpty {
            return CanonicalRecordingMetadata.Filing(itemFiling)
        }
        return CanonicalRecordingMetadata.Filing(receiveRecord?.studyFiling)
    }

    private static func tags(receiveRecord: RecordingReceiveRecord?, studyItem: StudyItemMetadata?) -> [String] {
        let itemTags = studyItem?.tags.map(\.value) ?? []
        return itemTags.isEmpty ? (receiveRecord?.tags ?? []) : itemTags
    }

    private static func businessModifiedAt(
        receiveRecord: RecordingReceiveRecord?,
        studyItem: StudyItemMetadata?,
        createdAt: Date,
        isDeleted: Bool,
        deletedAt: Date?
    ) -> Date {
        if isDeleted {
            return deletedAt ?? studyItem?.updatedAt ?? createdAt
        }
        guard let studyItem else {
            return receiveRecord?.createdAt ?? createdAt
        }
        if receiveRecord == nil || isSyncedMetadataOnly(studyItem) || hasBusinessOverride(studyItem: studyItem, receiveRecord: receiveRecord) {
            return studyItem.updatedAt
        }
        return receiveRecord?.createdAt ?? createdAt
    }

    private static func businessModifiedAt(
        inboxItem: MacRecordingInboxItem?,
        studyItem: StudyItemMetadata?,
        createdAt: Date,
        isDeleted: Bool,
        deletedAt: Date?
    ) -> Date {
        if isDeleted {
            return deletedAt ?? studyItem?.updatedAt ?? createdAt
        }
        guard let studyItem else {
            return createdAt
        }
        if inboxItem == nil || isSyncedMetadataOnly(studyItem) || hasBusinessOverride(studyItem: studyItem, inboxItem: inboxItem) {
            return studyItem.updatedAt
        }
        return createdAt
    }

    private static func isSyncedMetadataOnly(_ studyItem: StudyItemMetadata) -> Bool {
        studyItem.customProperties["syncedMetadataOnly"] == "true"
    }

    private static func hasBusinessOverride(
        studyItem: StudyItemMetadata,
        receiveRecord: RecordingReceiveRecord?
    ) -> Bool {
        guard let receiveRecord else {
            return true
        }
        if studyItem.isTrashed {
            return true
        }
        if studyItem.title != title(receiveRecord: receiveRecord, studyItem: nil) {
            return true
        }
        if CanonicalRecordingMetadata.Filing(studyItem.studyFiling) != CanonicalRecordingMetadata.Filing(receiveRecord.studyFiling) {
            return true
        }
        if normalizedTags(studyItem.tags.map(\.value)) != normalizedTags(receiveRecord.tags) {
            return true
        }
        return false
    }

    private static func hasBusinessOverride(
        studyItem: StudyItemMetadata,
        inboxItem: MacRecordingInboxItem?
    ) -> Bool {
        guard let inboxItem else {
            return true
        }
        if studyItem.isTrashed {
            return true
        }
        let inboxTitle = inboxItem.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未命名录音"
        if studyItem.title != inboxTitle {
            return true
        }
        if CanonicalRecordingMetadata.Filing(studyItem.studyFiling) != CanonicalRecordingMetadata.Filing(inboxItem.studyFiling) {
            return true
        }
        if !normalizedTags(studyItem.tags.map(\.value)).isEmpty {
            return true
        }
        return false
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.compactMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.lowercased()
        })).sorted()
    }

    private static func syncState(isDeleted: Bool, studyItem: StudyItemMetadata?) -> CanonicalSyncState {
        if isDeleted {
            return .deleted
        }
        if studyItem?.syncConflictStatus != nil {
            return .conflict
        }
        return .localOnly
    }

    private static func transferState(_ status: String?) -> CanonicalTransferState {
        switch status?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "queued":
            return .queued
        case "inFlight", "uploading", "downloading", "finalizing":
            return .inFlight
        case "retryPending":
            return .retryPending
        case "completed", "complete":
            return .completed
        case "failed":
            return .failed
        case "conflict":
            return .conflict
        default:
            return .none
        }
    }

    private static func processingStage(_ status: String?) -> CanonicalProcessingState.Stage {
        switch status?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "queued":
            return .queued
        case "transcribing", "generating", "processing":
            return .processing
        case "transcribed", "generated", "completed":
            return .completed
        case "failed":
            return .failed
        case "notStarted", "notGenerated", "":
            return .notStarted
        default:
            return .unknown
        }
    }
}

private extension CanonicalRecordingMetadata.Filing {
    nonisolated init?(_ filing: StudyFilingPath?) {
        guard let filing, !filing.isEmpty else {
            return nil
        }
        self.init(
            type: filing.type,
            subject: filing.subject,
            chapter: filing.chapter,
            topic: filing.topic
        )
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
