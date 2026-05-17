//
//  RokuricsTests.swift
//  RokuricsTests
//
//  Created by Vita on 2026/5/8.
//

import Testing
import Foundation
@testable import Rokurics

struct RokuricsTests {

    @Test func renameRecordingUpdatesMetadataTitle() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-01", title: "旧名称", store: store)

        let updated = try store.updateTitle(recordingID: metadata.id, rawTitle: " 新名称 ")

        #expect(updated.title == "新名称")
        #expect(try store.loadMetadata(id: metadata.id).title == "新名称")
    }

    @Test func renameRecordingTrimsWhitespaceAndNewlines() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-02", title: "旧名称", store: store)

        let updated = try store.updateTitle(recordingID: metadata.id, rawTitle: "  第一行\n第二行  ")

        #expect(updated.title == "第一行 第二行")
    }

    @Test func emptyRenameDoesNotSaveEmptyTitle() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-03", title: "保留名称", store: store)

        let updated = try store.updateTitle(recordingID: metadata.id, rawTitle: "   ")

        #expect(updated.title == "保留名称")
        #expect(try store.loadMetadata(id: metadata.id).title == "保留名称")
    }

    @Test func recordingMetadataMissingDeletedFieldsDefaultsToActive() throws {
        let metadata = makeMetadata(
            id: "recording-legacy",
            title: "旧录音",
            relativeAudioPath: "Recordings/recording-legacy.m4a",
            relativeMetadataPath: "Metadata/recording-legacy.json",
            uploadStatus: "localOnly"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: try encoder.encode(metadata)) as? [String: Any])
        object.removeValue(forKey: "isDeleted")
        object.removeValue(forKey: "deletedAt")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RecordingMetadata.self, from: data)

        #expect(decoded.isDeleted == false)
        #expect(decoded.deletedAt == nil)
    }

    @Test func softDeleteRecordingUpdatesMetadataButKeepsFiles() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-04", title: "要删除", store: store)
        let audioURL = try store.audioURL(for: metadata)
        let metadataURL = try store.makeMetadataURL(id: metadata.id)

        try store.deleteRecording(metadata)

        let updated = try store.loadMetadata(id: metadata.id)
        #expect(updated.isDeleted)
        #expect(updated.deletedAt != nil)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(FileManager.default.fileExists(atPath: metadataURL.path))
        #expect(try store.loadAllMetadata().isEmpty)
        #expect(try store.loadTrashedMetadata().map(\.id) == [metadata.id])
    }

    @Test func permanentDeleteRecordingRemovesAudioAndMetadata() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-permanent", title: "永久删除", store: store)
        let audioURL = try store.audioURL(for: metadata)
        let metadataURL = try store.makeMetadataURL(id: metadata.id)

        try store.permanentlyDeleteRecording(metadata)

        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        #expect(!FileManager.default.fileExists(atPath: metadataURL.path))
    }

    @Test func permanentDeleteRejectsAudioPathOutsideRokuricsRoot() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let outsideURL = rootURL
            .deletingLastPathComponent()
            .appendingPathComponent("outside.m4a", isDirectory: false)
        try Data("outside".utf8).write(to: outsideURL)
        let metadataURL = try store.makeMetadataURL(id: "recording-05")
        let metadata = makeMetadata(
            id: "recording-05",
            title: "越界",
            relativeAudioPath: "../outside.m4a",
            relativeMetadataPath: try store.relativePath(for: metadataURL),
            uploadStatus: "localOnly"
        )
        try store.saveMetadata(metadata)

        do {
            try store.permanentlyDeleteRecording(metadata)
            Issue.record("Expected delete to reject path outside Rokurics root")
        } catch AudioFileStoreError.pathOutsideRokuricsDirectory {
            #expect(FileManager.default.fileExists(atPath: outsideURL.path))
        }
    }

    @Test func softDeleteUploadedRecordingDoesNotRemoveLocalFilesOrRemoteState() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-06", title: "已上传", store: store, uploadStatus: "uploaded")
        let audioURL = try store.audioURL(for: metadata)

        try store.deleteRecording(metadata)

        #expect(try store.loadAllMetadata().isEmpty)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == "uploaded")
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test func restoreRecordingBringsItemBackFromTrash() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-restore", title: "恢复", store: store)

        try store.deleteRecording(metadata)
        let restored = try store.restoreRecording(id: metadata.id)

        #expect(restored.isDeleted == false)
        #expect(restored.deletedAt == nil)
        #expect(try store.loadAllMetadata().map(\.id) == [metadata.id])
        #expect(try store.loadTrashedMetadata().isEmpty)
    }

    @Test func loadAllMetadataFiltersDeletedRecordingsByDefault() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "recording-active", title: "保留", store: store)
        let deleted = try saveRecording(id: "recording-deleted", title: "废纸篓", store: store)

        try store.deleteRecording(deleted)

        #expect(try store.loadAllMetadata().map(\.id) == ["recording-active"])
        #expect(Set(try store.loadAllMetadata(includeDeleted: true).map(\.id)) == ["recording-active", "recording-deleted"])
    }

    @MainActor
    @Test func deletingRecordingUpdatesManagerListCount() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "recording-07", title: "第一条", store: store)
        _ = try saveRecording(id: "recording-08", title: "第二条", store: store)
        let manager = RecordingManager(fileStore: store)

        try manager.deleteRecording(recordingID: "recording-07")

        #expect(manager.recordings.count == 1)
        #expect(!manager.recordings.map(\.id).contains("recording-07"))
        #expect(manager.trashedRecordings.map(\.id) == ["recording-07"])
    }

    @MainActor
    @Test func homepageRecordingCountExcludesDeletedItems() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "recording-home-active", title: "首页显示", store: store)
        let deleted = try saveRecording(id: "recording-home-deleted", title: "首页隐藏", store: store)
        try store.deleteRecording(deleted)

        let manager = RecordingManager(fileStore: store)

        #expect(manager.recordings.count == 1)
        #expect(manager.recordings.first?.id == "recording-home-active")
        #expect(manager.pendingUploadCount == 1)
    }

    @Test func uploadCapsulePresentationKeepsStatusMapping() {
        #expect(RecordingUploadCapsulePresentation.resolve(status: .localOnly, isMacPaired: true).label == "上传")
        #expect(RecordingUploadCapsulePresentation.resolve(status: .uploading, isMacPaired: true).label == "上传中")
        #expect(RecordingUploadCapsulePresentation.resolve(status: .uploaded, isMacPaired: true).label == "已上传")
        #expect(RecordingUploadCapsulePresentation.resolve(status: .failed, isMacPaired: true).label == "重试")
        #expect(RecordingUploadCapsulePresentation.resolve(status: .localOnly, isMacPaired: true).isEnabled)
        #expect(RecordingUploadCapsulePresentation.resolve(status: .failed, isMacPaired: true).isEnabled)
        #expect(!RecordingUploadCapsulePresentation.resolve(status: .uploading, isMacPaired: true).isEnabled)
        #expect(!RecordingUploadCapsulePresentation.resolve(status: .uploaded, isMacPaired: true).isEnabled)
        #expect(!RecordingUploadCapsulePresentation.resolve(status: .localOnly, isMacPaired: false).isEnabled)
    }

    @Test func doubleTapRecordingIconResolvesMoveToTrashIntent() {
        #expect(RecordingRowIconInteraction.intent(for: .singleTap) == .none)
        #expect(RecordingRowIconInteraction.intent(for: .doubleTap) == .moveToTrash)
        #expect(RecordingRowIconInteraction.deletionTapCount == 2)
    }

    private func makeStore() throws -> (AudioFileStore, URL) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = AudioFileStore(rootDirectoryURL: rootURL)
        try store.ensureStorageDirectories()
        return (store, rootURL)
    }

    private func saveRecording(
        id: String,
        title: String,
        store: AudioFileStore,
        uploadStatus: String = "localOnly"
    ) throws -> RecordingMetadata {
        let audioURL = try store.recordingsDirectory()
            .appendingPathComponent(id, isDirectory: false)
            .appendingPathExtension("m4a")
        try Data("audio".utf8).write(to: audioURL)
        let metadataURL = try store.makeMetadataURL(id: id)
        let metadata = makeMetadata(
            id: id,
            title: title,
            relativeAudioPath: try store.relativePath(for: audioURL),
            relativeMetadataPath: try store.relativePath(for: metadataURL),
            uploadStatus: uploadStatus
        )
        try store.saveMetadata(metadata)
        return metadata
    }

    private func makeMetadata(
        id: String,
        title: String,
        relativeAudioPath: String,
        relativeMetadataPath: String,
        uploadStatus: String
    ) -> RecordingMetadata {
        RecordingMetadata(
            id: id,
            title: title,
            fileName: "\(id).m4a",
            relativeAudioPath: relativeAudioPath,
            relativeMetadataPath: relativeMetadataPath,
            createdAt: Date(timeIntervalSince1970: 1_800),
            endedAt: Date(timeIntervalSince1970: 1_806),
            duration: 6,
            format: "m4a",
            codec: "AAC",
            sampleRate: 16_000,
            channels: 1,
            bitrate: 64_000,
            fileSize: 5,
            uploadStatus: uploadStatus,
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            tags: []
        )
    }
}
