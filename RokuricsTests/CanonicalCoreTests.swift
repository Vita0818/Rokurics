//
//  CanonicalCoreTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/1.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalCoreTests {
    @Test func canonicalManifestHashSurvivesISO8601RoundTripWithFractionalInput() throws {
        let manifest = CanonicalManifest.make(
            node: CanonicalNode(nodeID: "iphone-01", platform: "iPhone"),
            generatedAt: Date(timeIntervalSince1970: 1_783_692_585.123_456),
            objects: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(CanonicalManifest.self, from: encoder.encode(manifest))

        #expect(manifest.generatedAt.date.timeIntervalSince1970 == 1_783_692_585)
        #expect(decoded.hasValidManifestHash)
        #expect(decoded.manifestHash == manifest.manifestHash)
    }

    @Test func iphoneAdapterUsesStableObjectIDAndCanonicalMetadataHash() {
        let metadata = makeMetadata()
        let object = IPhoneCanonicalRecordingAdapter().makeObject(metadata: metadata)
        let expected = expectedCanonicalMetadata()
        let manifest = IPhoneCanonicalRecordingAdapter().makeManifest(
            recordings: [metadata],
            audioFactsByRecordingID: [:],
            node: CanonicalNode(nodeID: "iphone-01", platform: "iPhone")
        )

        #expect(object.objectID == "canonical-recording-01")
        #expect(sameHash(object.metadataHash, expected.metadataHash))
        #expect(sameHash(manifest.object(withID: "canonical-recording-01")?.metadataHash, expected.metadataHash))
        #expect(manifest.hasValidManifestHash)
    }

    @Test func metadataHashIgnoresUploadProgressDisplayAndLedgerState() {
        let base = IPhoneCanonicalRecordingAdapter().makeObject(metadata: makeMetadata(uploadStatus: "localOnly"))
        var uploaded = IPhoneCanonicalRecordingAdapter().makeObject(
            metadata: makeMetadata(
                uploadStatus: "uploaded",
                uploadProgressFraction: 1,
                uploadProgressConfirmedBytes: 42,
                uploadProgressTotalBytes: 42,
                uploadPhase: "finalized",
                uploadProgressDescription: "done"
            )
        )
        uploaded.transferState = .completed
        let projection = ObjectProjection.make(from: uploaded)

        #expect(sameHash(uploaded.metadataHash, base.metadataHash))
        #expect(sameHash(projection.metadataHash, base.metadataHash))
        #expect(!projection.audioAvailable)
    }

    @Test func metadataHashIgnoresCreationTimeDurationProcessingAndAudioFacts() {
        let adapter = IPhoneCanonicalRecordingAdapter()
        let base = adapter.makeObject(metadata: makeMetadata())
        let changedClocksAndProcessing = adapter.makeObject(
            metadata: makeMetadata(
                createdAt: Date(timeIntervalSince1970: 2_000.987_654),
                duration: 900,
                transcriptionStatus: "transcribed",
                noteStatus: "generated"
            )
        )
        let changedAudioFacts = adapter.makeObject(
            metadata: makeMetadata(),
            audioFact: .audio(
                availability: .available,
                contentHash: CanonicalHash("bbbbbbbb"),
                byteSize: 900,
                logicalName: "renamed-audio.m4a"
            )
        )
        let restoredWithStaleDeletedAt = adapter.makeObject(
            metadata: makeMetadata(isDeleted: false, deletedAt: Date(timeIntervalSince1970: 2_100))
        )

        #expect(sameHash(changedClocksAndProcessing.metadataHash, base.metadataHash))
        #expect(sameHash(changedAudioFacts.metadataHash, base.metadataHash))
        #expect(sameHash(restoredWithStaleDeletedAt.metadataHash, base.metadataHash))
        #expect(restoredWithStaleDeletedAt.metadata.modifiedAt.date == Date(timeIntervalSince1970: 2_000))
        #expect(restoredWithStaleDeletedAt.metadata.deletedAt == nil)
    }

    @Test func metadataHashChangesForBusinessMetadata() {
        let adapter = IPhoneCanonicalRecordingAdapter()
        let baseHash = adapter.makeObject(metadata: makeMetadata()).metadataHash
        let renamedHash = adapter.makeObject(metadata: makeMetadata(title: "Renamed Lecture")).metadataHash
        let refilingHash = adapter.makeObject(
            metadata: makeMetadata(studyFiling: StudyFilingPath(type: "课堂", subject: "物理"))
        ).metadataHash
        let taggedHash = adapter.makeObject(metadata: makeMetadata(tags: ["exam"])).metadataHash
        let deletedHash = adapter.makeObject(
            metadata: makeMetadata(isDeleted: true, deletedAt: Date(timeIntervalSince1970: 2_100))
        ).metadataHash

        #expect(!sameHash(renamedHash, baseHash))
        #expect(!sameHash(refilingHash, baseHash))
        #expect(!sameHash(taggedHash, baseHash))
        #expect(!sameHash(deletedHash, baseHash))
    }

    @Test func audioTransferNoOpRequiresSameHashAndSize() {
        let local = audioObject(hash: "aaaaaaaa", size: 42)
        let peerSame = audioObject(hash: "aaaaaaaa", size: 42, nodeID: "mac-01")
        let peerDifferentHash = audioObject(hash: "bbbbbbbb", size: 42, nodeID: "mac-01")
        let peerDifferentSize = audioObject(hash: "aaaaaaaa", size: 43, nodeID: "mac-01")

        #expect(TransferDecision.audio(local: local, peer: peerSame).kind == .noOp)
        #expect(TransferDecision.audio(local: local, peer: peerSame).reason == "peer_audio_same_hash_and_size")
        #expect(TransferDecision.audio(local: local, peer: peerDifferentHash).kind == .conflict)
        #expect(TransferDecision.audio(local: local, peer: peerDifferentHash).conflictReason == .artifactHashMismatch)
        #expect(TransferDecision.audio(local: local, peer: peerDifferentSize).kind == .conflict)
        #expect(TransferDecision.audio(local: local, peer: peerDifferentSize).conflictReason == .artifactSizeMismatch)
    }

    @Test func peerUnknownAndHashUnavailableDoNotBecomeAudioNoOp() {
        let local = audioObject(hash: "aaaaaaaa", size: 42)
        let peerWithoutHash = IPhoneCanonicalRecordingAdapter().makeObject(
            metadata: makeMetadata(),
            audioFact: .audio(availability: .availableWithoutHash, byteSize: 42)
        )
        let peerClaimedAvailableWithoutProof = IPhoneCanonicalRecordingAdapter().makeObject(
            metadata: makeMetadata(),
            audioFact: .audio(availability: .available, byteSize: 42)
        )

        #expect(TransferDecision.audio(local: local, peer: nil).kind == .deferUntilPeerKnown)
        #expect(TransferDecision.audio(local: local, peer: nil).reason == "peer_unknown_is_not_missing")
        #expect(TransferDecision.audio(local: local, peer: peerWithoutHash).kind == .deferUntilPeerKnown)
        #expect(TransferDecision.audio(local: local, peer: peerClaimedAvailableWithoutProof).kind == .deferUntilPeerKnown)
        #expect(!peerWithoutHash.audioAvailable)
        #expect(!peerClaimedAvailableWithoutProof.audioAvailable)
    }

    @Test func uploadedMetadataAndCompletedLedgerDoNotProveAudioUploaded() {
        var object = IPhoneCanonicalRecordingAdapter().makeObject(metadata: makeMetadata(uploadStatus: "uploaded"))
        object.transferState = .completed
        let withoutHash = IPhoneCanonicalRecordingAdapter().makeObject(
            metadata: makeMetadata(uploadStatus: "uploaded"),
            audioFact: .audio(availability: .availableWithoutHash, byteSize: 42)
        )

        #expect(!object.audioAvailable)
        #expect(!ObjectProjection.make(from: object).audioAvailable)
        #expect(!withoutHash.audioAvailable)
    }

    @Test func canonicalArtifactContractSanitizesPathAndDecodesOldPayload() throws {
        let artifact = CanonicalProjectionContract.makeArtifact(
            objectID: "canonical-recording-01",
            kind: .transcriptMarkdown,
            availability: .available,
            contentHash: CanonicalHash("aaaaaaaa"),
            byteSize: 120,
            logicalPathToken: "transcripts/canonical-recording-01/transcript.md",
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 3_000)),
            producedByNodeID: nil,
            platform: "iPhone"
        )
        let oldPayload = """
        {
          "artifactID":"transcriptMarkdown:canonical-recording-01",
          "objectID":"canonical-recording-01",
          "kind":"transcriptMarkdown",
          "availability":"available",
          "contentHash":{"algorithm":"sha256","value":"aaaaaaaa"},
          "byteSize":120,
          "logicalName":"transcript.md"
        }
        """
        let decoded = try JSONDecoder().decode(CanonicalArtifact.self, from: Data(oldPayload.utf8))

        #expect(artifact.artifactID == "transcriptMarkdown:canonical-recording-01")
        #expect(artifact.logicalPathToken == "transcripts/canonical-recording-01/transcript.md")
        #expect(artifact.logicalName == "transcript.md")
        #expect(artifact.producedBy == nil)
        #expect(CanonicalProjectionContract.safeLogicalPathToken("/private/transcript.md") == nil)
        #expect(decoded.logicalPathToken == nil)
        #expect(decoded.producedBy == nil)
    }

    @Test func iphoneAdapterProjectsDownloadedGeneratedArtifactAsNonAuthoritative() {
        let metadata = makeMetadata()
        let downloadedTranscript = CanonicalProjectionContract.makeArtifact(
            objectID: metadata.id,
            kind: .transcriptMarkdown,
            availability: .available,
            contentHash: CanonicalHash("aaaaaaaa"),
            byteSize: 120,
            logicalPathToken: "transcripts/canonical-recording-01/transcript.md",
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 3_000)),
            producedByNodeID: nil,
            platform: "iPhone"
        )
        let object = IPhoneCanonicalRecordingAdapter().makeObject(
            metadata: metadata,
            artifactFacts: [downloadedTranscript],
            nodeID: "iphone-01"
        )
        let transcript = object.artifacts.first { $0.kind == .transcriptMarkdown }

        #expect(transcript?.provesCanonicalGeneratedArtifactAvailability == true)
        #expect(transcript?.producedBy == nil)
        #expect(transcript?.logicalPathToken == "transcripts/canonical-recording-01/transcript.md")
    }

    private func audioObject(hash: String, size: Int64, nodeID: String = "iphone-01") -> CanonicalRecordingObject {
        IPhoneCanonicalRecordingAdapter().makeObject(
            metadata: makeMetadata(),
            audioFact: .audio(
                availability: .available,
                contentHash: CanonicalHash(hash),
                byteSize: size,
                logicalName: "audio.m4a"
            ),
            nodeID: nodeID
        )
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

    private func makeMetadata(
        id: String = "canonical-recording-01",
        title: String = "Canonical Lecture",
        uploadStatus: String = "localOnly",
        uploadProgressFraction: Double? = nil,
        uploadProgressConfirmedBytes: Int64? = nil,
        uploadProgressTotalBytes: Int64? = nil,
        uploadPhase: String? = nil,
        uploadProgressDescription: String? = nil,
        tags: [String] = ["Important"],
        studyFiling: StudyFilingPath? = StudyFilingPath(type: "课堂", subject: "数学", chapter: "矩阵", topic: "行列式"),
        createdAt: Date = Date(timeIntervalSince1970: 2_000),
        duration: TimeInterval = 42,
        transcriptionStatus: String = "notStarted",
        noteStatus: String = "notGenerated",
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) -> RecordingMetadata {
        RecordingMetadata(
            id: id,
            title: title,
            fileName: "\(id).m4a",
            relativeAudioPath: "Recordings/\(id).m4a",
            relativeMetadataPath: "Metadata/\(id).json",
            createdAt: createdAt,
            endedAt: createdAt.addingTimeInterval(duration),
            duration: duration,
            format: "m4a",
            codec: "AAC",
            sampleRate: 16_000,
            channels: 1,
            bitrate: 64_000,
            fileSize: 42,
            uploadStatus: uploadStatus,
            transcriptionStatus: transcriptionStatus,
            noteStatus: noteStatus,
            tags: tags,
            studyFiling: studyFiling,
            uploadProgressFraction: uploadProgressFraction,
            uploadProgressConfirmedBytes: uploadProgressConfirmedBytes,
            uploadProgressTotalBytes: uploadProgressTotalBytes,
            uploadPhase: uploadPhase,
            uploadProgressDescription: uploadProgressDescription,
            isDeleted: isDeleted,
            deletedAt: deletedAt
        )
    }
}
