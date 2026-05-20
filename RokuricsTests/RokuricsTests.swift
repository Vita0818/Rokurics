//
//  RokuricsTests.swift
//  RokuricsTests
//
//  Created by Vita on 2026/5/8.
//

import Testing
import Foundation
@testable import Rokurics

@MainActor
struct RokuricsTests {

    @Test func iphoneTypographyTokensExistAndChatStylesStaySeparate() {
        #expect(RokuricsTypographyToken.allCases == [
            .pageTitle,
            .sectionTitle,
            .cardTitle,
            .body,
            .secondary,
            .chatGreeting,
            .chatMessage,
            .chatInput,
            .technical
        ])
        #expect(RokuricsTypographyToken.chatGreeting != .pageTitle)
        #expect(RokuricsTypographyToken.chatMessage != .pageTitle)
        #expect(RokuricsTypographyToken.chatInput != .pageTitle)
    }

    @Test func iphoneCircleIconButtonConfigurationUsesSystemGlassButton() {
        #expect(RokuricsIconCircleButtonConfiguration.size >= 44)
        #expect(RokuricsIconCircleButtonConfiguration.iconSize > 0)
        #expect(RokuricsIconCircleButtonConfiguration.borderWidth == 1)
        #expect(RokuricsIconCircleButtonConfiguration.usesGlassBackground)
        #expect(RokuricsIconCircleButtonConfiguration.usesSystemSymbols)
    }

    @Test func iphoneTechnicalInlineFragmentsDoNotPromoteWholeStringsToMonospace() {
        let fragments: [RokuricsInlineTextFragment] = [
            .text("路径 "),
            .technical("transcripts/2026-05-16/transcript.md"),
            .text(" 已保存")
        ]

        #expect(fragments[0].kind == .normal(.body))
        #expect(fragments[1].kind == .technical)
        #expect(fragments[2].kind == .normal(.body))
    }

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

    @Test func recordingMetadataMissingStudyFilingDecodesAsUnfiled() throws {
        let metadata = makeMetadata(
            id: "recording-legacy-filing",
            title: "旧录音",
            relativeAudioPath: "Recordings/recording-legacy-filing.m4a",
            relativeMetadataPath: "Metadata/recording-legacy-filing.json",
            uploadStatus: "localOnly"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: try encoder.encode(metadata)) as? [String: Any])
        object.removeValue(forKey: "studyFiling")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RecordingMetadata.self, from: data)

        #expect(decoded.studyFiling == nil)
    }

    @Test func directSaveUsesDefaultTitleAndEmptyFiling() {
        let title = RecordingSaveTitleResolver.title(
            defaultTitle: "录音 2026-05-18 12:00",
            pendingTitle: "课堂标题",
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数"),
            directSave: true
        )

        #expect(title == "录音 2026-05-18 12:00")
    }

    @Test func filingSaveCanGenerateFriendlyTitle() {
        let title = RecordingSaveTitleResolver.title(
            defaultTitle: "录音 2026-05-18 12:00",
            pendingTitle: nil,
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法"),
            directSave: false
        )

        #expect(title == "线性代数 · 矩阵 · 矩阵乘法")
    }

    @Test func uploadMetadataPayloadIncludesStudyFiling() {
        let filing = StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        let metadata = makeMetadata(
            id: "recording-upload-filing",
            title: "矩阵乘法",
            relativeAudioPath: "Recordings/recording-upload-filing.m4a",
            relativeMetadataPath: "Metadata/recording-upload-filing.json",
            uploadStatus: "localOnly",
            studyFiling: filing
        )

        let payload = RecordingUploadMetadataPayload(
            metadata: metadata,
            sourceDeviceName: "iPhone",
            sourceDeviceID: "device-01",
            uploadedAt: Date(timeIntervalSince1970: 2_000)
        )

        #expect(payload.studyFiling == filing)
    }

    @Test func unfiledRecordingAppearsUnderUncategorizedStudyTree() {
        let metadata = makeMetadata(
            id: "recording-unfiled",
            title: "未分类",
            relativeAudioPath: "Recordings/recording-unfiled.m4a",
            relativeMetadataPath: "Metadata/recording-unfiled.json",
            uploadStatus: "localOnly"
        )

        let tree = RecordingStudyTreeBuilder.build(recordings: [metadata])

        #expect(tree.first?.title == StudyFilingPath.uncategorizedTitle)
        #expect(tree.first?.children.first?.title == StudyFilingPath.missingTitle)
        #expect(tree.first?.children.first?.children.first?.title == StudyFilingPath.missingTitle)
        #expect(tree.first?.children.first?.children.first?.children.first?.recordings.map(\.id) == ["recording-unfiled"])
    }

    @Test func filingCandidatesCollectExistingValues() {
        let first = makeMetadata(
            id: "candidate-iphone-01",
            title: "A",
            relativeAudioPath: "Recordings/a.m4a",
            relativeMetadataPath: "Metadata/a.json",
            uploadStatus: "localOnly",
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )
        let second = makeMetadata(
            id: "candidate-iphone-02",
            title: "B",
            relativeAudioPath: "Recordings/b.m4a",
            relativeMetadataPath: "Metadata/b.json",
            uploadStatus: "localOnly",
            studyFiling: StudyFilingPath(type: "复习", subject: "高等数学", chapter: "矩阵", topic: "格林公式")
        )

        let candidates = StudyFilingCandidates.collect(from: [first, second])

        #expect(Set(candidates.types) == Set(["课堂", "复习"]))
        #expect(Set(candidates.subjects) == Set(["线性代数", "高等数学"]))
        #expect(candidates.chapters == ["矩阵"])
        #expect(Set(candidates.topics) == Set(["矩阵乘法", "格林公式"]))
    }

    @Test func iphoneStudyBrowserRootLevelBuildsTypeFolders() {
        let recordings = [
            makeMetadata(
                id: "iphone-browser-root-01",
                title: "课堂",
                relativeAudioPath: "Recordings/a.m4a",
                relativeMetadataPath: "Metadata/a.json",
                uploadStatus: "localOnly",
                studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
            ),
            makeMetadata(
                id: "iphone-browser-root-02",
                title: "复习",
                relativeAudioPath: "Recordings/b.m4a",
                relativeMetadataPath: "Metadata/b.json",
                uploadStatus: "localOnly",
                studyFiling: StudyFilingPath(type: "复习", subject: "高等数学", chapter: "积分", topic: "格林公式")
            )
        ]

        let content = RecordingStudyBrowser.content(recordings: recordings, path: RecordingStudyBrowsePath())

        #expect(Set(content.folders.map(\.title)) == Set(["课堂", "复习"]))
        #expect(Set(content.folders.map(\.itemCount)) == Set([1]))
        #expect(content.recordings.isEmpty)
    }

    @Test func iphoneStudyBrowserBuildsNestedFoldersAndFinalRecordings() {
        let recording = makeMetadata(
            id: "iphone-browser-levels-01",
            title: "矩阵乘法",
            relativeAudioPath: "Recordings/matrix.m4a",
            relativeMetadataPath: "Metadata/matrix.json",
            uploadStatus: "localOnly",
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )

        let subjectContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂"]))
        let chapterContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂", "线性代数"]))
        let topicContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂", "线性代数", "矩阵"]))
        let recordingContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"]))

        #expect(subjectContent.folders.map(\.title) == ["线性代数"])
        #expect(chapterContent.folders.map(\.title) == ["矩阵"])
        #expect(topicContent.folders.map(\.title) == ["矩阵乘法"])
        #expect(recordingContent.recordings.map(\.id) == ["iphone-browser-levels-01"])
        #expect(recordingContent.folders.isEmpty)
    }

    @Test func iphoneStudyBrowserUncategorizedRecordingsAreDirectlyVisible() {
        let recording = makeMetadata(
            id: "iphone-browser-unfiled",
            title: "未分类",
            relativeAudioPath: "Recordings/unfiled.m4a",
            relativeMetadataPath: "Metadata/unfiled.json",
            uploadStatus: "localOnly"
        )

        let rootContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath())
        let uncategorizedContent = RecordingStudyBrowser.content(
            recordings: [recording],
            path: RecordingStudyBrowsePath(components: [StudyFilingPath.uncategorizedTitle])
        )

        #expect(rootContent.folders.map(\.title) == [StudyFilingPath.uncategorizedTitle])
        #expect(uncategorizedContent.recordings.map(\.id) == ["iphone-browser-unfiled"])
        #expect(uncategorizedContent.folders.isEmpty)
    }

    @Test func iphoneStudyBrowserMissingLowerFieldsDoNotHideRecordings() {
        let recording = makeMetadata(
            id: "iphone-browser-missing",
            title: "缺下层",
            relativeAudioPath: "Recordings/missing.m4a",
            relativeMetadataPath: "Metadata/missing.json",
            uploadStatus: "localOnly",
            studyFiling: StudyFilingPath(type: "课堂")
        )

        let subjectContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂"]))
        let chapterContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂", StudyFilingPath.missingTitle]))
        let topicContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂", StudyFilingPath.missingTitle, StudyFilingPath.missingTitle]))
        let recordingContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂", StudyFilingPath.missingTitle, StudyFilingPath.missingTitle, StudyFilingPath.missingTitle]))

        #expect(subjectContent.folders.map(\.title) == [StudyFilingPath.missingTitle])
        #expect(chapterContent.folders.map(\.title) == [StudyFilingPath.missingTitle])
        #expect(topicContent.folders.map(\.title) == [StudyFilingPath.missingTitle])
        #expect(recordingContent.recordings.map(\.id) == ["iphone-browser-missing"])
    }

    @Test func iphoneStudyBrowserBreadcrumbsNavigateByDepth() {
        let path = RecordingStudyBrowsePath(components: ["课堂", "线性代数", "矩阵"])
        let breadcrumbs = RecordingStudyBrowser.breadcrumbs(for: path)

        #expect(breadcrumbs.map(\.title) == ["学习库", "课堂", "线性代数", "矩阵"])
        #expect(breadcrumbs[1].path.components == ["课堂"])
        #expect(breadcrumbs[2].path.components == ["课堂", "线性代数"])
        #expect(path.parent.components == ["课堂", "线性代数"])
    }

    @Test func iphoneStudyFilingUpdateMovesRecordingToNewVirtualPath() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "iphone-browser-update", title: "路径更新", store: store)
        let manager = RecordingManager(fileStore: store)

        #expect(RecordingStudyBrowser.content(recordings: manager.recordings, path: RecordingStudyBrowsePath()).folders.map(\.title) == [StudyFilingPath.uncategorizedTitle])

        try manager.updateStudyFiling(
            recordingID: "iphone-browser-update",
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )

        let rootContent = RecordingStudyBrowser.content(recordings: manager.recordings, path: RecordingStudyBrowsePath())
        let finalContent = RecordingStudyBrowser.content(
            recordings: manager.recordings,
            path: RecordingStudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"])
        )

        #expect(rootContent.folders.map(\.title) == ["课堂"])
        #expect(finalContent.recordings.map(\.id) == ["iphone-browser-update"])
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
        uploadStatus: String,
        studyFiling: StudyFilingPath? = nil
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
            tags: [],
            studyFiling: studyFiling
        )
    }
}
