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
            .pageSubtitle,
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

    @Test func lowPowerDisplayMinuteTextUsesCumulativeClockMinutes() {
        #expect(RecordingLowPowerDisplayPolicy.minuteText(elapsedSeconds: 7) == "00")
        #expect(RecordingLowPowerDisplayPolicy.minuteText(elapsedSeconds: 3 * 60 + 42) == "03")
        #expect(RecordingLowPowerDisplayPolicy.minuteText(elapsedSeconds: 37 * 60 + 24) == "37")
        #expect(RecordingLowPowerDisplayPolicy.minuteText(elapsedSeconds: 81 * 60 + 40) == "81")
    }

    @Test func lowPowerDisplayOnlyEntersForActiveForegroundRecording() {
        #expect(RecordingLowPowerDisplayPolicy.canEnter(
            state: .recording,
            isAppActive: true,
            isFilingOverlayPresented: false,
            hasBlockingPresentation: false
        ))
        #expect(!RecordingLowPowerDisplayPolicy.canEnter(
            state: .paused,
            isAppActive: true,
            isFilingOverlayPresented: false,
            hasBlockingPresentation: false
        ))
        #expect(!RecordingLowPowerDisplayPolicy.canEnter(
            state: .recording,
            isAppActive: false,
            isFilingOverlayPresented: false,
            hasBlockingPresentation: false
        ))
        #expect(!RecordingLowPowerDisplayPolicy.canEnter(
            state: .recording,
            isAppActive: true,
            isFilingOverlayPresented: true,
            hasBlockingPresentation: false
        ))
        #expect(!RecordingLowPowerDisplayPolicy.canEnter(
            state: .recording,
            isAppActive: true,
            isFilingOverlayPresented: false,
            hasBlockingPresentation: true
        ))
    }

    @Test func lowPowerElapsedRefreshDoesNotChangeRecordingManagerState() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let manager = RecordingManager(fileStore: store)

        manager.setLowPowerElapsedRefreshEnabled(true)

        #expect(manager.state == .idle)
    }

    @Test func recordingLiveActivityStateKeepsMinimalStatusText() {
        let recordingState = RecordingLiveActivityAttributes.ContentState(
            title: "课堂录音",
            elapsedMinutes: 81,
            isPaused: false,
            isSavingLocally: false
        )
        let savingState = RecordingLiveActivityAttributes.ContentState(
            title: "课堂录音",
            elapsedMinutes: 3,
            isPaused: false,
            isSavingLocally: true
        )

        #expect(recordingState.elapsedMinuteText == "81")
        #expect(recordingState.statusText == "录音中")
        #expect(savingState.elapsedMinuteText == "03")
        #expect(savingState.statusText == "本地保存中")
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

    @Test func studyFilingSelectionClearsDescendantLevels() {
        var draft = StudyFilingSelectionDraft(
            path: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "乘法")
        )

        draft.select(.subject, value: "高等数学")

        #expect(draft.type == "课堂")
        #expect(draft.subject == "高等数学")
        #expect(draft.chapter.isEmpty)
        #expect(draft.topic.isEmpty)

        draft.select(.type, value: "复习")

        #expect(draft.type == "复习")
        #expect(draft.subject.isEmpty)
        #expect(draft.chapter.isEmpty)
        #expect(draft.topic.isEmpty)
    }

    @Test func studyFilingCandidatesFilterByParentPath() {
        let first = StudyItemMetadata(
            recordingID: "candidate-filter-01",
            title: "A",
            createdAt: Date(timeIntervalSince1970: 10),
            duration: 12,
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵")
        )
        let second = StudyItemMetadata(
            recordingID: "candidate-filter-02",
            title: "B",
            createdAt: Date(timeIntervalSince1970: 20),
            duration: 12,
            studyFiling: StudyFilingPath(type: "复习", subject: "高等数学", chapter: "积分")
        )
        let folder = StudyFolderMetadata(
            name: "离散数学",
            level: .subject,
            path: StudyFilingPath(type: "课堂", subject: "离散数学")
        )

        let subjects = StudyFilingCandidateResolver.candidates(
            for: .subject,
            current: StudyFilingPath(type: "课堂"),
            items: [first, second],
            folders: [folder]
        )

        #expect(Set(subjects) == Set(["线性代数", "离散数学"]))
        #expect(!subjects.contains("高等数学"))
    }

    @Test func studyLibraryStoreWritesRecordingBundleAndFolderIndex() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(
            id: "study-store-recording",
            title: "矩阵乘法",
            store: audioStore,
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)

        let item = try studyStore.upsertRecordingMetadata(metadata)
        let content = StudyLibraryBrowser.content(
            items: studyStore.allStudyItems,
            folders: studyStore.allStudyFolders,
            path: StudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"])
        )

        #expect(item.kind == .recordingBundle)
        #expect(content.items.map(\.itemID) == [item.itemID])
        #expect(studyStore.allStudyFolders.contains { folder in
            folder.itemIDs.contains(item.itemID)
        })
    }

    @Test func studyLibraryStoreRepairsMissingFolderItemReferences() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let item = StudyItemMetadata(
            kind: .standaloneNote,
            title: "独立笔记",
            createdAt: Date(timeIntervalSince1970: 30),
            filing: StudyFilingPath(type: "课堂")
        )
        try studyStore.save(item)
        let folder = StudyFolderMetadata(
            name: "课堂",
            level: .type,
            path: StudyFilingPath(type: "课堂"),
            itemIDs: ["missing-item-id", item.itemID]
        )
        try studyStore.save(folder)

        studyStore.refresh()

        let repaired = try #require(studyStore.allStudyFolders.first { $0.folderID == folder.folderID })
        #expect(repaired.itemIDs == [item.itemID])
    }

    @Test func studyLibraryStoreReadsLegacyReceiveJSONWithMissingFields() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let receiveDirectory = rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .appendingPathComponent("2026-05-21", isDirectory: true)
            .appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: receiveDirectory, withIntermediateDirectories: true)
        let receiveURL = receiveDirectory.appendingPathComponent("receive.json", isDirectory: false)
        let receiveObject: [String: Any] = [
            "recordingID": "legacy-receive",
            "normalizedTitle": "旧接收录音",
            "createdAt": "2026-05-21T00:00:00Z",
            "duration": 42,
            "studyFiling": [
                "type": "课堂",
                "subject": "物理"
            ],
            "audioRelativePath": "audio/inbox/2026-05-21/legacy/audio.m4a"
        ]
        try JSONSerialization.data(withJSONObject: receiveObject, options: [.prettyPrinted])
            .write(to: receiveURL, options: .atomic)

        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)

        #expect(studyStore.allStudyItems.first?.recordingID == "legacy-receive")
        #expect(studyStore.allStudyItems.first?.filing.subject == "物理")
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

    @Test func staleUploadingStatusRecoversToFailedOnRecordingManagerLoad() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "stale-uploading-01", title: "卡住上传", store: store, uploadStatus: "uploading")

        let manager = RecordingManager(fileStore: store)

        #expect(manager.recordings.map(\.id) == ["stale-uploading-01"])
        #expect(manager.recordings.first?.uploadStatus == RecordingUploadStatus.failed.rawValue)
        #expect(try store.loadMetadata(id: "stale-uploading-01").uploadStatus == RecordingUploadStatus.failed.rawValue)
    }

    @Test func uploadJobStoreCreatesSavesAndLoadsJobWithVersion() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "upload-job-01", title: "任务账本", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 100)

        let job = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now)
        let loadedJob = try #require(try jobStore.loadJob(recordingID: metadata.id))
        let ledgerData = try Data(contentsOf: jobStore.ledgerURL())
        let ledgerJSON = try #require(JSONSerialization.jsonObject(with: ledgerData) as? [String: Any])

        #expect(job.recordingID == metadata.id)
        #expect(loadedJob.recordingID == metadata.id)
        #expect(loadedJob.metadataStage == .pending)
        #expect(loadedJob.audioStage == .pending)
        #expect(ledgerJSON["version"] as? Int == RecordingUploadJobLedger.currentVersion)
    }

    @Test func uploadJobStoreAtomicUpdatePreservesSingleActiveJob() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "upload-job-single", title: "唯一任务", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 100)

        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now)
        _ = try jobStore.markAttemptStarted(recordingID: metadata.id, now: now.addingTimeInterval(1))
        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now.addingTimeInterval(2))
        let jobs = try jobStore.loadJobs()
        let loadedJob = try #require(jobs.first)

        #expect(jobs.count == 1)
        #expect(loadedJob.recordingID == metadata.id)
        #expect(loadedJob.attemptCount == 1)
        #expect(loadedJob.lastAttemptAt == now.addingTimeInterval(1))
    }

    @Test func corruptedUploadLedgerDoesNotCrashOrDeleteRecordings() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "upload-job-corrupt", title: "损坏账本", store: store)
        let audioURL = try store.audioURL(for: metadata)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        try "not-json".data(using: .utf8)?.write(to: jobStore.ledgerURL(), options: .atomic)

        let jobs = try jobStore.loadJobs()

        #expect(jobs.isEmpty)
        #expect(jobStore.lastReadError?.contains("upload ledger read failed") == true)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(try store.loadMetadata(id: metadata.id).id == metadata.id)
    }

    @Test func uploadJobLedgerDoesNotPersistSharedSecret() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "upload-job-secret", title: "敏感信息", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let snapshot = makePairedMacSnapshot()

        _ = try jobStore.ensureJob(for: metadata, settings: snapshot, now: Date(timeIntervalSince1970: 100))
        let ledgerText = try String(contentsOf: jobStore.ledgerURL(), encoding: .utf8)

        #expect(!ledgerText.contains(snapshot.sharedSecretBase64URL))
        #expect(!ledgerText.contains("sharedSecret"))
        #expect(!ledgerText.contains("HMAC"))
        #expect(!ledgerText.contains("certificate"))
    }

    @Test func retryPolicyBackoffGrowsAndCaps() {
        let policy = RecordingUploadRetryPolicy.standard

        #expect(policy.delay(forAttemptCount: 1) == 5)
        #expect(policy.delay(forAttemptCount: 2) == 30)
        #expect(policy.delay(forAttemptCount: 3) == 120)
        #expect(policy.delay(forAttemptCount: 10) == 600)
    }

    @Test func retryQueueEligibilityAndDrainOnlyProcessesEligibleRetryableJobs() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 1_000)
        let eligibleMetadata = try saveRecording(id: "retry-eligible", title: "可重试", store: store)
        let futureMetadata = try saveRecording(id: "retry-future", title: "稍后重试", store: store)
        let fatalMetadata = try saveRecording(id: "retry-fatal", title: "致命失败", store: store)
        let succeededMetadata = try saveRecording(id: "retry-succeeded", title: "已成功", store: store)

        var eligibleJob = RecordingUploadJob.make(metadata: eligibleMetadata, settings: makePairedMacSnapshot(), now: now)
        eligibleJob.overallState = .retryableFailed
        eligibleJob.audioStage = .failed
        eligibleJob.nextRetryAfter = now
        try jobStore.saveJob(eligibleJob)

        var futureJob = RecordingUploadJob.make(metadata: futureMetadata, settings: makePairedMacSnapshot(), now: now)
        futureJob.overallState = .retryableFailed
        futureJob.audioStage = .failed
        futureJob.nextRetryAfter = now.addingTimeInterval(30)
        try jobStore.saveJob(futureJob)

        var fatalJob = RecordingUploadJob.make(metadata: fatalMetadata, settings: makePairedMacSnapshot(), now: now)
        fatalJob.overallState = .fatalFailed
        fatalJob.isFatal = true
        fatalJob.metadataStage = .failed
        try jobStore.saveJob(fatalJob)

        var succeededJob = RecordingUploadJob.make(metadata: succeededMetadata, settings: makePairedMacSnapshot(), now: now)
        succeededJob.overallState = .succeeded
        succeededJob.metadataStage = .succeeded
        succeededJob.audioStage = .succeeded
        try jobStore.saveJob(succeededJob)

        let queue = RecordingUploadQueue(jobStore: jobStore, retryPolicy: .standard)
        var drainedIDs: [String] = []
        let drainedJobs = try await queue.drainEligibleJobs(now: now) { job in
            drainedIDs.append(job.recordingID)
        }

        #expect(try queue.retryableJobs(now: now).map(\.recordingID).sorted() == ["retry-eligible", "retry-future"])
        #expect(try queue.eligibleRetryableJobs(now: now).map(\.recordingID) == ["retry-eligible"])
        #expect(drainedJobs.map(\.recordingID) == ["retry-eligible"])
        #expect(drainedIDs == ["retry-eligible"])
        #expect(!queue.isEligible(futureJob, now: now))
        #expect(queue.isEligible(futureJob, now: now.addingTimeInterval(30)))
        #expect(!queue.isEligible(fatalJob, now: now))
        #expect(!queue.isEligible(succeededJob, now: now))
    }

    @Test func newUploadCreatesJobAndMarksSucceededWithMetadataUploaded() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "job-success-new", title: "新上传", store: store)
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let fakeClient = FakeRecordingUploadClient(
            result: .success(RecordingUploadResult(
                recordingID: metadata.id,
                metadataFileName: "metadata.json",
                audioFileName: "audio.m4a",
                metadataDisposition: "acceptedNew",
                audioDisposition: "acceptedNew"
            )),
            events: [
                .metadataStarted,
                .metadataSucceeded(disposition: "acceptedNew"),
                .audioStarted,
                .audioSucceeded(disposition: "acceptedNew")
            ]
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .uploaded)
        #expect(job.overallState == .succeeded)
        #expect(job.metadataStage == .succeeded)
        #expect(job.audioStage == .succeeded)
        #expect(job.metadataDisposition == .acceptedNew)
        #expect(job.audioDisposition == .acceptedNew)
        #expect(job.attemptCount == 1)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.uploaded.rawValue)
    }

    @Test func metadataAcceptedExistingAndAudioSuccessMarksLocalRecordingUploaded() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "retry-after-metadata-only", title: "重试录音", store: store)
        let manager = RecordingManager(fileStore: store)
        let fakeClient = FakeRecordingUploadClient(result: .success(RecordingUploadResult(
            recordingID: metadata.id,
            metadataFileName: "metadata.json",
            audioFileName: "audio.m4a",
            metadataDisposition: "acceptedExisting",
            audioDisposition: "acceptedNew"
        )), events: [
            .metadataStarted,
            .metadataSucceeded(disposition: "acceptedExisting"),
            .audioStarted,
            .audioSucceeded(disposition: "acceptedNew")
        ])
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(
            metadata: metadata,
            settings: makePairedMacSnapshot(),
            recordingManager: manager
        )
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .uploaded)
        #expect(job.overallState == .succeeded)
        #expect(job.metadataDisposition == .acceptedExisting)
        #expect(job.audioDisposition == .acceptedNew)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.uploaded.rawValue)
        #expect(coordinator.errorMessage(for: metadata) == nil)
        #expect(fakeClient.lastMetadata?.id == metadata.id)
    }

    @Test func metadataSuccessAndAudioTemporaryFailureLeavesRetryableJob() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "audio-temp-failure", title: "音频临时失败", store: store)
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let fakeClient = FakeRecordingUploadClient(
            result: .failure(RecordingUploadError.audioUploadFailed("network timeout")),
            events: [
                .metadataStarted,
                .metadataSucceeded(disposition: "acceptedNew"),
                .audioStarted
            ]
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .failed)
        #expect(job.overallState == .retryableFailed)
        #expect(job.metadataStage == .succeeded)
        #expect(job.audioStage == .failed)
        #expect(job.metadataDisposition == .acceptedNew)
        #expect(job.attemptCount == 1)
        #expect(job.nextRetryAfter != nil)
        #expect(job.lastErrorCode == "audio_upload_failed")
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.failed.rawValue)
    }

    @Test func retryAfterMetadataSuccessAndAudioFailureCanCompleteUpload() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "audio-retry-complete", title: "重试完成", store: store)
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let failingClient = FakeRecordingUploadClient(
            result: .failure(RecordingUploadError.audioUploadFailed("network timeout")),
            events: [
                .metadataStarted,
                .metadataSucceeded(disposition: "acceptedNew"),
                .audioStarted
            ]
        )
        let firstCoordinator = RecordingUploadCoordinator(uploadClient: failingClient, jobStore: jobStore)

        _ = await firstCoordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)

        let retryClient = FakeRecordingUploadClient(
            result: .success(RecordingUploadResult(
                recordingID: metadata.id,
                metadataFileName: "metadata.json",
                audioFileName: "audio.m4a",
                metadataDisposition: "acceptedExisting",
                audioDisposition: "acceptedNew"
            )),
            events: [
                .metadataStarted,
                .metadataSucceeded(disposition: "acceptedExisting"),
                .audioStarted,
                .audioSucceeded(disposition: "acceptedNew")
            ]
        )
        let retryCoordinator = RecordingUploadCoordinator(uploadClient: retryClient, jobStore: jobStore)
        let failedMetadata = try store.loadMetadata(id: metadata.id)

        let status = await retryCoordinator.uploadAndWait(metadata: failedMetadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .uploaded)
        #expect(job.overallState == .succeeded)
        #expect(job.metadataStage == .succeeded)
        #expect(job.audioStage == .succeeded)
        #expect(job.attemptCount == 2)
        #expect(job.metadataDisposition == .acceptedExisting)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.uploaded.rawValue)
    }

    @Test func metadataConflictMarksLocalRecordingFailedWithReadableError() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "metadata-conflict-iphone", title: "冲突录音", store: store)
        let manager = RecordingManager(fileStore: store)
        let fakeClient = FakeRecordingUploadClient(result: .failure(
            RecordingUploadError.metadataUploadFailed("recording_metadata_conflict")
        ), events: [.metadataStarted])
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(
            metadata: metadata,
            settings: makePairedMacSnapshot(),
            recordingManager: manager
        )
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))
        let queue = RecordingUploadQueue(jobStore: jobStore, retryPolicy: .standard)

        #expect(status == .failed)
        #expect(job.overallState == .fatalFailed)
        #expect(job.metadataStage == .failed)
        #expect(job.isFatal)
        #expect(try queue.retryableJobs().isEmpty)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.failed.rawValue)
        #expect(coordinator.errorMessage(for: metadata)?.contains("recording_metadata_conflict") == true)
    }

    @Test func audioConflictMarksLocalRecordingFailedWithReadableError() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "audio-conflict-iphone", title: "音频冲突", store: store)
        let manager = RecordingManager(fileStore: store)
        let fakeClient = FakeRecordingUploadClient(result: .failure(
            RecordingUploadError.audioUploadFailed("recording_audio_conflict")
        ), events: [
            .metadataStarted,
            .metadataSucceeded(disposition: "acceptedNew"),
            .audioStarted
        ])
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(
            metadata: metadata,
            settings: makePairedMacSnapshot(),
            recordingManager: manager
        )
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))
        let queue = RecordingUploadQueue(jobStore: jobStore, retryPolicy: .standard)

        #expect(status == .failed)
        #expect(job.overallState == .fatalFailed)
        #expect(job.metadataStage == .succeeded)
        #expect(job.audioStage == .failed)
        #expect(job.isFatal)
        #expect(try queue.retryableJobs().isEmpty)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.failed.rawValue)
        #expect(coordinator.errorMessage(for: metadata)?.contains("recording_audio_conflict") == true)
    }

    @Test func staleInProgressUploadJobRecoversOnRecordingManagerLoad() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "stale-job-recovery", title: "中断任务", store: store, uploadStatus: "uploading")
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 100)
        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now)
        _ = try jobStore.markAttemptStarted(recordingID: metadata.id, now: now.addingTimeInterval(1))
        _ = try jobStore.applyProgress(recordingID: metadata.id, event: .metadataStarted, now: now.addingTimeInterval(2))

        let manager = RecordingManager(fileStore: store)
        let recoveredJob = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(manager.recordings.first?.uploadStatus == RecordingUploadStatus.failed.rawValue)
        #expect(recoveredJob.overallState == .retryableFailed)
        #expect(recoveredJob.metadataStage == .failed)
        #expect(recoveredJob.lastErrorCode == "upload_interrupted")
        #expect(recoveredJob.nextRetryAfter != nil)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.failed.rawValue)
    }

    @Test func resumableUploadProgressPersistsInLedger() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-ledger-progress", title: "进度任务", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 1_000)
        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now)

        let job = try jobStore.applyProgress(
            recordingID: metadata.id,
            event: .audioResumableSessionStarted(
                sessionID: "session-1",
                totalBytes: 10,
                chunkSize: 4,
                totalSHA256: "abc123",
                confirmedBytes: 4
            ),
            now: now.addingTimeInterval(1)
        )
        let loadedJob = try #require(try jobStore.loadJob(recordingID: metadata.id))
        let ledgerData = try Data(contentsOf: jobStore.ledgerURL())
        let ledgerText = String(data: ledgerData, encoding: .utf8) ?? ""

        #expect(job.uploadMode == .resumableChunks)
        #expect(loadedJob.resumableSessionID == "session-1")
        #expect(loadedJob.audioConfirmedBytes == 4)
        #expect(loadedJob.audioTotalBytes == 10)
        #expect(loadedJob.audioChunkCount == 3)
        #expect(loadedJob.audioCompletedChunkCount == 1)
        #expect(loadedJob.currentProgressFraction == 0.4)
        #expect(ledgerText.contains(#""version" : 2"#) || ledgerText.contains(#""version":2"#))
        #expect(!ledgerText.localizedCaseInsensitiveContains("sharedSecret"))
        #expect(!ledgerText.localizedCaseInsensitiveContains("hmac"))
    }

    @Test func resumableRetryableFailurePreservesSessionAndConfirmedBytes() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-failure-preserve", title: "失败保留", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 2_000)
        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now)
        _ = try jobStore.applyProgress(
            recordingID: metadata.id,
            event: .audioResumableSessionStarted(
                sessionID: "session-preserve",
                totalBytes: 12,
                chunkSize: 4,
                totalSHA256: "sha",
                confirmedBytes: 8
            ),
            now: now
        )

        let failed = try jobStore.markFailure(
            recordingID: metadata.id,
            classification: RecordingUploadFailureClassification(code: "network_failed", message: "network lost", isFatal: false),
            retryPolicy: .standard,
            now: now.addingTimeInterval(1)
        )

        #expect(failed.overallState == .retryableFailed)
        #expect(failed.resumableSessionID == "session-preserve")
        #expect(failed.audioConfirmedBytes == 8)
        #expect(failed.resumableState == .retryableFailed)
        #expect(failed.nextRetryAfter != nil)
    }

    @Test func staleResumableInProgressJobRecoversToPausedRetryable() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "stale-resumable-job", title: "续传中断", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 3_000)
        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now)
        _ = try jobStore.markAttemptStarted(recordingID: metadata.id, now: now)
        _ = try jobStore.applyProgress(
            recordingID: metadata.id,
            event: .audioResumableSessionStarted(
                sessionID: "session-stale",
                totalBytes: 20,
                chunkSize: 5,
                totalSHA256: "sha",
                confirmedBytes: 10
            ),
            now: now
        )

        let recovered = try #require(try jobStore.recoverStaleInProgressJobs(now: now.addingTimeInterval(10)).first)

        #expect(recovered.overallState == .retryableFailed)
        #expect(recovered.audioStage == .failed)
        #expect(recovered.resumableState == .paused)
        #expect(recovered.resumableSessionID == "session-stale")
        #expect(recovered.audioConfirmedBytes == 10)
    }

    @Test func smallFileBelowThresholdUsesExistingSingleRequestUpload() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "single-request-small", title: "小文件", store: store, audioData: Data("small".utf8))
        let transport = FakeRecordingSecureUploadTransport()
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 64,
            resumableChunkSize: 4
        )

        let result = try await client.uploadRecording(metadata: metadata, settings: makePairedMacSnapshot())

        #expect(result.audioDisposition == "acceptedNew")
        #expect(transport.metadataUploadCount == 1)
        #expect(transport.singleFileUploadCount == 1)
        #expect(transport.resumableStartCount == 0)
        #expect(transport.chunkOffsets.isEmpty)
    }

    @Test func largeFileAboveThresholdUsesResumableStartChunksFinalize() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-large", title: "大文件", store: store, audioData: Data("abcdefghi".utf8))
        let transport = FakeRecordingSecureUploadTransport()
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 4,
            resumableChunkSize: 3
        )
        var events: [RecordingUploadProgressEvent] = []

        let result = try await client.uploadRecording(
            metadata: metadata,
            settings: makePairedMacSnapshot(),
            progress: { event in events.append(event) }
        )

        #expect(result.audioDisposition == "acceptedNew")
        #expect(transport.metadataUploadCount == 1)
        #expect(transport.singleFileUploadCount == 0)
        #expect(transport.resumableStartCount == 1)
        #expect(transport.chunkOffsets == [0, 3, 6])
        #expect(transport.finalizeCount == 1)
        #expect(events.contains(.audioResumableProgress(sessionID: "session-1", confirmedBytes: 9, totalBytes: 9, nextOffset: 9)))
    }

    @Test func resumableNetworkFailurePreservesProgressInCoordinatorLedger() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-network-failure", title: "网络中断", store: store, audioData: Data("abcdefghi".utf8))
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let transport = FakeRecordingSecureUploadTransport()
        transport.failChunkAtOffset = 3
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 4,
            resumableChunkSize: 3
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: client, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))
        let storedMetadata = try store.loadMetadata(id: metadata.id)

        #expect(status == .failed)
        #expect(job.overallState == .retryableFailed)
        #expect(job.metadataStage == .succeeded)
        #expect(job.audioStage == .failed)
        #expect(job.resumableSessionID == "session-1")
        #expect(job.audioConfirmedBytes == 3)
        #expect(storedMetadata.uploadStatus == RecordingUploadStatus.failed.rawValue)
        #expect(storedMetadata.uploadProgressConfirmedBytes == 3)
    }

    @Test func resumableRetryQueriesStatusAndResumesFromMacConfirmedOffset() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-retry-status", title: "续传恢复", store: store, audioData: Data("abcdefghi".utf8))
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 4_000)
        var job = RecordingUploadJob.make(metadata: metadata, settings: makePairedMacSnapshot(), now: now)
        job.metadataStage = .succeeded
        job.metadataDisposition = .acceptedNew
        job.audioStage = .failed
        job.overallState = .retryableFailed
        job.uploadMode = .resumableChunks
        job.resumableState = .retryableFailed
        job.resumableSessionID = "session-1"
        job.audioConfirmedBytes = 3
        job.audioTotalBytes = 9
        job.audioChunkSize = 3
        job.audioTotalSHA256 = try SecureUploadUtilities.sha256Hex(fileURL: store.audioURL(for: metadata))
        try jobStore.saveJob(job)
        let transport = FakeRecordingSecureUploadTransport()
        transport.statusConfirmedBytes = 6
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 4,
            resumableChunkSize: 3
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: client, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let completedJob = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .uploaded)
        #expect(transport.statusCount == 1)
        #expect(transport.metadataUploadCount == 0)
        #expect(transport.chunkOffsets == [6])
        #expect(completedJob.overallState == .succeeded)
        #expect(completedJob.audioConfirmedBytes == 9)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.uploaded.rawValue)
    }

    @Test func resumableFinalizeAcceptedExistingMarksUploaded() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-finalize-existing", title: "重复完成", store: store, audioData: Data("abcdefghi".utf8))
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let transport = FakeRecordingSecureUploadTransport()
        transport.finalizeDisposition = "acceptedExisting"
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 4,
            resumableChunkSize: 3
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: client, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let completedJob = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .uploaded)
        #expect(completedJob.audioDisposition == .acceptedExisting)
        #expect(completedJob.currentProgressFraction == 1)
    }

    @Test func resumableAudioConflictMarksFatalFailed() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-audio-conflict", title: "续传冲突", store: store, audioData: Data("abcdefghi".utf8))
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let transport = FakeRecordingSecureUploadTransport()
        transport.chunkErrorAtOffset = (3, RecordingUploadError.audioUploadFailed("recording_audio_conflict"))
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 4,
            resumableChunkSize: 3
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: client, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))
        let queue = RecordingUploadQueue(jobStore: jobStore, retryPolicy: .standard)

        #expect(status == .failed)
        #expect(job.overallState == .fatalFailed)
        #expect(job.resumableState == .fatalFailed)
        #expect(job.audioStage == .failed)
        #expect(job.audioConfirmedBytes == 3)
        #expect(try queue.retryableJobs().isEmpty)
    }

    @Test func secureUploadClientAudioMainPathUsesFileUploadNotWholeAudioData() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Rokurics", isDirectory: true)
            .appendingPathComponent("SecureMacUploadClient.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("upload(for: request, fromFile: fileURL)"))
        #expect(!source.contains("Data(contentsOf: audioURL)"))
        #expect(!source.contains("Data(contentsOf: fileURL)"))
    }

    @Test func doubleTapRecordingIconResolvesMoveToTrashIntent() {
        #expect(RecordingRowIconInteraction.intent(for: .singleTap) == .none)
        #expect(RecordingRowIconInteraction.intent(for: .doubleTap) == .moveToTrash)
        #expect(RecordingRowIconInteraction.deletionTapCount == 2)
    }

    @Test func studyItemMetadataMissingSyncFieldsDefaultsSafely() throws {
        let metadata = StudyItemMetadata(
            recordingID: "legacy-sync-fields",
            title: "旧 metadata",
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 1,
            studyFiling: StudyFilingPath(type: "课堂")
        )
        var object = try #require(JSONSerialization.jsonObject(with: try Self.studyEncoder.encode(metadata)) as? [String: Any])
        object.removeValue(forKey: "isTrashed")
        object.removeValue(forKey: "trashedAt")
        object.removeValue(forKey: "modifiedByDeviceID")
        object.removeValue(forKey: "syncConflictStatus")
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try Self.studyDecoder.decode(StudyItemMetadata.self, from: data)

        #expect(decoded.isTrashed == false)
        #expect(decoded.trashedAt == nil)
        #expect(decoded.modifiedByDeviceID == nil)
        #expect(decoded.syncConflictStatus == nil)
    }

    @Test func studyLibraryManifestFiltersSensitiveCustomProperties() {
        let item = StudyItemMetadata(
            recordingID: "manifest-sensitive",
            title: "敏感字段",
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 1,
            customProperties: [
                "apiKey": "should-not-sync",
                "rawProviderResponse": "{}",
                "safePreview": "保留"
            ]
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-01",
            generatedAt: Date(timeIntervalSince1970: 2),
            items: [item.syncSanitized(modifiedByDeviceID: "iphone-01")],
            folders: []
        )

        #expect(manifest.hasValidChecksum)
        #expect(manifest.items.first?.customProperties == ["safePreview": "保留"])
    }

    @Test func applyingNewerMacMetadataUpdatesIPhoneMetadataWithoutDeletingAudio() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let recording = try saveRecording(id: "sync-lww-iphone", title: "iPhone 标题", store: audioStore)
        let audioURL = try audioStore.audioURL(for: recording)
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let baseItem = try #require(studyStore.item(recordingID: recording.id))
        var macItem = baseItem
        macItem.title = "Mac 标题"
        macItem.transcriptionStatus = "transcribed"
        macItem.noteStatus = "generated"
        macItem.updatedAt = baseItem.updatedAt.addingTimeInterval(60)
        macItem.modifiedByDeviceID = "mac-01"
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "mac-01",
            generatedAt: macItem.updatedAt.addingTimeInterval(1),
            items: [macItem],
            folders: []
        )

        let result = try studyStore.applySyncManifest(manifest, localDeviceID: "iphone-01")
        let updatedRecording = try audioStore.loadMetadata(id: recording.id)

        #expect(result.appliedItemCount == 1)
        #expect(updatedRecording.title == "Mac 标题")
        #expect(updatedRecording.transcriptionStatus == "transcribed")
        #expect(updatedRecording.noteStatus == "generated")
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test func applyingTrashTombstoneDoesNotDeleteRealFiles() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let recording = try saveRecording(id: "sync-trash-safe", title: "保留文件", store: audioStore)
        let audioURL = try audioStore.audioURL(for: recording)
        let metadataURL = try audioStore.makeMetadataURL(id: recording.id)
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let item = try #require(studyStore.item(recordingID: recording.id))
        let tombstoneUpdatedAt = item.updatedAt.addingTimeInterval(60)
        let tombstone = StudyLibrarySyncTombstone(
            id: "item:\(item.itemID)",
            entityKind: .item,
            entityID: item.itemID,
            operation: .trash,
            updatedAt: tombstoneUpdatedAt,
            modifiedByDeviceID: "mac-01"
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "mac-01",
            generatedAt: tombstoneUpdatedAt.addingTimeInterval(1),
            items: [],
            folders: [],
            tombstones: [tombstone]
        )

        let result = try studyStore.applySyncManifest(manifest, localDeviceID: "iphone-01")
        let updatedRecording = try audioStore.loadMetadata(id: recording.id)

        #expect(result.tombstoneCount == 1)
        #expect(updatedRecording.isDeleted)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(FileManager.default.fileExists(atPath: metadataURL.path))
    }

    @Test func iphoneSyncManifestCarriesPendingUploadsForUnuploadedRecordings() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "pending-upload-01", title: "待上传", store: audioStore, uploadStatus: "localOnly")
        _ = try saveRecording(id: "pending-upload-02", title: "已上传", store: audioStore, uploadStatus: "uploaded")
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)

        let manifest = studyStore.makeSyncManifest(deviceID: "mac-01", generatedAt: Date(timeIntervalSince1970: 4))

        #expect(manifest.hasValidChecksum)
        #expect(manifest.pendingUploads.map(\.recordingID) == ["pending-upload-01"])
        #expect(manifest.pendingUploads.first?.localAudioRelativePath.hasSuffix(".m4a") == true)
    }

    @Test func studyLibrarySyncStateMissingPendingUploadsDefaultsSafely() throws {
        let state = StudyLibrarySyncState(
            deviceID: "mac-01",
            pendingLocalChanges: 1,
            failedChanges: 1,
            lastError: "old"
        )
        var object = try #require(JSONSerialization.jsonObject(with: try Self.studyEncoder.encode(state)) as? [String: Any])
        object.removeValue(forKey: "pendingUploads")
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try Self.studyDecoder.decode(StudyLibrarySyncState.self, from: data)

        #expect(decoded.pendingUploads == 0)
        #expect(decoded.pendingLocalChanges == 1)
        #expect(decoded.lastKnownRemoteCommitID == nil)
    }

    @Test func studyLibrarySyncStateRecordsRemoteCommitIDAfterPullAndPush() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(rootURL: rootURL)

        store.recordPull(
            deviceID: "mac-01",
            remoteManifestHash: "remote-hash-1",
            remoteCommitID: "commit-pull",
            at: Date(timeIntervalSince1970: 10)
        )
        #expect(store.state.lastKnownRemoteCommitID == "commit-pull")
        #expect(store.state.lastRemoteManifestHash == "remote-hash-1")

        store.recordPush(
            deviceID: "mac-01",
            remoteManifestHash: "remote-hash-2",
            remoteCommitID: "commit-push",
            pendingUploads: 0,
            at: Date(timeIntervalSince1970: 20)
        )

        let reloaded = StudyLibrarySyncStateStore(rootURL: rootURL)
        #expect(reloaded.state.lastKnownRemoteCommitID == "commit-push")
        #expect(reloaded.state.lastRemoteManifestHash == "remote-hash-2")
        #expect(reloaded.state.pendingLocalChanges == 0)
        #expect(reloaded.state.failedChanges == 0)
    }

    @Test func studyLibrarySyncStateClearsSuccessfulPendingUploadsAndRetainsFailures() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(rootURL: rootURL)

        store.recordPendingUploads(
            deviceID: "mac-01",
            pendingUploads: 2,
            failedChanges: 1,
            error: "upload_failed"
        )

        #expect(store.state.pendingUploads == 2)
        #expect(store.state.failedChanges == 1)
        #expect(store.state.lastError == "upload_failed")

        store.recordPush(
            deviceID: "mac-01",
            remoteManifestHash: "remote-hash",
            remoteCommitID: "commit-after-upload",
            pendingUploads: 0,
            at: Date(timeIntervalSince1970: 30)
        )

        #expect(store.state.pendingUploads == 0)
        #expect(store.state.failedChanges == 0)
        #expect(store.state.lastError == nil)
        #expect(store.state.lastKnownRemoteCommitID == "commit-after-upload")
    }

    @Test func studyLibrarySyncFailureRetainsPendingChangesAndUploads() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(rootURL: rootURL)

        store.recordFailure(
            deviceID: "mac-01",
            error: "sync_failed",
            failedChanges: 3,
            pendingUploads: 2
        )

        let reloaded = StudyLibrarySyncStateStore(rootURL: rootURL)
        #expect(reloaded.state.pendingLocalChanges == 3)
        #expect(reloaded.state.failedChanges == 3)
        #expect(reloaded.state.pendingUploads == 2)
        #expect(reloaded.state.lastError == "sync_failed")
    }

    @Test func gitBackedStudySyncRuntimeDefaultsToDisabled() {
        #expect(!StudyLibrarySyncRuntimeConfiguration.default.gitBackedSyncEnabled)
        #expect(!StudyLibrarySyncRuntimeConfiguration.disabled.gitBackedSyncEnabled)
        #expect(StudyLibrarySyncRuntimeConfiguration.disabledReason == "Git-backed study sync is disabled")
    }

    @Test func disabledSyncCoordinatorDoesNotStartAutomationOrClearPendingState() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        syncStateStore.replace(StudyLibrarySyncState(
            deviceID: "mac-disabled",
            pendingLocalChanges: 5,
            pendingUploads: 2,
            failedChanges: 1,
            lastError: "previous_failure"
        ))
        let connectionProvider = FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot())
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: connectionProvider,
            studyLibraryStore: studyStore,
            statusStore: statusStore,
            syncStateStore: syncStateStore,
            runtimeConfiguration: .default,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )

        coordinator.startForegroundMonitoring()
        let manualResult = await coordinator.synchronizeNow()

        #expect(manualResult == nil)
        #expect(!coordinator.isAutomaticSyncMonitoringActive)
        #expect(coordinator.syncSummary.statusText == StudyLibrarySyncRuntimeConfiguration.disabledStatusText)
        #expect(coordinator.connectionStatus.lastSyncStatus == StudyLibrarySyncRuntimeConfiguration.disabledStatusText)
        #expect(syncStateStore.state.pendingLocalChanges == 5)
        #expect(syncStateStore.state.pendingUploads == 2)
        #expect(syncStateStore.state.failedChanges == 1)
        #expect(syncStateStore.state.lastError == "previous_failure")
        coordinator.stopMonitoring()
    }

    @Test func disabledGitBackedSyncDoesNotTurnOffSecureManualUploads() {
        #expect(!StudyLibrarySyncRuntimeConfiguration.default.gitBackedSyncEnabled)
        #expect(SecureMacUploadClient.isHTTPSUploadEnabled)
    }

    @Test func localNetworkInventoryEncodesWithoutAbsolutePathsOrSecrets() throws {
        let artifactID = LocalNetworkSyncArtifactID.make(
            kind: .transcriptMarkdown,
            ownerID: "recording-01",
            logicalPathToken: "transcripts/recording-01/transcript.md"
        )
        let inventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-01",
                deviceName: "Vita iPhone",
                platform: .iPhone,
                generatedAt: Date(timeIntervalSince1970: 1),
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            artifacts: [
                LocalNetworkSyncArtifactEntry(
                    artifactID: artifactID,
                    kind: .transcriptMarkdown,
                    ownerID: "recording-01",
                    checksum: "abc",
                    size: 12,
                    updatedAt: Date(timeIntervalSince1970: 2),
                    availability: .local,
                    logicalPathToken: "transcripts/recording-01/transcript.md"
                )
            ]
        )

        let data = try Self.studyEncoder.encode(inventory)
        let json = String(data: data, encoding: .utf8) ?? ""
        let decoded = try Self.studyDecoder.decode(LocalNetworkSyncInventory.self, from: data)

        #expect(decoded.inventoryHash == inventory.inventoryHash)
        #expect(!json.contains("/Users/"))
        #expect(!json.lowercased().contains("sharedsecret"))
        #expect(!json.lowercased().contains("hmac"))
    }

    @MainActor
    @Test func localNetworkInventoryBuilderIncludesVersionedRecordingStudyAndArtifactSchema() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "schema-recording-01", title: "Schema Recording", store: audioStore)
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let inventory = LocalNetworkSyncInventoryBuilder(
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore
        ).build(
            deviceID: "iphone-schema",
            deviceName: "Schema iPhone",
            lastKnownPeerRevision: "peer-revision",
            generatedAt: Date(timeIntervalSince1970: 4_000)
        )

        let recording = try #require(inventory.recordings.first { $0.recordingID == metadata.id })
        let studyItem = try #require(inventory.studyItems.first { $0.recordingID == metadata.id })
        let metadataArtifact = try #require(inventory.artifacts.first { $0.kind == .metadataJSON && $0.ownerID == metadata.id })
        let metadataObject = try #require(inventory.objects.first { $0.objectID == metadataArtifact.artifactID })
        let studyItemObject = try #require(inventory.objects.first { $0.objectID == "studyItem:\(studyItem.itemID)" })
        let encoded = String(data: try Self.studyEncoder.encode(inventory), encoding: .utf8) ?? ""

        #expect(inventory.schemaVersion == LocalNetworkSyncInventory.appSchemaVersion)
        #expect(inventory.sourceDeviceID == "iphone-schema")
        #expect(inventory.sourcePlatform == .iPhone)
        #expect(recording.title == metadata.title)
        #expect(recording.createdAt == metadata.createdAt)
        #expect(recording.tombstone == false)
        #expect(recording.audioAvailability == .local)
        #expect(recording.uploadStatus == metadata.uploadStatus)
        #expect(recording.transcriptionStatus == metadata.transcriptionStatus)
        #expect(recording.noteStatus == metadata.noteStatus)
        #expect(recording.sourceDeviceID == "iphone-schema")
        #expect(recording.artifactRefs?.contains(metadataArtifact.artifactID) == true)
        #expect(studyItem.path != nil)
        #expect(metadataArtifact.logicalPathToken == metadata.relativeMetadataPath)
        #expect(metadataArtifact.localAvailability == .local)
        #expect(metadataArtifact.autoDownloadAllowed == true)
        #expect(metadataObject.objectKind == .recordingMetadata)
        #expect(metadataObject.fileName == "metadata.json")
        #expect(metadataObject.sha256 == metadataArtifact.checksum)
        #expect(metadataObject.size == metadataArtifact.size)
        #expect(studyItemObject.objectKind == .studyItem)
        #expect(studyItemObject.displayTitle == studyItem.title)
        #expect(studyItemObject.updatedAt == studyItem.updatedAt)
        #expect(!encoded.contains(rootURL.path))
        #expect(!encoded.lowercased().contains("sharedsecret"))
        #expect(!encoded.lowercased().contains("hmac"))
    }

    @Test func artifactSanitizerRejectsTraversalAbsoluteAndEscapePaths() throws {
        #expect(throws: LocalNetworkSyncArtifactValidationError.pathTraversal) {
            try LocalNetworkSyncArtifactID.validateLogicalPathToken("transcripts/../secret.txt")
        }
        #expect(throws: LocalNetworkSyncArtifactValidationError.absolutePath) {
            try LocalNetworkSyncArtifactID.validateLogicalPathToken("/Users/vita/secret.txt")
        }
        #expect(throws: LocalNetworkSyncArtifactValidationError.invalidArtifactID) {
            try LocalNetworkSyncArtifactID.validate("../artifact")
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsArtifactEscapeTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let outsideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsOutside-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outsideURL) }
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        let symlinkURL = rootURL.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideURL)

        #expect(throws: LocalNetworkSyncArtifactValidationError.unsafeResolvedPath) {
            _ = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: "link/escape.md")
        }
    }

    @Test func localNetworkDiffPlannerSchedulesTranscriptDownloadButNotAudioDownload() {
        let generatedAt = Date(timeIntervalSince1970: 1)
        let local = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-01",
                deviceName: "iPhone",
                platform: .iPhone,
                generatedAt: generatedAt,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            )
        )
        let transcriptID = LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "recording-01", logicalPathToken: "transcripts/recording-01/transcript.md")
        let audioID = LocalNetworkSyncArtifactID.make(kind: .audio, ownerID: "recording-01", logicalPathToken: "audio/inbox/recording-01/audio.m4a")
        let peer = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: generatedAt,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            artifacts: [
                LocalNetworkSyncArtifactEntry(
                    artifactID: transcriptID,
                    kind: .transcriptMarkdown,
                    ownerID: "recording-01",
                    checksum: "tx",
                    size: 20,
                    updatedAt: generatedAt,
                    availability: .local,
                    logicalPathToken: "transcripts/recording-01/transcript.md"
                ),
                LocalNetworkSyncArtifactEntry(
                    artifactID: audioID,
                    kind: .audio,
                    ownerID: "recording-01",
                    checksum: nil,
                    size: 5,
                    updatedAt: generatedAt,
                    availability: .local,
                    logicalPathToken: "audio/inbox/recording-01/audio.m4a"
                )
            ]
        )

        let plan = LocalNetworkSyncDiffPlanner().plan(local: local, peer: peer, lastSuccessfulSyncAt: nil)

        #expect(plan.downloadArtifactActions.map(\.entityID).contains(transcriptID))
        #expect(!plan.downloadArtifactActions.map(\.entityID).contains(audioID))
        #expect(plan.noOps.contains { $0.entityID == audioID && $0.reason == "audio_auto_download_disabled" })
    }

    @Test func localNetworkDiffPlannerSchedulesExistingUploadWhenMacMissingIPhoneAudio() {
        let generatedAt = Date(timeIntervalSince1970: 1)
        let localRecording = LocalNetworkSyncRecordingEntry(
            recordingID: "recording-audio-01",
            metadataHash: "metadata-same",
            audioAvailable: true,
            audioChecksum: nil,
            audioSize: 5,
            uploadLedgerState: nil,
            receiveStatus: nil,
            processingStatus: nil,
            updatedAt: generatedAt,
            deleted: false,
            title: "iPhone audio",
            createdAt: generatedAt,
            tombstone: false,
            audioAvailability: .local,
            uploadStatus: "localOnly",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            sourceDeviceID: "iphone-01",
            artifactRefs: nil
        )
        let peerRecording = LocalNetworkSyncRecordingEntry(
            recordingID: "recording-audio-01",
            metadataHash: "metadata-same",
            audioAvailable: false,
            audioChecksum: nil,
            audioSize: nil,
            uploadLedgerState: nil,
            receiveStatus: "metadataReceived",
            processingStatus: "awaitingAudio",
            updatedAt: generatedAt,
            deleted: false,
            title: "iPhone audio",
            createdAt: generatedAt,
            tombstone: false,
            audioAvailability: .missing,
            uploadStatus: nil,
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            sourceDeviceID: nil,
            artifactRefs: nil
        )
        let local = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-01",
                deviceName: "iPhone",
                platform: .iPhone,
                generatedAt: generatedAt,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [localRecording]
        )
        let peer = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: generatedAt,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [peerRecording]
        )

        let plan = LocalNetworkSyncDiffPlanner().plan(local: local, peer: peer, lastSuccessfulSyncAt: nil)

        #expect(plan.uploadRecordingAudioActions.contains { $0.entityID == "recording-audio-01" && $0.reason == "peer_missing_audio_use_existing_upload" })
        #expect(plan.existingUploadActions == plan.uploadRecordingAudioActions)
    }

    @Test func localNetworkDiffPlannerMarksBothChangedConflictAndTombstoneWinner() {
        let lastSync = Date(timeIntervalSince1970: 100)
        let localFolder = LocalNetworkSyncFolderEntry(
            folderID: "folder-conflict",
            parentID: nil,
            path: "Course",
            name: "Local",
            colorToken: nil,
            updatedAt: Date(timeIntervalSince1970: 130),
            revisionHash: "local",
            deleted: false
        )
        let peerFolder = LocalNetworkSyncFolderEntry(
            folderID: "folder-conflict",
            parentID: nil,
            path: "Course",
            name: "Peer",
            colorToken: nil,
            updatedAt: Date(timeIntervalSince1970: 140),
            revisionHash: "peer",
            deleted: false
        )
        let localTombstoneVictim = LocalNetworkSyncFolderEntry(
            folderID: "folder-tombstone",
            parentID: nil,
            path: "Old",
            name: "Old",
            colorToken: nil,
            updatedAt: Date(timeIntervalSince1970: 10),
            revisionHash: "old-local",
            deleted: false
        )
        let peerTombstone = LocalNetworkSyncFolderEntry(
            folderID: "folder-tombstone",
            parentID: nil,
            path: "Old",
            name: "Old",
            colorToken: nil,
            updatedAt: Date(timeIntervalSince1970: 20),
            revisionHash: "old-peer-deleted",
            deleted: true
        )
        let local = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-01",
                deviceName: "iPhone",
                platform: .iPhone,
                generatedAt: lastSync,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            folders: [localFolder, localTombstoneVictim]
        )
        let peer = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: lastSync,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            folders: [peerFolder, peerTombstone]
        )

        let conflictPlan = LocalNetworkSyncDiffPlanner().plan(local: local, peer: peer, lastSuccessfulSyncAt: lastSync)
        let tombstonePlan = LocalNetworkSyncDiffPlanner().plan(local: local, peer: peer, lastSuccessfulSyncAt: nil)

        #expect(conflictPlan.conflictActions.contains { $0.entityID == "folder-conflict" && $0.reason == "both_changed_after_last_sync" })
        #expect(tombstonePlan.downloadMetadataActions.contains { $0.entityID == "folder-tombstone" && $0.reason == "peer_tombstone_wins" })
    }

    @Test func localNetworkSyncStateCorruptionDoesNotCrashOrDeleteRecordings() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "state-corruption-audio", title: "保留录音", store: audioStore)
        let syncURL = rootURL
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("local-network-sync-state.json", isDirectory: false)
        try FileManager.default.createDirectory(at: syncURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: syncURL)

        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL)

        #expect(stateStore.state == .empty)
        #expect(stateStore.lastError != nil)
        #expect(try audioStore.loadMetadata(id: "state-corruption-audio").id == "state-corruption-audio")
    }

    @Test func localNetworkSchedulerPreventsReentrantTicks() async {
        var tickCount = 0
        let scheduler = LocalNetworkSyncScheduler(interval: 0.01) { _ in
            tickCount += 1
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        async let first: Bool = scheduler.requestTick(trigger: "first")
        try? await Task.sleep(nanoseconds: 5_000_000)
        let second = await scheduler.requestTick(trigger: "second")
        let firstResult = await first

        #expect(firstResult)
        #expect(!second)
        #expect(tickCount == 1)
    }

    @Test func localNetworkSyncSchedulerAllowsTenThirtySixtySecondIntervals() {
        let ten = LocalNetworkSyncScheduler(interval: 10) { _ in }
        let thirty = LocalNetworkSyncScheduler(interval: 30) { _ in }
        let sixty = LocalNetworkSyncScheduler(interval: 60) { _ in }
        let fallback = LocalNetworkSyncScheduler(interval: 17) { _ in }

        #expect(ten.configuredInterval == 10)
        #expect(thirty.configuredInterval == 30)
        #expect(sixty.configuredInterval == 60)
        #expect(fallback.configuredInterval == 30)
    }

    @Test func localNetworkSyncStartGateRequiresActivePairedAndOnline() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let online = statusStore.markConnected(deviceID: snapshot.deviceID, displayName: "Mac")
        let offline = statusStore.markOffline(deviceID: snapshot.deviceID, displayName: "Mac", error: "offline")

        #expect(LocalNetworkSyncStartGate.canRun(isActive: true, snapshot: snapshot, status: online))
        #expect(!LocalNetworkSyncStartGate.canRun(isActive: false, snapshot: snapshot, status: online))
        #expect(!LocalNetworkSyncStartGate.canRun(isActive: true, snapshot: makeUnpairedMacSnapshot(), status: online))
        #expect(!LocalNetworkSyncStartGate.canRun(isActive: true, snapshot: snapshot, status: offline))
        #expect(!LocalNetworkSyncStartGate.canRun(isActive: true, snapshot: snapshot, status: nil))
        #expect(!LocalNetworkSyncStartGate.canRun(
            isActive: true,
            snapshot: snapshot,
            status: online,
            userConnectionIntent: .disconnectedByUser
        ))
    }

    @Test func heartbeatMonitorStartsPeriodicForegroundPing() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let client = FakeLocalNetworkHeartbeatClient()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: client,
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(
                heartbeatInterval: 0.01,
                requestTimeout: 0.01,
                missedHeartbeatLimit: 2,
                staleAfter: 0.05,
                disconnectedAfter: 0.1
            )
        )

        monitor.startForegroundMonitoring()
        try? await Task.sleep(nanoseconds: 35_000_000)
        monitor.suspend()

        #expect(client.requests.count >= 1)
        #expect(statusStore.status(for: makePairedMacSnapshot().deviceID)?.monitoringMode == .suspended)
    }

    @Test func heartbeatMonitorSuppressedWhenUserDoesNotWantConnection() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let client = FakeLocalNetworkHeartbeatClient()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let provider = FakeSecureMacConnectionSnapshotProvider(
            snapshot: snapshot,
            userConnectionIntent: .disconnectedByUser
        )
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: provider,
            client: client,
            statusStore: statusStore,
            diagnosticsStore: diagnosticsStore,
            configuration: LocalNetworkHeartbeatConfiguration(
                heartbeatInterval: 0.01,
                requestTimeout: 0.01,
                missedHeartbeatLimit: 2,
                staleAfter: 0.05,
                disconnectedAfter: 0.1
            )
        )

        let didStart = monitor.startForegroundMonitoring()
        try? await Task.sleep(nanoseconds: 20_000_000)

        let status = try #require(statusStore.status(for: snapshot.deviceID))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))
        #expect(!didStart)
        #expect(!monitor.isMonitoring)
        #expect(client.requests.isEmpty)
        #expect(status.lastErrorCode == "user_disconnected")
        #expect(phases.contains("heartbeatSuppressedBecauseUserDoesNotWantConnection"))
    }

    @Test func foregroundResumeStartsHeartbeatEvenWhenDisconnectedAndSendsImmediateProbe() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let client = FakeLocalNetworkHeartbeatClient()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        _ = statusStore.markOffline(deviceID: snapshot.deviceID, displayName: "Rokurics Mac", error: "previous_disconnect")
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot),
            client: client,
            statusStore: statusStore,
            diagnosticsStore: diagnosticsStore,
            configuration: LocalNetworkHeartbeatConfiguration(
                heartbeatInterval: 0.05,
                requestTimeout: 0.02,
                missedHeartbeatLimit: 3,
                staleAfter: 0.05,
                disconnectedAfter: 0.1
            )
        )

        let didStart = monitor.startForegroundMonitoring()
        try? await Task.sleep(nanoseconds: 30_000_000)
        monitor.suspend()

        let status = try #require(statusStore.status(for: snapshot.deviceID, now: Date()))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))
        #expect(didStart)
        #expect(client.requests.first?.sequenceNumber == 1)
        #expect(status.presenceState == .online)
        #expect(status.missedHeartbeatCount == 0)
        #expect(phases.contains("heartbeatMonitorResumeRequested"))
        #expect(phases.contains("heartbeatImmediateProbeStarted"))
        #expect(phases.contains("heartbeatImmediateProbeSucceeded"))
    }

    @Test func heartbeatMonitorDoesNotStartWithoutPairedDevice() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let client = FakeLocalNetworkHeartbeatClient()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makeUnpairedMacSnapshot()),
            client: client,
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(
                heartbeatInterval: 0.01,
                requestTimeout: 0.01,
                missedHeartbeatLimit: 2,
                staleAfter: 0.05,
                disconnectedAfter: 0.1
            )
        )

        let didStart = monitor.startForegroundMonitoring()
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(!didStart)
        #expect(!monitor.isMonitoring)
        #expect(client.requests.isEmpty)
        #expect(statusStore.latestStatus == nil)
    }

    @Test func pairingSuccessAllowsHeartbeatToStartAfterPreviouslyUnpairedState() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = FakeSecureMacConnectionSnapshotProvider(snapshot: makeUnpairedMacSnapshot())
        let client = FakeLocalNetworkHeartbeatClient()
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: provider,
            client: client,
            statusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            configuration: LocalNetworkHeartbeatConfiguration(
                heartbeatInterval: 0.01,
                requestTimeout: 0.01,
                missedHeartbeatLimit: 2,
                staleAfter: 0.05,
                disconnectedAfter: 0.1
            )
        )

        #expect(!monitor.startForegroundMonitoring())
        provider.snapshot = makePairedMacSnapshot()
        #expect(monitor.startForegroundMonitoring())
        try? await Task.sleep(nanoseconds: 25_000_000)
        monitor.suspend()

        #expect(client.requests.count >= 1)
    }

    @MainActor
    @Test func pairingSuccessStoresCurrentMacIdentityInConnectionStore() throws {
        let suiteName = "RokuricsTests.Pairing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let keychain = KeychainStore(service: "com.Vita0818.Rokurics.tests.\(UUID().uuidString)")
        defer {
            try? keychain.delete(account: SecureMacConnectionSettings.deviceIDKey)
            try? keychain.delete(account: SecureMacConnectionSettings.sharedSecretKey)
            try? keychain.delete(account: SecureMacConnectionSettings.macFingerprintKey)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = SecureMacConnectionStore(userDefaults: defaults, keychainStore: keychain)
        let fingerprint = String(repeating: "a", count: 64)
        let result = SecurePairingResult(
            deviceID: "iphone-\(UUID().uuidString.lowercased())",
            sharedSecretBase64URL: Data("paired-secret-\(UUID().uuidString)".utf8).base64URLEncodedString(),
            pairedAt: "2026-05-26T10:00:00Z",
            macName: "Rokurics Mac",
            macModel: "MacBook"
        )

        try store.savePairing(
            result: result,
            host: " https://192.168.1.25:8787/pair ",
            portText: "8787",
            fingerprint: fingerprint.uppercased()
        )

        let snapshot = store.snapshot
        #expect(snapshot.isPaired)
        #expect(snapshot.macHost == "192.168.1.25")
        #expect(snapshot.macPort == 8787)
        #expect(snapshot.macFingerprint == fingerprint)
        #expect(snapshot.deviceID == result.deviceID)
        #expect(snapshot.sharedSecretBase64URL == result.sharedSecretBase64URL)

        let reloaded = SecureMacConnectionStore(userDefaults: defaults, keychainStore: keychain)
        #expect(reloaded.snapshot.macHost == "192.168.1.25")
        #expect(reloaded.snapshot.macPort == 8787)
        #expect(reloaded.snapshot.macFingerprint == fingerprint)
        #expect(reloaded.snapshot.sharedSecretBase64URL == result.sharedSecretBase64URL)
        #expect(reloaded.userConnectionIntent == .wantsConnected)
    }

    @MainActor
    @Test func manualDisconnectClearsPairedCredentialsAndRequiresFreshPairing() throws {
        let suiteName = "RokuricsTests.Intent.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let keychain = KeychainStore(service: "com.Vita0818.Rokurics.tests.\(UUID().uuidString)")
        defer {
            try? keychain.delete(account: SecureMacConnectionSettings.deviceIDKey)
            try? keychain.delete(account: SecureMacConnectionSettings.sharedSecretKey)
            try? keychain.delete(account: SecureMacConnectionSettings.macFingerprintKey)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = SecureMacConnectionStore(userDefaults: defaults, keychainStore: keychain)
        let result = SecurePairingResult(
            deviceID: "iphone-\(UUID().uuidString.lowercased())",
            sharedSecretBase64URL: Data("paired-secret-\(UUID().uuidString)".utf8).base64URLEncodedString(),
            pairedAt: "2026-05-26T10:00:00Z",
            macName: "Rokurics Mac",
            macModel: "MacBook"
        )
        try store.savePairing(
            result: result,
            host: "192.168.1.25",
            portText: "8787",
            fingerprint: String(repeating: "a", count: 64)
        )

        try store.clearPairing()
        let reloaded = SecureMacConnectionStore(userDefaults: defaults, keychainStore: keychain)

        #expect(!reloaded.snapshot.isPaired)
        #expect(reloaded.snapshot.sharedSecretBase64URL.isEmpty)
        #expect(reloaded.snapshot.deviceID.isEmpty)
        #expect(reloaded.snapshot.macHost.isEmpty)
        #expect(reloaded.snapshot.macPort == SecureMacConnectionSettings.defaultPort)
        #expect(reloaded.userConnectionIntent == .disconnectedByUser)
    }

    @Test func heartbeatPongMarksPeerOnlineAndRecordsLatency() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: FakeLocalNetworkHeartbeatClient(),
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )

        let didSend = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let status = try #require(statusStore.status(for: makePairedMacSnapshot().deviceID, now: Date(timeIntervalSince1970: 11)))

        #expect(didSend)
        #expect(status.presenceState == .online)
        #expect(status.state == .connected)
        #expect(status.missedHeartbeatCount == 0)
        #expect(status.latencyMilliseconds != nil)
    }

    @Test func heartbeatMonitorSendsRepeatedSequencesAndRecordsTraceDiagnostics() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let client = FakeLocalNetworkHeartbeatClient()
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot),
            client: client,
            statusStore: statusStore,
            diagnosticsStore: diagnosticsStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )

        for offset in [0, 3, 6] {
            _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10 + TimeInterval(offset)))
        }

        #expect(client.requests.map(\.sequenceNumber) == [1, 2, 3])
        let entries = diagnosticsStore.loadEntries()
        let startedSequences = entries
            .filter { $0.phase == "heartbeatRequestStarted" }
            .compactMap(\.heartbeatSequence)
        let responseSequences = entries
            .filter { $0.phase == "heartbeatResponseReceived" }
            .compactMap(\.responseSequence)
        let onlineSequences = entries
            .filter { $0.phase == "heartbeatMarkedOnline" }
            .compactMap(\.heartbeatSequence)
        let latestStatus = try #require(statusStore.status(for: snapshot.deviceID, now: Date()))

        #expect(startedSequences == [1, 2, 3])
        #expect(responseSequences == [1, 2, 3])
        #expect(onlineSequences == [1, 2, 3])
        #expect(latestStatus.presenceState == .online)
        #expect(latestStatus.missedHeartbeatCount == 0)
    }

    @Test func presenceSnapshotUnifiesStateAndRecentOnlineText() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL, staleAfter: 5, disconnectedAfter: 10)
        let snapshot = makePairedMacSnapshot()
        _ = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: Date(timeIntervalSince1970: 0),
            receivedAt: Date(timeIntervalSince1970: 0),
            latencyMilliseconds: 1
        )

        let interruptedStatus = try #require(statusStore.status(for: snapshot.deviceID, now: Date(timeIntervalSince1970: 8)))
        let presence = interruptedStatus.presenceSnapshot(now: Date(timeIntervalSince1970: 8))

        #expect(interruptedStatus.state != .connected)
        #expect(presence.state == .interrupted)
        #expect(presence.statusText == "连接中断 8 秒")
        #expect(presence.recentOnlineText == presence.statusText)
        #expect(!presence.isOnline)
    }

    @Test func heartbeatRecoveryResetsInterruptedSeconds() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL, staleAfter: 5, disconnectedAfter: 10)
        let snapshot = makePairedMacSnapshot()
        _ = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: Date(timeIntervalSince1970: 0),
            receivedAt: Date(timeIntervalSince1970: 0),
            latencyMilliseconds: 1
        )
        #expect(statusStore.status(for: snapshot.deviceID, now: Date(timeIntervalSince1970: 6))?.presenceSnapshot(now: Date(timeIntervalSince1970: 6)).state == .interrupted)

        _ = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: Date(timeIntervalSince1970: 7),
            receivedAt: Date(timeIntervalSince1970: 7),
            latencyMilliseconds: 1
        )
        let recovered = try #require(statusStore.status(for: snapshot.deviceID, now: Date(timeIntervalSince1970: 7)))
        let presence = recovered.presenceSnapshot(now: Date(timeIntervalSince1970: 7))

        #expect(presence.state == .online)
        #expect(presence.interruptedSeconds == 0)
        #expect(presence.recentOnlineText == "刚刚")
    }

    @Test func disabledSyncCoordinatorReadsPresenceStoreInsteadOfMarkingOffline() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let provider = FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: provider,
            studyLibraryStore: StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore),
            statusStore: statusStore,
            syncStateStore: syncStateStore,
            runtimeConfiguration: .default,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )

        _ = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: Date(timeIntervalSince1970: 9),
            receivedAt: Date(timeIntervalSince1970: 10),
            latencyMilliseconds: 4
        )
        coordinator.startForegroundMonitoring()
        coordinator.refreshPairingState()

        #expect(!coordinator.isAutomaticSyncMonitoringActive)
        #expect(coordinator.connectionStatus.presenceState == .online)
        #expect(coordinator.connectionStatus.state == .connected)
        #expect(coordinator.connectionStatus.lastSeenAt == Date(timeIntervalSince1970: 10))

        _ = statusStore.recordHeartbeatFailure(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            errorCode: "heartbeat_timeout",
            errorMessage: "Timed out"
        )
        _ = statusStore.recordHeartbeatFailure(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            errorCode: "heartbeat_timeout",
            errorMessage: "Timed out"
        )
        _ = statusStore.recordHeartbeatFailure(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            errorCode: "heartbeat_timeout",
            errorMessage: "Timed out"
        )
        coordinator.refreshPairingState()

        #expect(coordinator.connectionStatus.presenceState == .disconnected)
        #expect(coordinator.connectionStatus.state == .offline)
    }

    @Test func manualSyncInterruptedTriggersImmediateHeartbeatRetryBeforeSkippingDisabledSync() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let provider = FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        let heartbeatClient = FakeLocalNetworkHeartbeatClient()
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        _ = statusStore.markOffline(deviceID: snapshot.deviceID, displayName: "Rokurics Mac", error: "previous_disconnect")
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: provider,
            studyLibraryStore: StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore),
            presenceHeartbeatClient: heartbeatClient,
            statusStore: statusStore,
            syncStateStore: syncStateStore,
            diagnosticsStore: diagnosticsStore,
            runtimeConfiguration: .default,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )

        let result = await coordinator.synchronizeNow()
        let status = try #require(statusStore.status(for: snapshot.deviceID, now: Date()))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(result == nil)
        #expect(heartbeatClient.requests.map(\.sequenceNumber) == [1])
        #expect(status.presenceSnapshot().isOnline)
        #expect(status.lastSyncStatus == StudyLibrarySyncRuntimeConfiguration.disabledStatusText)
        #expect(phases.contains("manualSyncTriggeredImmediateProbe"))
    }

    @Test func manualSyncDoesNotForceConnectionWhenUserIntentIsFalse() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let provider = FakeSecureMacConnectionSnapshotProvider(
            snapshot: snapshot,
            userConnectionIntent: .disconnectedByUser
        )
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let heartbeatClient = FakeLocalNetworkHeartbeatClient()
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: provider,
            studyLibraryStore: StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore),
            presenceHeartbeatClient: heartbeatClient,
            statusStore: statusStore,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore,
            runtimeConfiguration: .default,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )

        let result = await coordinator.synchronizeNow()
        let status = try #require(statusStore.status(for: snapshot.deviceID))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(result == nil)
        #expect(provider.userConnectionIntent == .disconnectedByUser)
        #expect(heartbeatClient.requests.isEmpty)
        #expect(status.lastErrorCode == "user_disconnected")
        #expect(phases.contains("syncSkippedBecauseUserDoesNotWantConnection"))
    }

    @Test func syncFailureStatusDoesNotMutatePresenceToDisconnectedOrHeartbeatMiss() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        _ = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: Date(timeIntervalSince1970: 1),
            receivedAt: Date(timeIntervalSince1970: 1),
            latencyMilliseconds: 1
        )

        let afterSyncFailure = statusStore.recordSyncResult(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            statusText: "同步失败",
            at: Date(timeIntervalSince1970: 2),
            error: "sync_timeout"
        )

        #expect(afterSyncFailure.presenceState == .online)
        #expect(afterSyncFailure.missedHeartbeatCount == 0)
        #expect(afterSyncFailure.lastErrorCode == nil)
        #expect(afterSyncFailure.lastSyncStatus == "同步失败")
    }

    @Test func heartbeatTimeoutsIncrementMissesAndDisconnectAfterThreshold() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL, missedHeartbeatLimit: 2)
        let client = FakeLocalNetworkHeartbeatClient(error: URLError(.timedOut))
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: client,
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 2, staleAfter: 6, disconnectedAfter: 10)
        )

        _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let first = try #require(statusStore.status(for: makePairedMacSnapshot().deviceID, now: Date(timeIntervalSince1970: 10)))
        _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 11))
        let second = try #require(statusStore.status(for: makePairedMacSnapshot().deviceID, now: Date(timeIntervalSince1970: 11)))

        #expect(first.presenceState == .interrupted)
        #expect(first.missedHeartbeatCount == 1)
        #expect(second.presenceState == .disconnected)
        #expect(second.missedHeartbeatCount == 2)
    }

    @Test func heartbeatMonitorPreventsConcurrentRequests() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let client = FakeLocalNetworkHeartbeatClient(delayNanoseconds: 50_000_000)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: client,
            statusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )

        async let first: Bool = monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        try? await Task.sleep(nanoseconds: 5_000_000)
        let second = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let firstResult = await first

        #expect(firstResult)
        #expect(!second)
        #expect(client.maxConcurrentRequests == 1)
    }

    @Test func signedRequestSuccessRefreshesPresenceState() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let snapshot = makePairedMacSnapshot()

        _ = statusStore.recordHeartbeatFailure(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            errorCode: "heartbeat_timeout",
            errorMessage: "Timed out"
        )
        let refreshed = statusStore.recordSignedRequestSucceeded(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            now: Date(timeIntervalSince1970: 20)
        )

        #expect(refreshed.presenceState == .online)
        #expect(refreshed.lastSignedRequestSucceededAt == Date(timeIntervalSince1970: 20))
        #expect(refreshed.missedHeartbeatCount == 0)
    }

    @Test func heartbeatFailureDoesNotDeleteUploadJobOrSyncState() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "heartbeat-preserve-upload-job", title: "保留上传任务", store: audioStore, uploadStatus: "failed")
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let snapshot = makePairedMacSnapshot()
        let connectionProvider = FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot)
        _ = try jobStore.ensureJob(for: metadata, settings: snapshot, now: Date(timeIntervalSince1970: 1))
        let syncStateStore = LocalNetworkSyncStateStore(rootURL: rootURL)
        syncStateStore.recordFailure(code: "previous_sync_failure", message: "keep me", at: Date(timeIntervalSince1970: 2))
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL, missedHeartbeatLimit: 1)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: connectionProvider,
            client: FakeLocalNetworkHeartbeatClient(error: URLError(.cannotConnectToHost)),
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 1, staleAfter: 6, disconnectedAfter: 10)
        )

        _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 3))

        #expect(try jobStore.loadJob(recordingID: metadata.id) != nil)
        #expect(syncStateStore.state.lastErrorCode == "previous_sync_failure")
        #expect(connectionProvider.snapshot.isPaired)
    }

    @Test func heartbeatSecurityFailureMapsToSecurityError() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: FakeLocalNetworkHeartbeatClient(error: SecureMacUploadError.fingerprintMismatch),
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )

        _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let status = try #require(statusStore.status(for: makePairedMacSnapshot().deviceID, now: Date(timeIntervalSince1970: 10)))

        #expect(status.presenceState == .securityError)
        #expect(status.lastErrorCode == "certificate_pinning_failed")
    }

    @Test func uploadTestGateUsesPresenceState() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let onlineStatus = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: Date(timeIntervalSince1970: 1),
            receivedAt: Date(timeIntervalSince1970: 2),
            latencyMilliseconds: 3
        )

        #expect(MacUploadTestPresenceGate.blockedReason(snapshot: snapshot, status: onlineStatus, now: Date(timeIntervalSince1970: 2)) == nil)

        let disconnected = statusStore.markOffline(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            error: "heartbeat_disconnected",
            now: Date(timeIntervalSince1970: 12)
        )

        #expect(MacUploadTestPresenceGate.blockedReason(snapshot: snapshot, status: disconnected) == "heartbeat_disconnected")
        #expect(MacUploadTestPresenceGate.blockedReason(snapshot: makeUnpairedMacSnapshot(), status: disconnected) == "not_paired")
    }

    @Test func studyItemTransferProgressModelReplacesActionAreaUntilComplete() {
        let item = StudyItemMetadata(
            recordingID: "transfer-recording",
            title: "传输中录音",
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 5
        )
        let transferring = LocalNetworkTransferProgress(
            objectID: "transfer-recording",
            objectKind: LocalNetworkSyncObjectKind.transcriptMarkdown.rawValue,
            state: .transferring,
            progressFraction: 0.4,
            receivedBytes: 4,
            totalBytes: 10,
            sourceDeviceID: "mac-01",
            statusText: "40%"
        )

        let withTransfer = item.withLocalNetworkTransferProgress(transferring)
        let restored = withTransfer.withLocalNetworkTransferProgress(LocalNetworkTransferProgress(
            objectID: "transfer-recording",
            objectKind: LocalNetworkSyncObjectKind.transcriptMarkdown.rawValue,
            state: .complete,
            progressFraction: 1,
            receivedBytes: 10,
            totalBytes: 10,
            sourceDeviceID: "mac-01",
            statusText: "已完成"
        ))

        #expect(withTransfer.localNetworkTransferProgress?.state == .transferring)
        #expect(withTransfer.localNetworkTransferProgress?.progressFraction == 0.4)
        #expect(withTransfer.localNetworkTransferProgress?.isVisibleInActionArea == true)
        #expect(restored.localNetworkTransferProgress == nil)
    }

    @Test func heartbeatDiagnosticsContainPhasesWithoutSecrets() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot),
            client: FakeLocalNetworkHeartbeatClient(),
            statusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )

        _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        monitor.recordSignedRequestSucceeded(settings: snapshot, now: Date(timeIntervalSince1970: 11))

        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))
        #expect(phases.contains("heartbeatRequestStarted"))
        #expect(phases.contains("heartbeatResponseReceived"))
        #expect(phases.contains("heartbeatMarkedOnline"))
        #expect(phases.contains("signedRequestRefreshedLastSeen"))

        let diagnosticsText = try String(contentsOf: diagnosticsStore.logURL, encoding: .utf8)
        #expect(!diagnosticsText.lowercased().contains("sharedsecret"))
        #expect(!diagnosticsText.lowercased().contains("hmac"))
        #expect(!diagnosticsText.lowercased().contains("privatekey"))
        #expect(!diagnosticsText.contains(snapshot.sharedSecretBase64URL))
    }

    @Test func staleHostOrPortHeartbeatFailureIsClassifiedWithoutClearingCredentials() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = SecureMacConnectionSnapshot(
            macHost: "192.0.2.55",
            macPort: 65535,
            macFingerprint: String(repeating: "a", count: 64),
            macName: "Rokurics Mac",
            macModel: "Mac",
            deviceID: "iphone-stale-host",
            sharedSecretBase64URL: Data("stale-host-secret".utf8).base64EncodedString(),
            pairedAt: "2026-05-26T10:00:00Z"
        )
        let provider = FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: provider,
            client: FakeLocalNetworkHeartbeatClient(error: SecureMacUploadError.httpsUnavailable("连接被拒绝或 Mac 未监听该地址。")),
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )

        _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let status = try #require(statusStore.status(for: snapshot.deviceID, now: Date(timeIntervalSince1970: 10)))

        #expect(status.presenceState == .interrupted)
        #expect(status.lastErrorCode == "heartbeat_unreachable")
        #expect(provider.snapshot.isPaired)
        #expect(provider.snapshot.sharedSecretBase64URL == snapshot.sharedSecretBase64URL)
    }

    @Test func heartbeatConfigurationSupportsForegroundSecondScaleIntervals() {
        let configuration = LocalNetworkHeartbeatConfiguration(
            heartbeatInterval: 1,
            requestTimeout: 1.5,
            missedHeartbeatLimit: 3,
            staleAfter: 6,
            disconnectedAfter: 10
        )

        #expect((1...5).contains(configuration.heartbeatInterval))
        #expect(configuration.requestTimeout <= 3)
        #expect(configuration.missedHeartbeatLimit == 3)
    }

    @Test func heartbeatPayloadDoesNotCarrySyncOrFileDataOrSecrets() throws {
        let request = ConnectionHeartbeatRequest(
            deviceID: "iphone-01",
            deviceName: "Vita iPhone",
            platform: .iPhone,
            appInstanceID: "instance-01",
            sequenceNumber: 7,
            sentAt: Date(timeIntervalSince1970: 10),
            lastKnownPeerStatusRevision: 3
        )

        let json = String(data: try Self.studyEncoder.encode(request), encoding: .utf8) ?? ""

        #expect(!json.lowercased().contains("sharedsecret"))
        #expect(!json.lowercased().contains("hmac"))
        #expect(!json.lowercased().contains("manifest"))
        #expect(!json.lowercased().contains("transcript"))
        #expect(!json.lowercased().contains("audio"))
        #expect(!json.lowercased().contains("note"))
    }

    @Test func disconnectedOrSecurityStatusDoesNotClearPairedCredentials() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let provider = FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL, missedHeartbeatLimit: 1)

        _ = statusStore.recordHeartbeatFailure(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            errorCode: "certificate_pinning_failed",
            errorMessage: "Certificate pinning failed",
            isSecurityFailure: true
        )

        #expect(statusStore.status(for: snapshot.deviceID)?.presenceState == .securityError)
        #expect(provider.snapshot.isPaired)
        #expect(provider.snapshot.sharedSecretBase64URL == snapshot.sharedSecretBase64URL)
    }

    @Test func localNetworkSyncEngineDoesNotRunSecureSyncWithoutPairedDevice() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let fakeClient = FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac))
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makeUnpairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL)
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 1))

        #expect(plan == nil)
        #expect(fakeClient.inventoryRequestCount == 0)
    }

    @Test func localNetworkSyncEngineRespectsNextAllowedSyncAt() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL)
        var blockedState = LocalNetworkSyncState.empty
        blockedState.nextAllowedSyncAt = Date(timeIntervalSince1970: 10_000)
        stateStore.replace(blockedState)
        let fakeClient = FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac))
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: stateStore
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 1))

        #expect(plan == nil)
        #expect(fakeClient.inventoryRequestCount == 0)
    }

    @Test func localNetworkSyncEngineSkipsWhenPresenceIsNotOnline() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        _ = statusStore.markOffline(deviceID: makePairedMacSnapshot().deviceID, displayName: "Mac", error: "offline")
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL)
        let fakeClient = FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac))
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: stateStore,
            connectionStatusStore: statusStore
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 1))

        #expect(plan == nil)
        #expect(fakeClient.inventoryRequestCount == 0)
        #expect(stateStore.state.lastErrorCode == "presence_not_online")
    }

    @Test func localNetworkSyncDiagnosticsContainPhasesWithoutSecrets() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac)),
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore
        )

        _ = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 10))
        let rawLog = (try? String(contentsOf: diagnosticsStore.logURL, encoding: .utf8)) ?? ""

        #expect(rawLog.contains("syncTickStarted"))
        #expect(rawLog.contains("localInventoryBuilt"))
        #expect(rawLog.contains("peerInventoryFetched"))
        #expect(rawLog.contains("diffPlanCreated"))
        #expect(rawLog.contains("syncTickCompleted"))
        #expect(!rawLog.lowercased().contains("sharedsecret"))
        #expect(!rawLog.lowercased().contains("hmac"))
        #expect(!rawLog.contains("c3luYy1zZWNyZXQ"))
    }

    @Test func localNetworkSyncEngineDownloadsTranscriptArtifact() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let logicalPath = "transcripts/recording-remote/transcript.md"
        let receivePath = "incoming/recording-remote/receive.json"
        let artifactID = LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "recording-remote", logicalPathToken: logicalPath)
        let receiveArtifactID = LocalNetworkSyncArtifactID.make(kind: .receiveJSON, ownerID: "recording-remote", logicalPathToken: receivePath)
        let item = StudyItemMetadata(
            recordingID: "recording-remote",
            title: "远端转写",
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 9,
            receiveRelativePath: receivePath,
            transcriptMarkdownRelativePath: logicalPath,
            updatedAt: Date(timeIntervalSince1970: 2_010),
            transcriptionStatus: "transcribed",
            noteStatus: "notStarted"
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "mac-01",
            generatedAt: Date(timeIntervalSince1970: 2_020),
            items: [item],
            folders: []
        )
        let peerInventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: Date(timeIntervalSince1970: 2_020),
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            studyItems: [
                LocalNetworkSyncStudyItemEntry(
                    itemID: item.itemID,
                    kind: item.kind,
                    title: item.title,
                    folderIDs: item.folderIDs,
                    recordingID: item.recordingID,
                    updatedAt: item.updatedAt,
                    revisionHash: LocalNetworkSyncMetadataHash.hash(item),
                    deleted: false
                )
            ],
            artifacts: [
                LocalNetworkSyncArtifactEntry(
                    artifactID: artifactID,
                    kind: .transcriptMarkdown,
                    ownerID: "recording-remote",
                    checksum: SecureUploadUtilities.sha256Hex(Data("hello transcript".utf8)),
                    size: 16,
                    updatedAt: Date(timeIntervalSince1970: 2_020),
                    availability: .local,
                    logicalPathToken: logicalPath
                ),
                LocalNetworkSyncArtifactEntry(
                    artifactID: receiveArtifactID,
                    kind: .receiveJSON,
                    ownerID: "recording-remote",
                    checksum: SecureUploadUtilities.sha256Hex(Data(#"{"status":"completed"}"#.utf8)),
                    size: Int64(Data(#"{"status":"completed"}"#.utf8).count),
                    updatedAt: Date(timeIntervalSince1970: 2_020),
                    availability: .local,
                    logicalPathToken: receivePath
                )
            ],
            studyManifest: manifest
        )
        let fakeClient = FakeLocalNetworkSyncClient(
            peerInventory: peerInventory,
            artifactResponses: [
                artifactID: LocalNetworkSyncArtifactResponse(
                    ok: true,
                    artifactID: artifactID,
                    kind: .transcriptMarkdown,
                    checksum: SecureUploadUtilities.sha256Hex(Data("hello transcript".utf8)),
                    size: 16,
                    logicalPathToken: logicalPath,
                    dataBase64: Data("hello transcript".utf8).base64EncodedString(),
                    error: nil
                ),
                receiveArtifactID: LocalNetworkSyncArtifactResponse(
                    ok: true,
                    artifactID: receiveArtifactID,
                    kind: .receiveJSON,
                    checksum: SecureUploadUtilities.sha256Hex(Data(#"{"status":"completed"}"#.utf8)),
                    size: Int64(Data(#"{"status":"completed"}"#.utf8).count),
                    logicalPathToken: receivePath,
                    dataBase64: Data(#"{"status":"completed"}"#.utf8).base64EncodedString(),
                    error: nil
                )
            ]
        )
        var observedTransferStates: [LocalNetworkTransferState] = []
        fakeClient.onArtifactRequest = { _ in
            if let progress = studyStore.item(recordingID: "recording-remote")?.localNetworkTransferProgress {
                observedTransferStates.append(progress.state)
            }
        }
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL)
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 3_000))
        let downloadedURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: audioStore.baseDirectory(), logicalPathToken: logicalPath)
        let downloadedReceiveURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: audioStore.baseDirectory(), logicalPathToken: receivePath)

        #expect(plan?.downloadArtifactActions.map(\.entityID).contains(artifactID) == true)
        #expect(plan?.downloadArtifactActions.map(\.entityID).contains(receiveArtifactID) == true)
        #expect(String(data: try Data(contentsOf: downloadedURL), encoding: .utf8) == "hello transcript")
        #expect(String(data: try Data(contentsOf: downloadedReceiveURL), encoding: .utf8) == #"{"status":"completed"}"#)
        #expect(fakeClient.artifactRequestIDs == [receiveArtifactID, artifactID] || fakeClient.artifactRequestIDs == [artifactID, receiveArtifactID])
        #expect(observedTransferStates.contains(.transferring))
        #expect(studyStore.item(recordingID: "recording-remote")?.localNetworkTransferProgress == nil)
    }

    @Test func localNetworkSyncEngineUploadsSmallArtifactWhenPeerMissing() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let logicalPath = "transcripts/local-recording/transcript.md"
        let localData = Data("local transcript".utf8)
        let localURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: audioStore.baseDirectory(), logicalPathToken: logicalPath)
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try localData.write(to: localURL)

        let item = StudyItemMetadata(
            recordingID: "local-recording",
            title: "本地转写",
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 5,
            transcriptMarkdownRelativePath: logicalPath,
            updatedAt: Date(timeIntervalSince1970: 2_010),
            transcriptionStatus: "transcribed",
            noteStatus: "notStarted"
        )
        _ = try studyStore.applySyncManifest(
            StudyLibrarySyncManifest.make(
                deviceID: makePairedMacSnapshot().deviceID,
                generatedAt: Date(timeIntervalSince1970: 2_020),
                items: [item],
                folders: []
            ),
            localDeviceID: makePairedMacSnapshot().deviceID
        )

        let fakeClient = FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac))
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL)
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 3_000))
        let artifactID = LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "local-recording", logicalPathToken: logicalPath)
        let putRequest = try #require(fakeClient.artifactPutRequests.first)

        #expect(plan?.uploadArtifactActions.contains { $0.entityID == artifactID } == true)
        #expect(putRequest.artifactID == artifactID)
        #expect(putRequest.kind == .transcriptMarkdown)
        #expect(putRequest.logicalPathToken == logicalPath)
        #expect(putRequest.checksum == SecureUploadUtilities.sha256Hex(localData))
        #expect(Data(base64Encoded: putRequest.dataBase64) == localData)
    }

    @Test func localNetworkSyncEngineAppliesCompletedReceiveStatusToLocalMetadata() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "receive-return-01", title: "待确认上传", store: audioStore, uploadStatus: "failed")
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let peerInventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: Date(timeIntervalSince1970: 2_020),
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [
                LocalNetworkSyncRecordingEntry(
                    recordingID: metadata.id,
                    metadataHash: LocalNetworkSyncMetadataHash.hash(metadata),
                    audioAvailable: true,
                    audioChecksum: nil,
                    audioSize: metadata.fileSize,
                    uploadLedgerState: nil,
                    receiveStatus: "completed",
                    processingStatus: "notStarted",
                    updatedAt: metadata.endedAt.addingTimeInterval(60),
                    deleted: false
                )
            ]
        )
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: FakeLocalNetworkSyncClient(peerInventory: peerInventory),
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL)
        )

        _ = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 3_000))

        #expect(try audioStore.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.uploaded.rawValue)
    }

    @Test func secureUploadServerResponseDecodesMetadataAcceptedNew() throws {
        let response = try decodeSecureUploadResponse("""
        {"audioFileName":null,"disposition":"acceptedNew","metadataFileName":"metadata.json","message":"recording metadata received","ok":true,"processingStatus":"awaitingAudio","receiveFileName":"receive.json","receiveStatus":"metadataReceived","recordingID":"metadata-new"}
        """)

        #expect(response.ok)
        #expect(response.recordingID == "metadata-new")
        #expect(response.metadataFileName == "metadata.json")
        #expect(response.audioFileName == nil)
        #expect(response.disposition == "acceptedNew")
        #expect(response.receiveStatus == "metadataReceived")
        #expect(response.processingStatus == "awaitingAudio")
    }

    @Test func secureUploadServerResponseDecodesMetadataAcceptedExisting() throws {
        let response = try decodeSecureUploadResponse("""
        {"audioFileName":null,"disposition":"acceptedExisting","metadataFileName":"metadata.json","message":"recording metadata received","ok":true,"processingStatus":"awaitingAudio","receiveFileName":"receive.json","receiveStatus":"metadataReceived","recordingID":"metadata-existing"}
        """)

        #expect(response.ok)
        #expect(response.recordingID == "metadata-existing")
        #expect(response.disposition == "acceptedExisting")
        #expect(response.receiveStatus == "metadataReceived")
        #expect(response.processingStatus == "awaitingAudio")
    }

    @Test func secureUploadServerResponseDecodesMetadataConflict() throws {
        let response = try decodeSecureUploadResponse("""
        {"disposition":"rejectedConflict","error":"recording_metadata_conflict","ok":false,"reason":"Conflict"}
        """)
        let error = SecureMacUploadError.serverRejected(response.error ?? "missing_error")

        #expect(!response.ok)
        #expect(response.error == "recording_metadata_conflict")
        #expect(response.disposition == "rejectedConflict")
        #expect(response.reason == "Conflict")
        #expect(error.localizedDescription == "recording_metadata_conflict")
    }

    @Test func secureUploadServerResponseDecodesAudioAcceptedNew() throws {
        let response = try decodeSecureUploadResponse("""
        {"audioFileName":"audio.m4a","disposition":"acceptedNew","metadataFileName":"metadata.json","message":"recording audio received","ok":true,"processingStatus":"notStarted","receiveFileName":"receive.json","receiveStatus":"completed","recordingID":"audio-new"}
        """)

        #expect(response.ok)
        #expect(response.recordingID == "audio-new")
        #expect(response.audioFileName == "audio.m4a")
        #expect(response.disposition == "acceptedNew")
        #expect(response.receiveStatus == "completed")
        #expect(response.processingStatus == "notStarted")
    }

    @Test func secureUploadServerResponseDecodesAudioAcceptedExisting() throws {
        let response = try decodeSecureUploadResponse("""
        {"audioFileName":"audio.m4a","disposition":"acceptedExisting","metadataFileName":"metadata.json","message":"recording audio received","ok":true,"processingStatus":"notStarted","receiveFileName":"receive.json","receiveStatus":"completed","recordingID":"audio-existing"}
        """)

        #expect(response.ok)
        #expect(response.recordingID == "audio-existing")
        #expect(response.audioFileName == "audio.m4a")
        #expect(response.disposition == "acceptedExisting")
        #expect(response.receiveStatus == "completed")
        #expect(response.processingStatus == "notStarted")
    }

    @Test func secureUploadServerResponseDecodesAudioConflict() throws {
        let response = try decodeSecureUploadResponse("""
        {"disposition":"rejectedConflict","error":"recording_audio_conflict","ok":false,"reason":"Conflict"}
        """)
        let error = SecureMacUploadError.serverRejected(response.error ?? "missing_error")

        #expect(!response.ok)
        #expect(response.error == "recording_audio_conflict")
        #expect(response.disposition == "rejectedConflict")
        #expect(response.reason == "Conflict")
        #expect(error.localizedDescription == "recording_audio_conflict")
    }

    @Test func connectionProbeResponseDecodesTinyEchoPayload() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(ConnectionProbeResponse.self, from: Data("""
        {"disposition":"ok","echoedClientPayload":"tiny hello","ok":true,"receivedSequenceNumber":9,"serverPayload":"rokurics-probe-ok","serverTime":"2026-05-26T00:00:00Z"}
        """.utf8))

        #expect(response.ok)
        #expect(response.disposition == "ok")
        #expect(response.receivedSequenceNumber == 9)
        #expect(response.echoedClientPayload == "tiny hello")
        #expect(response.serverPayload == "rokurics-probe-ok")
    }

    @Test func secureUploadServerResponseKeepsLegacyAndMalformedErrorsReadable() throws {
        let legacy = try decodeSecureUploadResponse(#"{"ok":false,"error":"legacy_upload_failed"}"#)

        #expect(!legacy.ok)
        #expect(legacy.error == "legacy_upload_failed")
        #expect(SecureMacUploadError.serverRejected(legacy.error ?? "missing_error").localizedDescription == "legacy_upload_failed")

        do {
            _ = try decodeSecureUploadResponse("not-json")
            Issue.record("Expected malformed JSON to fail decoding")
        } catch {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test func iphoneAIProviderPresetFiltersLocalDesktopProviders() {
        let visible = AIProviderPreset.iPhoneVisibleCases

        #expect(visible.contains(.openAI))
        #expect(visible.contains(.deepSeek))
        #expect(visible.contains(.gemini))
        #expect(visible.contains(.customOpenAICompatible))
        #expect(!visible.contains(.lmStudioLocal))
        #expect(!visible.contains(.ollamaLocal))
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
        uploadStatus: String = "localOnly",
        studyFiling: StudyFilingPath? = nil,
        audioData: Data = Data("audio".utf8)
    ) throws -> RecordingMetadata {
        let audioURL = try store.recordingsDirectory()
            .appendingPathComponent(id, isDirectory: false)
            .appendingPathExtension("m4a")
        try audioData.write(to: audioURL)
        let metadataURL = try store.makeMetadataURL(id: id)
        let metadata = makeMetadata(
            id: id,
            title: title,
            relativeAudioPath: try store.relativePath(for: audioURL),
            relativeMetadataPath: try store.relativePath(for: metadataURL),
            uploadStatus: uploadStatus,
            studyFiling: studyFiling,
            fileSize: Int64(audioData.count)
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
        studyFiling: StudyFilingPath? = nil,
        fileSize: Int64 = 5
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
            fileSize: fileSize,
            uploadStatus: uploadStatus,
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            tags: [],
            studyFiling: studyFiling
        )
    }

    private static let studyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let studyDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func decodeSecureUploadResponse(_ json: String) throws -> SecureUploadServerResponse {
        try JSONDecoder().decode(SecureUploadServerResponse.self, from: Data(json.utf8))
    }
}

@MainActor
private final class FakeSecureMacConnectionSnapshotProvider: SecureMacConnectionSnapshotProviding, SecureMacConnectionIntentProviding {
    var snapshot: SecureMacConnectionSnapshot
    var userConnectionIntent: UserConnectionIntent

    init(snapshot: SecureMacConnectionSnapshot, userConnectionIntent: UserConnectionIntent = .wantsConnected) {
        self.snapshot = snapshot
        self.userConnectionIntent = userConnectionIntent
    }
}

private final class FakeRecordingUploadClient: RecordingUploadClientProtocol {
    enum ResultMode {
        case success(RecordingUploadResult)
        case failure(Error)
    }

    let result: ResultMode
    let events: [RecordingUploadProgressEvent]
    private(set) var lastMetadata: RecordingMetadata?

    init(result: ResultMode, events: [RecordingUploadProgressEvent] = []) {
        self.result = result
        self.events = events
    }

    func uploadRecording(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        progress: RecordingUploadProgressHandler?
    ) async throws -> RecordingUploadResult {
        lastMetadata = metadata
        for event in events {
            try progress?(event)
        }

        switch result {
        case .success(let uploadResult):
            return uploadResult
        case .failure(let error):
            throw error
        }
    }
}

private final class FakeRecordingSecureUploadTransport: RecordingSecureUploadTransport {
    var metadataUploadCount = 0
    var singleFileUploadCount = 0
    var resumableStartCount = 0
    var statusCount = 0
    var finalizeCount = 0
    var chunkOffsets: [Int64] = []
    var failChunkAtOffset: Int64?
    var chunkErrorAtOffset: (offset: Int64, error: Error)?
    var statusConfirmedBytes: Int64?
    var finalizeDisposition = "acceptedNew"

    private var sessionID = "session-1"
    private var confirmedBytes: Int64 = 0
    private var totalBytes: Int64 = 0
    private var chunkSize = 0

    func uploadSignedData(
        settings: SecureMacConnectionSnapshot,
        path: String,
        body: Data,
        contentType: String,
        uploadType: String,
        recordingID: String,
        fileName: String,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) async throws -> SecureUploadServerResponse {
        metadataUploadCount += 1
        return SecureUploadServerResponse(
            ok: true,
            message: "metadata received",
            disposition: "acceptedNew",
            fileName: nil,
            recordingID: recordingID,
            metadataFileName: "metadata.json",
            audioFileName: nil,
            receiveStatus: "metadataReceived",
            processingStatus: "awaitingAudio",
            error: nil,
            reason: nil
        )
    }

    func uploadSignedFile(
        settings: SecureMacConnectionSnapshot,
        path: String,
        fileURL: URL,
        contentType: String,
        uploadType: String,
        recordingID: String,
        fileName: String,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) async throws -> SecureUploadServerResponse {
        singleFileUploadCount += 1
        return SecureUploadServerResponse(
            ok: true,
            message: "audio received",
            disposition: "acceptedNew",
            fileName: "audio.m4a",
            recordingID: recordingID,
            metadataFileName: nil,
            audioFileName: "audio.m4a",
            receiveStatus: "completed",
            processingStatus: "notStarted",
            error: nil,
            reason: nil
        )
    }

    func startResumableAudioUpload(
        settings: SecureMacConnectionSnapshot,
        request: ResumableAudioUploadStartRequest
    ) async throws -> ResumableAudioUploadSessionResponse {
        resumableStartCount += 1
        sessionID = "session-1"
        totalBytes = request.totalBytes
        chunkSize = request.chunkSize
        confirmedBytes = 0
        return sessionResponse(
            disposition: "acceptedNew",
            confirmedBytes: confirmedBytes,
            chunkSize: request.chunkSize,
            completed: false
        )
    }

    func fetchResumableAudioUploadStatus(
        settings: SecureMacConnectionSnapshot,
        request: ResumableAudioUploadStatusRequest
    ) async throws -> ResumableAudioUploadSessionResponse {
        statusCount += 1
        if let statusConfirmedBytes {
            confirmedBytes = statusConfirmedBytes
        }
        return sessionResponse(
            disposition: "acceptedExisting",
            confirmedBytes: confirmedBytes,
            chunkSize: chunkSize == 0 ? nil : chunkSize,
            completed: false
        )
    }

    func uploadResumableAudioChunk(
        settings: SecureMacConnectionSnapshot,
        recordingID: String,
        sessionID: String,
        offset: Int64,
        totalSHA256: String,
        chunk: Data
    ) async throws -> ResumableAudioUploadSessionResponse {
        if let chunkErrorAtOffset, chunkErrorAtOffset.offset == offset {
            throw chunkErrorAtOffset.error
        }
        if failChunkAtOffset == offset {
            throw RecordingUploadError.networkFailed("network lost")
        }

        chunkOffsets.append(offset)
        confirmedBytes = offset + Int64(chunk.count)
        return sessionResponse(
            disposition: "acceptedNew",
            confirmedBytes: confirmedBytes,
            chunkSize: chunkSize == 0 ? chunk.count : chunkSize,
            completed: false,
            chunkAccepted: true
        )
    }

    func finalizeResumableAudioUpload(
        settings: SecureMacConnectionSnapshot,
        request: ResumableAudioUploadFinalizeRequest
    ) async throws -> ResumableAudioUploadSessionResponse {
        finalizeCount += 1
        confirmedBytes = request.totalBytes
        totalBytes = request.totalBytes
        return sessionResponse(
            disposition: finalizeDisposition,
            confirmedBytes: request.totalBytes,
            chunkSize: chunkSize == 0 ? nil : chunkSize,
            completed: true,
            finalAudioExists: true,
            finalAudioRelativePath: "audio/inbox/day/\(request.recordingID)/audio.m4a",
            checksum: request.totalSHA256,
            fileSize: request.totalBytes
        )
    }

    private func sessionResponse(
        disposition: String,
        confirmedBytes: Int64,
        chunkSize: Int?,
        completed: Bool,
        chunkAccepted: Bool? = nil,
        finalAudioExists: Bool? = nil,
        finalAudioRelativePath: String? = nil,
        checksum: String? = nil,
        fileSize: Int64? = nil
    ) -> ResumableAudioUploadSessionResponse {
        ResumableAudioUploadSessionResponse(
            ok: true,
            disposition: disposition,
            status: completed ? "completed" : "active",
            sessionID: sessionID,
            confirmedBytes: confirmedBytes,
            nextOffset: confirmedBytes,
            chunkSize: chunkSize,
            completed: completed,
            finalAudioExists: finalAudioExists,
            chunkAccepted: chunkAccepted,
            finalAudioRelativePath: finalAudioRelativePath,
            checksum: checksum,
            fileSize: fileSize,
            receiveStatus: completed ? "completed" : nil,
            processingStatus: completed ? "notStarted" : nil,
            error: nil,
            reason: nil
        )
    }
}

private final class FakeLocalNetworkSyncClient: LocalNetworkSyncClientProtocol {
    let peerInventory: LocalNetworkSyncInventory
    var artifactResponses: [String: LocalNetworkSyncArtifactResponse]
    var onArtifactRequest: ((String) -> Void)?
    private(set) var inventoryRequestCount = 0
    private(set) var applyMetadataCount = 0
    private(set) var artifactRequestIDs: [String] = []
    private(set) var artifactPutRequests: [LocalNetworkSyncArtifactPutRequest] = []

    init(
        peerInventory: LocalNetworkSyncInventory,
        artifactResponses: [String: LocalNetworkSyncArtifactResponse] = [:]
    ) {
        self.peerInventory = peerInventory
        self.artifactResponses = artifactResponses
    }

    func sendDeviceStatus(
        settings: SecureMacConnectionSnapshot,
        statusRequest: DeviceStatusRequest
    ) async throws -> DeviceStatusResponse {
        DeviceStatusResponse(ok: true, status: nil, syncState: nil, error: nil)
    }

    func fetchLocalNetworkSyncInventory(
        settings: SecureMacConnectionSnapshot,
        localInventory: LocalNetworkSyncInventory
    ) async throws -> LocalNetworkSyncInventoryResponse {
        inventoryRequestCount += 1
        return LocalNetworkSyncInventoryResponse(ok: true, inventory: peerInventory, error: nil)
    }

    func applyLocalNetworkSyncMetadata(
        settings: SecureMacConnectionSnapshot,
        manifest: StudyLibrarySyncManifest
    ) async throws -> StudyLibrarySyncManifestResponse {
        applyMetadataCount += 1
        return StudyLibrarySyncManifestResponse(
            ok: true,
            manifest: nil,
            syncState: nil,
            deviceStatus: nil,
            applyResult: StudyLibrarySyncApplyResult(),
            baseCommitID: nil,
            newCommitID: nil,
            remoteChanges: nil,
            rejectedChanges: nil,
            error: nil
        )
    }

    func requestLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        artifactID: String
    ) async throws -> LocalNetworkSyncArtifactResponse {
        artifactRequestIDs.append(artifactID)
        onArtifactRequest?(artifactID)
        return artifactResponses[artifactID] ?? LocalNetworkSyncArtifactResponse(
            ok: false,
            artifactID: nil,
            kind: nil,
            checksum: nil,
            size: nil,
            logicalPathToken: nil,
            dataBase64: nil,
            error: "missing_fake_artifact"
        )
    }

    func putLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactPutRequest
    ) async throws -> LocalNetworkSyncArtifactPutResponse {
        artifactPutRequests.append(request)
        return LocalNetworkSyncArtifactPutResponse(
            ok: true,
            artifactID: request.artifactID,
            disposition: "acceptedNew",
            checksum: request.checksum,
            size: request.size,
            error: nil
        )
    }
}

private final class FakeLocalNetworkHeartbeatClient: LocalNetworkHeartbeatClientProtocol {
    private(set) var requests: [ConnectionHeartbeatRequest] = []
    private(set) var maxConcurrentRequests = 0
    private var inFlightRequests = 0
    var error: Error?
    var delayNanoseconds: UInt64

    init(error: Error? = nil, delayNanoseconds: UInt64 = 0) {
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    func sendConnectionHeartbeat(
        settings: SecureMacConnectionSnapshot,
        request: ConnectionHeartbeatRequest,
        requestTimeout: TimeInterval
    ) async throws -> ConnectionHeartbeatResponse {
        requests.append(request)
        inFlightRequests += 1
        maxConcurrentRequests = max(maxConcurrentRequests, inFlightRequests)
        defer {
            inFlightRequests -= 1
        }
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let error {
            throw error
        }
        return ConnectionHeartbeatResponse(
            ok: true,
            disposition: "ok",
            peerDeviceID: "mac-01",
            serverTime: Date(),
            receivedSequenceNumber: request.sequenceNumber,
            connectionStatusRevision: request.lastKnownPeerStatusRevision ?? 0,
            minimumSuggestedInterval: nil,
            status: nil,
            error: nil
        )
    }
}

private func emptyLocalNetworkInventory(
    deviceID: String,
    platform: LocalNetworkSyncPlatform
) -> LocalNetworkSyncInventory {
    LocalNetworkSyncInventory.make(
        device: LocalNetworkSyncDeviceSection(
            deviceID: deviceID,
            deviceName: platform == .Mac ? "Mac" : "iPhone",
            platform: platform,
            generatedAt: Date(timeIntervalSince1970: 1),
            lastKnownPeerRevision: nil,
            appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
        )
    )
}

private func makePairedMacSnapshot() -> SecureMacConnectionSnapshot {
    SecureMacConnectionSnapshot(
        macHost: "127.0.0.1",
        macPort: 8787,
        macFingerprint: String(repeating: "a", count: 64),
        macName: "Rokurics Mac",
        macModel: "Mac",
        deviceID: "mac-disabled",
        sharedSecretBase64URL: "c3luYy1zZWNyZXQ",
        pairedAt: "2026-05-22T00:00:00Z"
    )
}

private func makeUnpairedMacSnapshot() -> SecureMacConnectionSnapshot {
    SecureMacConnectionSnapshot(
        macHost: "",
        macPort: SecureMacConnectionSettings.defaultPort,
        macFingerprint: "",
        macName: "",
        macModel: "",
        deviceID: "",
        sharedSecretBase64URL: "",
        pairedAt: ""
    )
}
