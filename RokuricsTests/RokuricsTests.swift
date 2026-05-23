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
        studyFiling: StudyFilingPath? = nil
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
            uploadStatus: uploadStatus,
            studyFiling: studyFiling
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
}

@MainActor
private final class FakeSecureMacConnectionSnapshotProvider: SecureMacConnectionSnapshotProviding {
    var snapshot: SecureMacConnectionSnapshot

    init(snapshot: SecureMacConnectionSnapshot) {
        self.snapshot = snapshot
    }
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
