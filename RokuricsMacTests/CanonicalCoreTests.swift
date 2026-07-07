//
//  CanonicalCoreTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/1.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalCoreTests {
    @Test func macAdapterUsesStableObjectIDAndCanonicalMetadataHash() {
        let receiveRecord = makeReceiveRecord()
        let studyItem = makeStudyItem()
        let object = MacCanonicalRecordingAdapter().makeObject(
            receiveRecord: receiveRecord,
            studyItem: studyItem,
            artifacts: []
        )
        let expected = expectedCanonicalMetadata()

        #expect(object.objectID == "canonical-recording-01")
        #expect(sameHash(object.metadataHash, expected.metadataHash))
        #expect(object.receivedAt?.date.timeIntervalSince1970 == 2_500)
    }

    @Test func macReceivedAtDoesNotChangeMetadataHash() {
        let adapter = MacCanonicalRecordingAdapter()
        let first = adapter.makeObject(
            receiveRecord: makeReceiveRecord(receivedAt: Date(timeIntervalSince1970: 2_500)),
            studyItem: nil,
            artifacts: []
        )
        let second = adapter.makeObject(
            receiveRecord: makeReceiveRecord(receivedAt: Date(timeIntervalSince1970: 9_000)),
            studyItem: nil,
            artifacts: []
        )

        #expect(sameHash(first.metadataHash, second.metadataHash))
    }

    @Test func receiveProcessingUpdatedAtDoesNotChangeBusinessModifiedAtOrMetadataHash() {
        let adapter = MacCanonicalRecordingAdapter()
        let base = adapter.makeObject(
            receiveRecord: makeReceiveRecord(updatedAt: Date(timeIntervalSince1970: 2_000)),
            studyItem: nil,
            artifacts: []
        )
        let processingChanged = adapter.makeObject(
            receiveRecord: makeReceiveRecord(
                updatedAt: Date(timeIntervalSince1970: 9_000),
                transcriptionStatus: "transcribed",
                noteStatus: "generated",
                processingStatus: "completed"
            ),
            studyItem: nil,
            artifacts: []
        )

        #expect(processingChanged.metadata.modifiedAt.date == Date(timeIntervalSince1970: 2_000))
        #expect(sameHash(processingChanged.metadataHash, base.metadataHash))
    }

    @Test func inboxFallbackUpdatedAtDoesNotBecomeCanonicalBusinessModifiedAt() {
        let inboxItem = makeInboxItem()
        let fallbackStudyItem = StudyItemMetadata(
            recordingID: "canonical-recording-01",
            title: "Canonical Lecture",
            createdAt: Date(timeIntervalSince1970: 2_500),
            duration: 42,
            studyFiling: StudyFilingPath(type: "课堂", subject: "数学", chapter: "矩阵", topic: "行列式"),
            tags: [],
            updatedAt: Date(timeIntervalSince1970: 9_000),
            transcriptionStatus: "transcribed",
            noteStatus: "generated"
        )
        let object = MacCanonicalRecordingAdapter().makeObject(
            inboxItem: inboxItem,
            studyItem: fallbackStudyItem,
            artifacts: []
        )

        #expect(object.metadata.modifiedAt.date == Date(timeIntervalSince1970: 2_500))
    }

    @Test func businessStudyItemChangesUseBusinessUpdatedAt() {
        let adapter = MacCanonicalRecordingAdapter()
        let base = adapter.makeObject(
            receiveRecord: makeReceiveRecord(),
            studyItem: makeStudyItem(),
            artifacts: []
        )
        let renamed = adapter.makeObject(
            receiveRecord: makeReceiveRecord(),
            studyItem: makeStudyItem(title: "Renamed Lecture", updatedAt: Date(timeIntervalSince1970: 7_000)),
            artifacts: []
        )

        #expect(renamed.metadata.modifiedAt.date == Date(timeIntervalSince1970: 7_000))
        #expect(!sameHash(renamed.metadataHash, base.metadataHash))
    }

    @Test func receiveStatusTransferStateAndProjectionDoNotChangeMetadataHash() {
        let adapter = MacCanonicalRecordingAdapter()
        let base = adapter.makeObject(
            receiveRecord: makeReceiveRecord(status: "received", localNetworkTransferState: nil),
            studyItem: makeStudyItem(),
            artifacts: []
        )
        var changed = adapter.makeObject(
            receiveRecord: makeReceiveRecord(status: "completed", localNetworkTransferState: "completed"),
            studyItem: makeStudyItem(),
            artifacts: []
        )
        changed.transferState = .completed
        let projection = ObjectProjection.make(from: changed)

        #expect(sameHash(changed.metadataHash, base.metadataHash))
        #expect(sameHash(projection.metadataHash, base.metadataHash))
        #expect(!projection.audioAvailable)
    }

    @Test func receiveRecordExistingDoesNotProveAudioUploaded() {
        let adapter = MacCanonicalRecordingAdapter()
        var receiveRecord = makeReceiveRecord(status: "completed")
        receiveRecord.audioRelativePath = "audio/inbox/1970-01-01/canonical-recording-01/audio.m4a"
        receiveRecord.checksum = "aaaaaaaa"
        receiveRecord.fileSize = 42
        let receiveOnly = adapter.makeObject(receiveRecord: receiveRecord, studyItem: nil, artifacts: [])
        let hashUnavailable = adapter.makeObject(
            receiveRecord: receiveRecord,
            studyItem: nil,
            artifacts: [
                CanonicalArtifactFact.audio(
                    availability: .availableWithoutHash,
                    byteSize: 42,
                    logicalName: "audio.m4a"
                ).makeArtifact(objectID: receiveRecord.recordingID)
            ]
        )
        let provenAudio = adapter.makeObject(
            receiveRecord: receiveRecord,
            studyItem: nil,
            artifacts: [
                CanonicalArtifactFact.audio(
                    availability: .available,
                    contentHash: CanonicalHash("aaaaaaaa"),
                    byteSize: 42,
                    logicalName: "audio.m4a"
                ).makeArtifact(objectID: receiveRecord.recordingID)
            ]
        )

        #expect(!receiveOnly.audioAvailable)
        #expect(!hashUnavailable.audioAvailable)
        #expect(provenAudio.audioAvailable)
    }

    @Test func macManifestJoinsReceiveStudyAndArtifactFactsByRecordingID() {
        let node = CanonicalNode(nodeID: "mac-01", platform: "Mac")
        let artifact = CanonicalArtifactFact.audio(
            availability: .available,
            contentHash: CanonicalHash("aaaaaaaa"),
            byteSize: 42,
            logicalName: "audio.m4a"
        ).makeArtifact(objectID: "canonical-recording-01")
        let manifest = MacCanonicalRecordingAdapter().makeManifest(
            receiveRecords: [makeReceiveRecord()],
            studyItems: [makeStudyItem()],
            artifactFactsByRecordingID: ["canonical-recording-01": [artifact]],
            node: node,
            generatedAt: Date(timeIntervalSince1970: 3_000)
        )
        let object = manifest.object(withID: "canonical-recording-01")

        #expect(manifest.hasValidManifestHash)
        #expect(sameHash(object?.metadataHash, expectedCanonicalMetadata().metadataHash))
        #expect(object?.audioAvailable == true)
    }

    @Test func macGeneratedArtifactProjectionMarksAuthoritativeProducer() {
        let node = CanonicalNode(
            nodeID: "mac-01",
            platform: "Mac",
            capabilities: [.recordingMetadata, .audioArtifact, .transcriptArtifact, .noteArtifact, .summaryArtifact]
        )
        let transcript = CanonicalProjectionContract.makeArtifact(
            objectID: "canonical-recording-01",
            kind: .transcriptJSON,
            availability: .available,
            contentHash: CanonicalHash("aaaaaaaa"),
            byteSize: 256,
            logicalPathToken: "transcripts/canonical-recording-01/transcript.json",
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 4_000)),
            producedByNodeID: "mac-01",
            platform: "Mac"
        )
        let note = CanonicalProjectionContract.makeArtifact(
            objectID: "canonical-recording-01",
            kind: .noteMarkdown,
            availability: .available,
            contentHash: CanonicalHash("bbbbbbbb"),
            byteSize: 512,
            logicalPathToken: "notes/canonical-recording-01/note.md",
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 4_100)),
            producedByNodeID: "mac-01",
            platform: "Mac"
        )
        let object = MacCanonicalRecordingAdapter().makeObject(
            receiveRecord: makeReceiveRecord(),
            studyItem: makeStudyItem(),
            artifacts: [transcript, note],
            nodeID: "mac-01"
        )

        #expect(object.artifacts.first { $0.kind == .transcriptJSON }?.producedBy == .transcription)
        #expect(object.artifacts.first { $0.kind == .noteMarkdown }?.producedBy == .noteGeneration)
        #expect(CanonicalProjectionContract.isAuthoritativeProducer(transcript, node: node))
        #expect(CanonicalProjectionContract.isAuthoritativeProducer(note, node: node))
    }

    private func sameHash(_ lhs: CanonicalHash?, _ rhs: CanonicalHash?) -> Bool {
        lhs?.algorithm == rhs?.algorithm && lhs?.value == rhs?.value
    }

    private func sameHash(_ lhs: CanonicalHash, _ rhs: CanonicalHash) -> Bool {
        lhs.algorithm == rhs.algorithm && lhs.value == rhs.value
    }

    private func expectedCanonicalMetadata() -> CanonicalRecordingMetadata {
        CanonicalRecordingMetadata(
            objectID: "canonical-recording-01",
            title: "Canonical Lecture",
            createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2_000)),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2_000)),
            duration: 42,
            filing: CanonicalRecordingMetadata.Filing(type: "课堂", subject: "数学", chapter: "矩阵", topic: "行列式"),
            tags: ["Important"],
            isDeleted: false,
            deletedAt: nil
        )
    }

    private func makeStudyItem(
        title: String = "Canonical Lecture",
        updatedAt: Date = Date(timeIntervalSince1970: 2_000)
    ) -> StudyItemMetadata {
        StudyItemMetadata(
            recordingID: "canonical-recording-01",
            title: title,
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 42,
            audioRelativePath: nil,
            studyFiling: StudyFilingPath(type: "课堂", subject: "数学", chapter: "矩阵", topic: "行列式"),
            tags: [StudyTag(namespace: "custom", value: "Important")],
            updatedAt: updatedAt,
            transcriptionStatus: "notStarted",
            noteStatus: "notGenerated"
        )
    }

    private func makeReceiveRecord(
        receivedAt: Date = Date(timeIntervalSince1970: 2_500),
        updatedAt: Date = Date(timeIntervalSince1970: 2_000),
        status: String = "received",
        localNetworkTransferState: String? = nil,
        transcriptionStatus: String = "notStarted",
        noteStatus: String = "notGenerated",
        processingStatus: String = "notStarted"
    ) -> RecordingReceiveRecord {
        RecordingReceiveRecord(
            recordingID: "canonical-recording-01",
            sanitizedRecordingID: "canonical-recording-01",
            receivedAt: receivedAt,
            updatedAt: updatedAt,
            sourceDeviceID: "iphone-01",
            sourceDeviceName: "iPhone",
            originalTitle: "Canonical Lecture",
            normalizedTitle: "Canonical Lecture",
            audioFileName: "audio.m4a",
            originalAudioFileName: "canonical-recording-01.m4a",
            metadataFileName: "metadata.json",
            status: status,
            transcriptionStatus: transcriptionStatus,
            noteStatus: noteStatus,
            processingStatus: processingStatus,
            suggestedCategory: nil,
            course: nil,
            category: nil,
            tags: ["Important"],
            studyFiling: StudyFilingPath(type: "课堂", subject: "数学", chapter: "矩阵", topic: "行列式"),
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 42,
            fileSize: 42,
            suggestedFolder: nil,
            userConfirmedFolder: nil,
            checksum: nil,
            audioRelativePath: nil,
            metadataRelativePath: "audio/inbox/1970-01-01/canonical-recording-01/metadata.json",
            localNetworkTransferState: localNetworkTransferState
        )
    }

    private func makeInboxItem() -> MacRecordingInboxItem {
        MacRecordingInboxItem(
            id: "canonical-recording-01",
            title: "Canonical Lecture",
            receivedAt: Date(timeIntervalSince1970: 2_500),
            duration: 42,
            fileSize: 42,
            sourceDeviceID: "iphone-01",
            sourceDeviceName: "iPhone",
            audioChecksum: nil,
            transcriptionStatus: "transcribed",
            noteStatus: "generated",
            receiveStatus: "received",
            hasAudio: true,
            audioRelativePath: "audio/inbox/1970-01-01/canonical-recording-01/audio.m4a",
            receiveRelativePath: "audio/inbox/1970-01-01/canonical-recording-01/receive.json",
            transcriptRelativePath: nil,
            transcriptMarkdownRelativePath: nil,
            transcriptionError: nil,
            studyFiling: StudyFilingPath(type: "课堂", subject: "数学", chapter: "矩阵", topic: "行列式")
        )
    }
}
