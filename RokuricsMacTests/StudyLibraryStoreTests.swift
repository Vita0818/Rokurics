//
//  StudyLibraryStoreTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/5/17.
//

import Foundation
import Testing
@testable import RokuricsMac

struct StudyLibraryStoreTests {
    @Test func studyLibraryHeaderUsesChineseTitleWithoutLargeIcon() {
        #expect(MacStudyLibraryHeaderModel.title == "学习库")
        #expect(!MacStudyLibraryHeaderModel.title.contains("Study Library"))
        #expect(!MacStudyLibraryHeaderModel.showsLeadingIcon)
    }

    @Test func studyTagEncodesAndDecodes() throws {
        let tag = StudyTag(
            namespace: "subject",
            value: "线性代数",
            displayName: "Linear Algebra",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let data = try Self.encoder.encode(tag)
        let decoded = try Self.decoder.decode(StudyTag.self, from: data)

        #expect(decoded.namespace == "subject")
        #expect(decoded.value == "线性代数")
        #expect(decoded.displayName == "Linear Algebra")
        #expect(decoded.id == "subject:线性代数")
    }

    @Test func studyFilingPathEncodesAndDecodes() throws {
        let filing = StudyFilingPath(
            type: "课堂",
            subject: "线性代数",
            chapter: "矩阵",
            topic: "矩阵乘法"
        )

        let data = try Self.encoder.encode(filing)
        let decoded = try Self.decoder.decode(StudyFilingPath.self, from: data)

        #expect(decoded == filing)
        #expect(decoded.displaySummary == "课堂 / 线性代数 / 矩阵 / 矩阵乘法")
    }

    @Test func selectingTypeClearsLowerFilingLevels() {
        var draft = StudyFilingSelectionDraft(
            path: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )

        draft.select(.type, value: "复习")

        #expect(draft.type == "复习")
        #expect(draft.subject.isEmpty)
        #expect(draft.chapter.isEmpty)
        #expect(draft.topic.isEmpty)
    }

    @Test func selectingSubjectClearsChapterAndTopic() {
        var draft = StudyFilingSelectionDraft(
            path: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )

        draft.select(.subject, value: "高等数学")

        #expect(draft.type == "课堂")
        #expect(draft.subject == "高等数学")
        #expect(draft.chapter.isEmpty)
        #expect(draft.topic.isEmpty)
    }

    @Test func selectingChapterClearsTopic() {
        var draft = StudyFilingSelectionDraft(
            path: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )

        draft.select(.chapter, value: "行列式")

        #expect(draft.type == "课堂")
        #expect(draft.subject == "线性代数")
        #expect(draft.chapter == "行列式")
        #expect(draft.topic.isEmpty)
    }

    @Test func filingSelectionFlowStopsAfterTopicCommit() {
        #expect(StudyFilingSelectionFlow.nextLevelAfterCommit(.type) == .subject)
        #expect(StudyFilingSelectionFlow.nextLevelAfterCommit(.subject) == .chapter)
        #expect(StudyFilingSelectionFlow.nextLevelAfterCommit(.chapter) == .topic)
        #expect(StudyFilingSelectionFlow.nextLevelAfterCommit(.topic) == nil)
    }

    @Test func selectingTopicKeepsAncestorFilingValues() {
        var draft = StudyFilingSelectionDraft(
            path: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵")
        )

        draft.select(.topic, value: "矩阵乘法")

        #expect(draft.type == "课堂")
        #expect(draft.subject == "线性代数")
        #expect(draft.chapter == "矩阵")
        #expect(draft.topic == "矩阵乘法")
    }

    @Test func filingCandidatesAreFilteredBySelectedAncestors() {
        let items = Self.makeFilteredCandidateItems()
        let extraTopicFolder = StudyFolderMetadata(
            name: "逆矩阵",
            level: .topic,
            path: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "逆矩阵")
        )

        let subjects = StudyFilingCandidateResolver.candidates(
            for: .subject,
            current: StudyFilingPath(type: "课堂"),
            items: items,
            folders: []
        )
        let chapters = StudyFilingCandidateResolver.candidates(
            for: .chapter,
            current: StudyFilingPath(type: "课堂", subject: "线性代数"),
            items: items,
            folders: []
        )
        let topics = StudyFilingCandidateResolver.candidates(
            for: .topic,
            current: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵"),
            items: items,
            folders: [extraTopicFolder]
        )

        #expect(Set(subjects) == Set(["线性代数", "高等数学"]))
        #expect(Set(chapters) == Set(["矩阵", "行列式"]))
        #expect(Set(topics) == Set(["矩阵乘法", "逆矩阵"]))
    }

    @Test func studyItemMetadataEncodesAndDecodes() throws {
        let metadata = StudyItemMetadata(
            recordingID: "recording-01",
            sanitizedRecordingID: "recording-01",
            title: "矩阵乘法",
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 90,
            transcriptRelativePath: "transcripts/1970-01-01/recording-01/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/recording-01/transcript.md",
            noteRelativePath: "notes/1970-01-01/recording-01/note.md",
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法"),
            tags: [
                StudyTag(namespace: "subject", value: "线性代数"),
                StudyTag(namespace: "topic", value: "矩阵乘法")
            ],
            customProperties: ["teacher": "Vita"],
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let data = try Self.encoder.encode(metadata)
        let decoded = try Self.decoder.decode(StudyItemMetadata.self, from: data)

        #expect(decoded == metadata)
        #expect(decoded.hasTranscript)
        #expect(decoded.hasNote)
        #expect(decoded.studyFiling?.topic == "矩阵乘法")
        #expect(decoded.kind == .recordingBundle)
        #expect(decoded.itemID == StudyItemMetadata.recordingBundleItemID(for: "recording-01"))
        #expect(decoded.customProperties["teacher"] == "Vita")
    }

    @Test func studyItemKindEncodesAndDecodes() throws {
        let data = try Self.encoder.encode(StudyItemKind.standaloneNote)
        let decoded = try Self.decoder.decode(StudyItemKind.self, from: data)

        #expect(decoded == .standaloneNote)
    }

    @Test func standaloneNoteStudyItemMetadataEncodesAndDecodes() throws {
        let metadata = StudyItemMetadata(
            itemID: "item_note_manual_01",
            kind: .standaloneNote,
            title: "格林公式整理",
            createdAt: Date(timeIntervalSince1970: 2_100),
            updatedAt: Date(timeIntervalSince1970: 2_200),
            filing: StudyFilingPath(type: "课堂", subject: "高等数学", chapter: "多元函数积分", topic: "格林公式"),
            tags: [StudyTag(namespace: "topic", value: "格林公式")],
            folderIDs: ["folder_topic_green"],
            noteRelativePath: "notes/standalone/green/note.md",
            sourceDescription: "manual"
        )

        let data = try Self.encoder.encode(metadata)
        let decoded = try Self.decoder.decode(StudyItemMetadata.self, from: data)

        #expect(decoded == metadata)
        #expect(decoded.kind == .standaloneNote)
        #expect(decoded.recordingID == nil)
        #expect(decoded.audioRelativePath == nil)
        #expect(decoded.transcriptRelativePath == nil)
        #expect(decoded.noteRelativePath == "notes/standalone/green/note.md")
    }

    @Test func studyFolderMetadataEncodesAndDecodes() throws {
        let folder = StudyFolderMetadata(
            folderID: "folder_topic_matrix_multiplication",
            name: "矩阵乘法",
            level: .topic,
            path: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法"),
            parentFolderID: "folder_chapter_matrix",
            childFolderIDs: [],
            itemIDs: ["item_recording_recording-01"],
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_100),
            colorToken: .purple,
            isTrashed: true,
            trashedAt: Date(timeIntervalSince1970: 1_200),
            customProperties: ["color": "aqua"]
        )

        let data = try Self.encoder.encode(folder)
        let decoded = try Self.decoder.decode(StudyFolderMetadata.self, from: data)

        #expect(decoded == folder)
        #expect(decoded.itemIDs == ["item_recording_recording-01"])
        #expect(decoded.path.topic == "矩阵乘法")
        #expect(decoded.colorToken == .purple)
        #expect(decoded.isTrashed)
        #expect(decoded.trashedAt == Date(timeIntervalSince1970: 1_200))
    }

    @Test func legacyInboxItemWithoutMetadataBuildsDefaultStudyMetadata() {
        let item = makeInboxItem(
            id: "legacy study item",
            title: "录音 2026-05-17 14:27",
            transcriptRelativePath: "transcripts/2026-05-17/legacy/transcript.json",
            noteRelativePath: nil
        )

        let metadata = StudyItemMetadata.defaultMetadata(for: item)

        #expect(metadata.recordingID == "legacy study item")
        #expect(metadata.itemID == StudyItemMetadata.recordingBundleItemID(for: "legacy study item"))
        #expect(metadata.kind == .recordingBundle)
        #expect(metadata.title == "录音 2026-05-17 14:27")
        #expect(metadata.sanitizedRecordingID == "legacy_study_item")
        #expect(metadata.hasTranscript)
        #expect(!metadata.hasNote)
        #expect(metadata.tags.isEmpty)
    }

    @Test func savedTagsCanBeReloadedFromStudyMetadataStore() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try saveInboxRecording(id: "study-save-01", title: "保存标签", store: fileStore)
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)

        try store.updateTags(for: "study-save-01", tags: [
            StudyTag(namespace: "subject", value: "线性代数"),
            StudyTag(namespace: "chapter", value: "矩阵"),
            StudyTag(namespace: "exam", value: "期末")
        ])
        let reloaded = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let item = try #require(reloaded.item(recordingID: "study-save-01"))

        #expect(item.tags.contains(StudyTag(namespace: "subject", value: "线性代数")))
        #expect(item.tags.contains(StudyTag(namespace: "chapter", value: "矩阵")))
        #expect(item.tags.contains(StudyTag(namespace: "exam", value: "期末")))
    }

    @Test func defaultHierarchyRuleIsCourseView() throws {
        let (_, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let store = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)

        #expect(store.selectedHierarchyRule.name == "课程视图")
        #expect(store.selectedHierarchyRule.levels == ["type", "subject", "chapter", "topic"])
    }

    @Test func typeSubjectChapterTopicFilingBuildsVirtualTree() {
        let item = StudyItemMetadata(
            recordingID: "matrix-01",
            title: "矩阵乘法",
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 120,
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )

        let tree = VirtualStudyTreeBuilder.build(items: [item], rule: .defaultCourseView)
        let type = tree.first
        let subject = type?.children.first
        let chapter = subject?.children.first
        let topic = chapter?.children.first

        #expect(type?.levelKey == "type")
        #expect(type?.levelValue == "课堂")
        #expect(subject?.levelKey == "subject")
        #expect(subject?.levelValue == "线性代数")
        #expect(chapter?.levelKey == "chapter")
        #expect(chapter?.levelValue == "矩阵")
        #expect(topic?.levelKey == "topic")
        #expect(topic?.levelValue == "矩阵乘法")
        #expect(topic?.items.compactMap(\.recordingID) == ["matrix-01"])
    }

    @Test func finderBrowserRootLevelBuildsTypeFolders() {
        let items = [
            StudyItemMetadata(
                recordingID: "browser-root-01",
                title: "课堂",
                createdAt: Date(timeIntervalSince1970: 1),
                duration: 1,
                studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
            ),
            StudyItemMetadata(
                recordingID: "browser-root-02",
                title: "复习",
                createdAt: Date(timeIntervalSince1970: 2),
                duration: 1,
                studyFiling: StudyFilingPath(type: "复习", subject: "高等数学", chapter: "积分", topic: "格林公式")
            )
        ]

        let content = StudyLibraryBrowser.content(items: items, path: StudyBrowsePath())

        #expect(content.folders.map(\.title) == ["复习", "课堂"])
        #expect(content.folders.map(\.itemCount) == [1, 1])
        #expect(content.items.isEmpty)
    }

    @Test func finderBrowserBuildsEachNestedFolderLevel() {
        let item = StudyItemMetadata(
            recordingID: "browser-levels-01",
            title: "矩阵乘法",
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 1,
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )
        let typePath = StudyBrowsePath(components: ["课堂"])
        let subjectPath = StudyBrowsePath(components: ["课堂", "线性代数"])
        let chapterPath = StudyBrowsePath(components: ["课堂", "线性代数", "矩阵"])
        let topicPath = StudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"])

        let subjectContent = StudyLibraryBrowser.content(items: [item], path: typePath)
        let chapterContent = StudyLibraryBrowser.content(items: [item], path: subjectPath)
        let topicContent = StudyLibraryBrowser.content(items: [item], path: chapterPath)
        let recordingContent = StudyLibraryBrowser.content(items: [item], path: topicPath)

        #expect(subjectContent.folders.map(\.title) == ["线性代数"])
        #expect(chapterContent.folders.map(\.title) == ["矩阵"])
        #expect(topicContent.folders.map(\.title) == ["矩阵乘法"])
        #expect(recordingContent.items.compactMap(\.recordingID) == ["browser-levels-01"])
        #expect(recordingContent.folders.isEmpty)
    }

    @Test func emptyTypeFolderMetadataAppearsAtRoot() {
        let folder = StudyFolderMetadata(
            name: "课堂",
            level: .type,
            path: StudyFilingPath(type: "课堂"),
            itemIDs: []
        )

        let content = StudyLibraryBrowser.content(items: [], folders: [folder], path: StudyBrowsePath())

        #expect(content.folders.map(\.title) == ["课堂"])
        #expect(content.folders.map(\.itemCount) == [0])
    }

    @Test func emptyNestedFolderMetadataAppearsAtMatchingLevel() {
        let subject = StudyFolderMetadata(
            name: "高等数学",
            level: .subject,
            path: StudyFilingPath(type: "课堂", subject: "高等数学")
        )
        let chapter = StudyFolderMetadata(
            name: "多元函数积分",
            level: .chapter,
            path: StudyFilingPath(type: "课堂", subject: "高等数学", chapter: "多元函数积分")
        )
        let topic = StudyFolderMetadata(
            name: "格林公式",
            level: .topic,
            path: StudyFilingPath(type: "课堂", subject: "高等数学", chapter: "多元函数积分", topic: "格林公式")
        )

        let subjectContent = StudyLibraryBrowser.content(items: [], folders: [subject, chapter, topic], path: StudyBrowsePath(components: ["课堂"]))
        let chapterContent = StudyLibraryBrowser.content(items: [], folders: [subject, chapter, topic], path: StudyBrowsePath(components: ["课堂", "高等数学"]))
        let topicContent = StudyLibraryBrowser.content(items: [], folders: [subject, chapter, topic], path: StudyBrowsePath(components: ["课堂", "高等数学", "多元函数积分"]))

        #expect(subjectContent.folders.map(\.title) == ["高等数学"])
        #expect(chapterContent.folders.map(\.title) == ["多元函数积分"])
        #expect(topicContent.folders.map(\.title) == ["格林公式"])
    }

    @Test func folderMetadataUsesItemIDInsteadOfTitle() {
        let itemID = StudyItemMetadata.recordingBundleItemID(for: "rename-stable-01")
        let folder = StudyFolderMetadata(
            name: "矩阵乘法",
            level: .topic,
            path: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法"),
            itemIDs: [itemID]
        )

        #expect(folder.itemIDs == [itemID])
        #expect(!folder.itemIDs.contains("矩阵乘法"))
    }

    @Test func itemFilingWinsWhenFolderIndexDisagrees() {
        let item = StudyItemMetadata(
            recordingID: "conflict-01",
            title: "真实位置",
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 1,
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )
        let staleFolder = StudyFolderMetadata(
            name: "旧主题",
            level: .topic,
            path: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "旧主题"),
            itemIDs: [item.itemID]
        )

        let realContent = StudyLibraryBrowser.content(
            items: [item],
            folders: [staleFolder],
            path: StudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"])
        )
        let staleParentContent = StudyLibraryBrowser.content(
            items: [item],
            folders: [staleFolder],
            path: StudyBrowsePath(components: ["课堂", "线性代数", "矩阵"])
        )

        #expect(realContent.items.map(\.itemID) == [item.itemID])
        #expect(staleParentContent.folders.first { $0.title == "旧主题" }?.itemCount == 0)
    }

    @Test func orphanFolderItemReferenceDoesNotCrashBrowser() {
        let folder = StudyFolderMetadata(
            name: "孤儿引用",
            level: .type,
            path: StudyFilingPath(type: "孤儿引用"),
            itemIDs: ["missing-item"]
        )

        let content = StudyLibraryBrowser.content(items: [], folders: [folder], path: StudyBrowsePath())

        #expect(content.folders.map(\.title) == ["孤儿引用"])
        #expect(content.folders.map(\.itemCount) == [0])
    }

    @Test func finderBrowserShowsUncategorizedRecordingsDirectly() {
        let item = StudyItemMetadata(
            recordingID: "browser-uncategorized-01",
            title: "未分类",
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 1
        )

        let rootContent = StudyLibraryBrowser.content(items: [item], path: StudyBrowsePath())
        let uncategorizedContent = StudyLibraryBrowser.content(
            items: [item],
            path: StudyBrowsePath(components: [StudyHierarchyRule.uncategorizedValue])
        )

        #expect(rootContent.folders.map(\.title) == [StudyHierarchyRule.uncategorizedValue])
        #expect(uncategorizedContent.items.compactMap(\.recordingID) == ["browser-uncategorized-01"])
        #expect(uncategorizedContent.folders.isEmpty)
    }

    @Test func finderBrowserMissingLowerFieldsStayVisible() {
        let item = StudyItemMetadata(
            recordingID: "browser-missing-01",
            title: "缺课程",
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 1,
            studyFiling: StudyFilingPath(type: "课堂")
        )

        let subjectContent = StudyLibraryBrowser.content(items: [item], path: StudyBrowsePath(components: ["课堂"]))
        let chapterContent = StudyLibraryBrowser.content(items: [item], path: StudyBrowsePath(components: ["课堂", StudyHierarchyRule.missingValue]))
        let topicContent = StudyLibraryBrowser.content(items: [item], path: StudyBrowsePath(components: ["课堂", StudyHierarchyRule.missingValue, StudyHierarchyRule.missingValue]))
        let recordingContent = StudyLibraryBrowser.content(items: [item], path: StudyBrowsePath(components: ["课堂", StudyHierarchyRule.missingValue, StudyHierarchyRule.missingValue, StudyHierarchyRule.missingValue]))

        #expect(subjectContent.folders.map(\.title) == [StudyHierarchyRule.missingValue])
        #expect(chapterContent.folders.map(\.title) == [StudyHierarchyRule.missingValue])
        #expect(topicContent.folders.map(\.title) == [StudyHierarchyRule.missingValue])
        #expect(recordingContent.items.compactMap(\.recordingID) == ["browser-missing-01"])
    }

    @Test func finderBrowserBreadcrumbPathsNavigateByDepth() {
        let path = StudyBrowsePath(components: ["课堂", "线性代数", "矩阵"])
        let breadcrumbs = StudyLibraryBrowser.breadcrumbs(for: path)

        #expect(breadcrumbs.map(\.title) == ["学习库", "课堂", "线性代数", "矩阵"])
        #expect(breadcrumbs[1].path.components == ["课堂"])
        #expect(breadcrumbs[2].path.components == ["课堂", "线性代数"])
        #expect(path.parent.components == ["课堂", "线性代数"])
    }

    @Test func finderBrowserPathUpdatesAfterFilingChanges() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try saveInboxRecording(id: "browser-update-01", title: "路径更新", store: fileStore)
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)

        #expect(StudyLibraryBrowser.content(items: store.allStudyItems, path: StudyBrowsePath()).folders.map(\.title) == [StudyHierarchyRule.uncategorizedValue])

        try store.updateFiling(
            for: "browser-update-01",
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )

        let rootContent = StudyLibraryBrowser.content(items: store.allStudyItems, path: StudyBrowsePath())
        let finalContent = StudyLibraryBrowser.content(
            items: store.allStudyItems,
            path: StudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"])
        )

        #expect(rootContent.folders.map(\.title) == ["课堂"])
        #expect(finalContent.items.compactMap(\.recordingID) == ["browser-update-01"])
    }

    @Test func creatingVirtualFolderWritesMetadataAndShowsEmptyFolder() throws {
        let (_, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let store = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)

        let folder = try store.createFolder(named: "课堂", at: StudyBrowsePath())
        let reloaded = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)
        let content = StudyLibraryBrowser.content(
            items: reloaded.allStudyItems,
            folders: reloaded.allStudyFolders,
            path: StudyBrowsePath()
        )

        #expect(folder.level == .type)
        #expect(folder.itemIDs.isEmpty)
        #expect(reloaded.folder(folderID: folder.folderID)?.name == "课堂")
        #expect(content.folders.map(\.title) == ["课堂"])
    }

    @Test func creatingNestedFilingFoldersWritesFolderMetadata() throws {
        let (_, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let store = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)

        let type = try store.createFolder(named: "课堂", at: StudyBrowsePath())
        let subject = try store.createFolder(named: "线性代数", at: StudyBrowsePath(components: ["课堂"]))
        let chapter = try store.createFolder(named: "矩阵", at: StudyBrowsePath(components: ["课堂", "线性代数"]))
        let topic = try store.createFolder(named: "矩阵乘法", at: StudyBrowsePath(components: ["课堂", "线性代数", "矩阵"]))
        let reloaded = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)

        #expect(type.level == .type)
        #expect(subject.level == .subject)
        #expect(chapter.level == .chapter)
        #expect(topic.level == .topic)
        #expect(reloaded.folder(folderID: subject.folderID)?.path.subject == "线性代数")
        #expect(reloaded.folder(folderID: chapter.folderID)?.path.chapter == "矩阵")
        #expect(reloaded.folder(folderID: topic.folderID)?.path.topic == "矩阵乘法")
    }

    @Test func standaloneNoteWithoutRecordingAudioOrTranscriptCanExistInStore() throws {
        let (_, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let note = StudyItemMetadata(
            itemID: "item_note_standalone_store",
            kind: .standaloneNote,
            title: "独立笔记",
            createdAt: Date(timeIntervalSince1970: 2_500),
            filing: StudyFilingPath(type: "复习", subject: "高等数学"),
            noteRelativePath: "notes/standalone/review/note.md"
        )
        let store = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)

        try store.save(note)
        let reloaded = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)
        let item = try #require(reloaded.item(itemID: note.itemID))

        #expect(item.kind == .standaloneNote)
        #expect(item.recordingID == nil)
        #expect(item.audioRelativePath == nil)
        #expect(item.transcriptRelativePath == nil)
        #expect(item.noteRelativePath == "notes/standalone/review/note.md")
    }

    @Test func finderBrowserIncludesItemDerivedAndEmptyFoldersTogether() {
        let item = StudyItemMetadata(
            recordingID: "mixed-tree-01",
            title: "矩阵乘法",
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 1,
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )
        let emptyFolder = StudyFolderMetadata(
            name: "复习",
            level: .type,
            path: StudyFilingPath(type: "复习")
        )

        let content = StudyLibraryBrowser.content(items: [item], folders: [emptyFolder], path: StudyBrowsePath())

        #expect(content.folders.map(\.title) == ["复习", "课堂"])
        #expect(content.folders.map(\.itemCount) == [0, 1])
    }

    @Test func moveItemUpdatesItemAndFolderReferencesWithoutMovingResources() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try saveInboxRecording(id: "move-item-01", title: "移动对象", store: fileStore)
        try fileStore.updateTranscriptionStatus(
            recordingID: "move-item-01",
            status: "transcribed",
            transcriptRelativePath: "transcripts/1970-01-01/move-item-01/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/move-item-01/transcript.md",
            providerID: "whisper.cpp",
            modelName: "small",
            startedAt: Date(timeIntervalSince1970: 1_900),
            completedAt: Date(timeIntervalSince1970: 1_901),
            errorMessage: nil
        )
        try fileStore.updateNoteGenerationStatus(
            recordingID: "move-item-01",
            status: "generated",
            noteRelativePath: "notes/1970-01-01/move-item-01/note.md",
            generatedAt: Date(timeIntervalSince1970: 2_000),
            providerID: "mockNoteGenerationProvider",
            modelName: "mock",
            endpointDescription: nil,
            errorMessage: nil
        )
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let target = try store.createFolder(
            named: "格林公式",
            at: StudyBrowsePath(components: ["课堂", "高等数学", "多元函数积分"])
        )
        let before = try #require(store.item(recordingID: "move-item-01"))

        try store.moveItem(itemID: before.itemID, toFolderID: target.folderID)

        let moved = try #require(store.item(recordingID: "move-item-01"))
        let folder = try #require(store.folder(folderID: target.folderID))
        #expect(moved.filing.topic == "格林公式")
        #expect(moved.folderIDs == [target.folderID])
        #expect(folder.itemIDs == [before.itemID])
        #expect(moved.recordingID == before.recordingID)
        #expect(moved.audioRelativePath == before.audioRelativePath)
        #expect(moved.transcriptRelativePath == before.transcriptRelativePath)
        #expect(moved.transcriptMarkdownRelativePath == before.transcriptMarkdownRelativePath)
        #expect(moved.noteRelativePath == before.noteRelativePath)
    }

    @Test func renamingFolderKeepsFolderIDAndUpdatesItemFiling() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let filing = StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        try saveInboxRecording(id: "folder-rename-01", title: "矩阵乘法", store: fileStore, studyFiling: filing)
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let folderID = StudyFolderMetadata.folderID(for: .topic, path: filing)
        let browsePath = StudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"])

        let renamed = try store.renameFolder(path: browsePath, level: .topic, to: "逆矩阵")
        let item = try #require(store.item(recordingID: "folder-rename-01"))

        #expect(renamed.folderID == folderID)
        #expect(renamed.name == "逆矩阵")
        #expect(item.filing.topic == "逆矩阵")
        #expect(item.folderIDs.contains(folderID))
    }

    @Test func renamingStudyItemKeepsStableIDsAndResourcePaths() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try saveInboxRecording(id: "item-rename-01", title: "旧标题", store: fileStore)
        try fileStore.updateTranscriptionStatus(
            recordingID: "item-rename-01",
            status: "transcribed",
            transcriptRelativePath: "transcripts/1970-01-01/item-rename-01/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/item-rename-01/transcript.md",
            providerID: "whisper.cpp",
            modelName: "small",
            startedAt: Date(timeIntervalSince1970: 1_900),
            completedAt: Date(timeIntervalSince1970: 1_901),
            errorMessage: nil
        )
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let before = try #require(store.item(recordingID: "item-rename-01"))

        let renamed = try store.renameItem(itemID: before.itemID, to: "新标题")

        #expect(renamed.title == "新标题")
        #expect(renamed.itemID == before.itemID)
        #expect(renamed.recordingID == before.recordingID)
        #expect(renamed.audioRelativePath == before.audioRelativePath)
        #expect(renamed.transcriptRelativePath == before.transcriptRelativePath)
        #expect(renamed.transcriptMarkdownRelativePath == before.transcriptMarkdownRelativePath)
    }

    @Test func emptyFolderRenameDoesNotSaveBlankName() throws {
        let (_, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let store = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)
        let folder = try store.createFolder(named: "课堂", at: StudyBrowsePath())

        let renamed = try store.renameFolder(folderID: folder.folderID, to: "   ")

        #expect(renamed.name == "课堂")
        #expect(store.folder(folderID: folder.folderID)?.name == "课堂")
    }

    @Test func duplicateSiblingFolderRenameFailsSafely() throws {
        let (_, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let store = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)
        let original = try store.createFolder(named: "课堂", at: StudyBrowsePath())
        _ = try store.createFolder(named: "复习", at: StudyBrowsePath())

        do {
            _ = try store.renameFolder(folderID: original.folderID, to: "复习")
            Issue.record("duplicate sibling rename should fail")
        } catch {
            #expect(error.localizedDescription == "study_folder_duplicate_name")
        }
    }

    @Test func folderColorPersistsWithoutChangingItemIDs() throws {
        let (_, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let store = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)
        let folder = try store.createFolder(named: "课堂", at: StudyBrowsePath())

        let colored = try store.setFolderColor(folderID: folder.folderID, colorToken: .mint)
        let reloaded = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)
        let loadedFolder = try #require(reloaded.folder(folderID: folder.folderID))

        #expect(colored.colorToken == .mint)
        #expect(loadedFolder.colorToken == .mint)
        #expect(loadedFolder.itemIDs == folder.itemIDs)
        #expect(loadedFolder.folderID == folder.folderID)
    }

    @Test func movingEmptyFolderToTrashHidesItWithoutDeletingMetadata() throws {
        let (_, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let store = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)
        let folder = try store.createFolder(named: "课堂", at: StudyBrowsePath())

        let trashed = try store.moveFolderToTrash(folderID: folder.folderID)
        let reloaded = StudyLibraryStore(rootURL: rootURL, listenForInboxChanges: false)
        let storedFolder = try #require(reloaded.folder(folderID: folder.folderID))
        let content = StudyLibraryBrowser.content(
            items: reloaded.allStudyItems,
            folders: reloaded.allStudyFolders,
            path: StudyBrowsePath()
        )

        #expect(trashed.isTrashed)
        #expect(storedFolder.isTrashed)
        #expect(!content.folders.contains { $0.folderID == folder.folderID })
    }

    @Test func movingNonEmptyFolderToTrashFailsWithoutDeletingItems() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let filing = StudyFilingPath(type: "课堂")
        try saveInboxRecording(id: "folder-trash-01", title: "课堂录音", store: fileStore, studyFiling: filing)
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let folder = try store.createFolder(named: "课堂", at: StudyBrowsePath())

        do {
            _ = try store.moveFolderToTrash(folderID: folder.folderID)
            Issue.record("non-empty folder trash should fail safely")
        } catch {
            #expect(error.localizedDescription == "study_folder_not_empty")
        }

        #expect(store.item(recordingID: "folder-trash-01") != nil)
        #expect(store.folder(folderID: folder.folderID)?.isTrashed == false)
    }

    @Test func missingSubjectFallsIntoUncategorized() {
        let item = StudyItemMetadata(
            recordingID: "uncategorized-01",
            title: "无科目录音",
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 60,
            tags: [
                StudyTag(namespace: "chapter", value: "矩阵"),
                StudyTag(namespace: "topic", value: "行列式")
            ]
        )

        let tree = VirtualStudyTreeBuilder.build(items: [item], rule: .defaultCourseView)

        #expect(tree.first?.levelValue == StudyHierarchyRule.uncategorizedValue)
        #expect(tree.first?.children.first?.levelValue == StudyHierarchyRule.missingValue)
        #expect(tree.first?.children.first?.children.first?.levelValue == "矩阵")
    }

    @Test func missingChapterAndTopicDoNotHideItem() {
        let item = StudyItemMetadata(
            recordingID: "missing-lower-01",
            title: "缺少下层",
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 60,
            studyFiling: StudyFilingPath(type: "复习", subject: "高等数学")
        )

        let tree = VirtualStudyTreeBuilder.build(items: [item], rule: .defaultCourseView)
        let subject = tree.first?.children.first
        let chapter = subject?.children.first
        let topic = chapter?.children.first

        #expect(tree.first?.levelValue == "复习")
        #expect(subject?.levelValue == "高等数学")
        #expect(chapter?.levelValue == StudyHierarchyRule.missingValue)
        #expect(topic?.levelValue == StudyHierarchyRule.missingValue)
        #expect(topic?.items.compactMap(\.recordingID) == ["missing-lower-01"])
    }

    @Test func itemWithMultipleTagsCanAppearInMultipleVirtualLocations() {
        let item = StudyItemMetadata(
            recordingID: "multi-subject-01",
            title: "交叉内容",
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 60,
            tags: [
                StudyTag(namespace: "subject", value: "线性代数"),
                StudyTag(namespace: "subject", value: "机器学习"),
                StudyTag(namespace: "topic", value: "特征向量")
            ]
        )

        let tree = VirtualStudyTreeBuilder.build(items: [item], rule: .defaultCourseView)
        let subjects = tree.first?.children.map(\.levelValue) ?? []

        #expect(subjects.contains("线性代数"))
        #expect(subjects.contains("机器学习"))
        #expect(tree.flatMap { $0.children }.flatMap { $0.children }.flatMap { $0.children }.flatMap { $0.items }.count == 2)
    }

    @Test func filingCandidatesAreExtractedFromRecordings() {
        let items = [
            StudyItemMetadata(
                recordingID: "candidate-01",
                title: "A",
                createdAt: Date(timeIntervalSince1970: 1),
                duration: 1,
                studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
            ),
            StudyItemMetadata(
                recordingID: "candidate-02",
                title: "B",
                createdAt: Date(timeIntervalSince1970: 2),
                duration: 1,
                studyFiling: StudyFilingPath(type: "复习", subject: "高等数学", chapter: "矩阵", topic: "格林公式")
            )
        ]

        let candidates = StudyFilingCandidates.collect(from: items)

        #expect(Set(candidates.types) == Set(["复习", "课堂"]))
        #expect(Set(candidates.subjects) == Set(["线性代数", "高等数学"]))
        #expect(candidates.chapters == ["矩阵"])
        #expect(Set(candidates.topics) == Set(["格林公式", "矩阵乘法"]))
    }

    @Test func customNamespacesCanBeSaved() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try saveInboxRecording(id: "custom-tag-01", title: "自定义标签", store: fileStore)
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)

        try store.updateTags(for: "custom-tag-01", tags: [
            StudyTag(namespace: "exam", value: "期末"),
            StudyTag(namespace: "status", value: "待复习")
        ])
        let item = try #require(store.item(recordingID: "custom-tag-01"))

        #expect(item.tags.contains(StudyTag(namespace: "exam", value: "期末")))
        #expect(item.tags.contains(StudyTag(namespace: "status", value: "待复习")))
    }

    @Test func studyLibraryStoreDoesNotMoveTranscriptOrNoteFiles() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try saveInboxRecording(id: "no-move-01", title: "不移动文件", store: fileStore)
        let transcriptURL = try writeTranscriptFile(rootURL: rootURL, recordingID: "no-move-01")
        let noteURL = try writeNoteFile(rootURL: rootURL, recordingID: "no-move-01")
        try fileStore.updateTranscriptionStatus(
            recordingID: "no-move-01",
            status: "transcribed",
            transcriptRelativePath: "transcripts/1970-01-01/no-move-01/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/no-move-01/transcript.md",
            providerID: "whisper.cpp",
            modelName: "small",
            startedAt: Date(timeIntervalSince1970: 1_900),
            completedAt: Date(timeIntervalSince1970: 1_901),
            errorMessage: nil
        )
        try fileStore.updateNoteGenerationStatus(
            recordingID: "no-move-01",
            status: "generated",
            noteRelativePath: "notes/1970-01-01/no-move-01/note.md",
            generatedAt: Date(timeIntervalSince1970: 2_000),
            providerID: "mockNoteGenerationProvider",
            modelName: "mock",
            endpointDescription: nil,
            errorMessage: nil
        )
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)

        try store.updateTags(for: "no-move-01", tags: [StudyTag(namespace: "subject", value: "物理")])

        #expect(FileManager.default.fileExists(atPath: transcriptURL.path))
        #expect(FileManager.default.fileExists(atPath: noteURL.path))
        #expect(try String(contentsOf: transcriptURL, encoding: .utf8) == "# transcript")
        #expect(try String(contentsOf: noteURL, encoding: .utf8) == "# note")
    }

    @Test func receiveJSONWithoutNotePathStillAppearsInStudyLibrary() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try saveInboxRecording(id: "missing-note-path-01", title: "无笔记路径", store: fileStore)
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let item = try #require(store.item(recordingID: "missing-note-path-01"))

        #expect(item.title == "无笔记路径")
        #expect(!item.hasNote)
        #expect(item.noteRelativePath == nil)
    }

    @Test func generatedNoteRelativePathIsVisibleAfterRefresh() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try saveInboxRecording(id: "note-path-01", title: "有笔记路径", store: fileStore)
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        try fileStore.updateNoteGenerationStatus(
            recordingID: "note-path-01",
            status: "generated",
            noteRelativePath: "notes/1970-01-01/note-path-01/note.md",
            generatedAt: Date(timeIntervalSince1970: 2_000),
            providerID: "openAICompatible",
            modelName: "google/gemma-4-e4b",
            endpointDescription: "127.0.0.1",
            errorMessage: nil
        )

        store.refresh()
        let item = try #require(store.item(recordingID: "note-path-01"))

        #expect(item.hasNote)
        #expect(item.noteRelativePath == "notes/1970-01-01/note-path-01/note.md")
    }

    @Test func incomingMetadataStudyFilingIsWrittenToReceiveJSONAndStudyLibrary() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let filing = StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")

        try saveInboxRecording(id: "filing-receive-01", title: "归档上传", store: fileStore, studyFiling: filing)
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "filing-receive-01")
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let item = try #require(store.item(recordingID: "filing-receive-01"))

        #expect(record.studyFiling == filing)
        #expect(item.studyFiling == filing)
        #expect(store.studyTree.first?.levelValue == "课堂")
    }

    @Test func oldReceiveJSONWithoutStudyFilingDecodes() throws {
        let record = RecordingReceiveRecord(
            recordingID: "legacy-filing",
            sanitizedRecordingID: "legacy-filing",
            receivedAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            sourceDeviceID: "device",
            sourceDeviceName: "iPhone",
            originalTitle: "旧录音",
            normalizedTitle: "旧录音",
            audioFileName: "audio.m4a",
            originalAudioFileName: "legacy.m4a",
            metadataFileName: "metadata.json",
            status: "received",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            processingStatus: "notStarted",
            suggestedCategory: nil,
            course: nil,
            category: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 6,
            fileSize: 5,
            suggestedFolder: nil,
            userConfirmedFolder: nil,
            checksum: nil,
            audioRelativePath: "audio/inbox/1970-01-01/legacy-filing/audio.m4a",
            metadataRelativePath: "audio/inbox/1970-01-01/legacy-filing/metadata.json"
        )
        var object = try #require(JSONSerialization.jsonObject(with: try Self.encoder.encode(record)) as? [String: Any])
        object.removeValue(forKey: "studyFiling")
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try Self.decoder.decode(RecordingReceiveRecord.self, from: data)

        #expect(decoded.studyFiling == nil)
    }

    @Test func oldIncomingMetadataWithoutStudyFilingDecodes() throws {
        let metadata = IncomingRecordingMetadata(
            id: "legacy-metadata",
            title: "旧上传",
            originalFileName: "legacy.m4a",
            relativeAudioPath: "Recordings/legacy.m4a",
            createdAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            duration: 1,
            format: "m4a",
            codec: "AAC",
            sampleRate: 16_000,
            channels: 1,
            bitrate: 64_000,
            fileSize: 5,
            uploadStatus: "uploaded",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            tags: [],
            sourceDeviceName: "iPhone",
            sourceDeviceID: "device",
            uploadedAt: Date(timeIntervalSince1970: 3)
        )
        var object = try #require(JSONSerialization.jsonObject(with: try Self.encoder.encode(metadata)) as? [String: Any])
        object.removeValue(forKey: "studyFiling")
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try Self.decoder.decode(IncomingRecordingMetadata.self, from: data)

        #expect(decoded.studyFiling == nil)
    }

    @Test func updatingStudyTagsDoesNotChangeReceiveStatuses() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try saveInboxRecording(id: "preserve-receive-01", title: "保持状态", store: fileStore)
        try fileStore.updateTranscriptionStatus(
            recordingID: "preserve-receive-01",
            status: "transcribed",
            transcriptRelativePath: "transcripts/1970-01-01/preserve-receive-01/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/preserve-receive-01/transcript.md",
            providerID: "whisper.cpp",
            modelName: "small",
            startedAt: Date(timeIntervalSince1970: 1_900),
            completedAt: Date(timeIntervalSince1970: 1_901),
            errorMessage: nil
        )
        try fileStore.updateNoteGenerationStatus(
            recordingID: "preserve-receive-01",
            status: "generated",
            noteRelativePath: "notes/1970-01-01/preserve-receive-01/note.md",
            generatedAt: Date(timeIntervalSince1970: 2_000),
            providerID: "openAICompatible",
            modelName: "google/gemma-4-e4b",
            endpointDescription: "127.0.0.1",
            errorMessage: nil
        )
        let before = try readReceiveRecord(rootURL: rootURL, recordingID: "preserve-receive-01")
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)

        try store.updateTags(for: "preserve-receive-01", tags: [
            StudyTag(namespace: "subject", value: "数学"),
            StudyTag(namespace: "status", value: "待复习")
        ])
        let after = try readReceiveRecord(rootURL: rootURL, recordingID: "preserve-receive-01")

        #expect(after.transcriptionStatus == before.transcriptionStatus)
        #expect(after.noteStatus == before.noteStatus)
        #expect(after.noteRelativePath == before.noteRelativePath)
        #expect(after.transcriptMarkdownRelativePath == before.transcriptMarkdownRelativePath)
    }

    @MainActor
    @Test func syncManifestEndpointRejectsUnpairedDevice() {
        let body = Data("{}".utf8)
        let bodyHash = MacSecurityUtilities.sha256Hex(body)
        let timestamp = "1000"
        let nonce = "nonce-sync-unpaired"
        let headers = [
            "Content-Type": "application/json",
            "X-Rokurics-Device-ID": "unknown-device",
            "X-Rokurics-Timestamp": timestamp,
            "X-Rokurics-Nonce": nonce,
            "X-Rokurics-Body-SHA256": bodyHash,
            "X-Rokurics-Signature": "signature"
        ]
        let verifier = RequestVerifier(pairedDeviceProvider: { _ in nil })

        let result = verifier.verify(
            method: "POST",
            path: "/sync/manifest",
            headers: headers,
            body: body,
            now: Date(timeIntervalSince1970: 1_000)
        )

        guard case .rejected(let reason) = result else {
            Issue.record("Expected unpaired sync request to be rejected")
            return
        }
        #expect(reason == "unknown_device")
    }

    @MainActor
    @Test func syncManifestEndpointAcceptsSignedPairedDevice() throws {
        let secret = Data("sync-secret".utf8).base64URLEncodedString()
        let device = PairedDevice(
            id: "device-sync-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: secret,
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
        let body = Data("{}".utf8)
        let bodyHash = MacSecurityUtilities.sha256Hex(body)
        let timestamp = "1000"
        let nonce = "nonce-sync-accepted"
        let payload = ["POST", "/sync/manifest", timestamp, nonce, bodyHash].joined(separator: "\n")
        let signature = try #require(MacSecurityUtilities.hmacSHA256Base64URL(message: payload, secretBase64URL: secret))
        let headers = [
            "Content-Type": "application/json",
            "X-Rokurics-Device-ID": device.id,
            "X-Rokurics-Timestamp": timestamp,
            "X-Rokurics-Nonce": nonce,
            "X-Rokurics-Body-SHA256": bodyHash,
            "X-Rokurics-Signature": signature
        ]
        let verifier = RequestVerifier(pairedDeviceProvider: { id in id == device.id ? device : nil })

        let result = verifier.verify(
            method: "POST",
            path: "/sync/manifest",
            headers: headers,
            body: body,
            now: Date(timeIntervalSince1970: 1_000)
        )

        guard case .accepted(let acceptedDevice) = result else {
            Issue.record("Expected signed sync request to be accepted")
            return
        }
        #expect(acceptedDevice.id == device.id)
    }

    @MainActor
    @Test func uploadEndpointRejectsBadSignatureForPairedDevice() throws {
        let secret = Data("sync-secret".utf8).base64URLEncodedString()
        let device = PairedDevice(
            id: "device-upload-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: secret,
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
        let body = Data("audio".utf8)
        let bodyHash = MacSecurityUtilities.sha256Hex(body)
        let headers = [
            "Content-Type": "audio/m4a",
            "X-Rokurics-Upload-Type": "recording-audio",
            "X-Rokurics-Device-ID": device.id,
            "X-Rokurics-Timestamp": "1000",
            "X-Rokurics-Nonce": "nonce-upload-bad-signature",
            "X-Rokurics-Body-SHA256": bodyHash,
            "X-Rokurics-Signature": "bad-signature"
        ]
        let verifier = RequestVerifier(pairedDeviceProvider: { id in id == device.id ? device : nil })

        let result = verifier.verify(
            method: "POST",
            path: "/upload-recording-audio",
            headers: headers,
            body: body,
            now: Date(timeIntervalSince1970: 1_000)
        )

        guard case .rejected(let reason) = result else {
            Issue.record("Expected bad signature to be rejected")
            return
        }
        #expect(reason == "signature_mismatch")
    }

    @Test func macAppliesIPhoneMetadataOnlyRecordingWithoutPretendingAudioExists() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let remoteItem = StudyItemMetadata(
            recordingID: "iphone-new-metadata",
            title: "iPhone 新录音",
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 32,
            audioRelativePath: "Recordings/iphone-new-metadata.m4a",
            studyFiling: StudyFilingPath(type: "课堂", subject: "物理"),
            updatedAt: Date(timeIntervalSince1970: 2_100),
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted"
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-device",
            generatedAt: Date(timeIntervalSince1970: 2_101),
            items: [remoteItem],
            folders: []
        )

        let result = try store.applySyncManifest(manifest, localDeviceID: "mac-device")
        let synced = try #require(store.item(recordingID: "iphone-new-metadata"))

        #expect(result.appliedItemCount == 1)
        #expect(synced.title == "iPhone 新录音")
        #expect(synced.customProperties["syncedMetadataOnly"] == "true")
        #expect(!synced.asInboxItem().hasAudio)
    }

    @Test func macSyncLastWriteWinsForFilingAndKeepsFolderIndexSafe() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try saveInboxRecording(
            id: "sync-filing-lww",
            title: "旧归档",
            store: fileStore,
            studyFiling: StudyFilingPath(type: "课堂", subject: "数学")
        )
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let existing = try #require(store.item(recordingID: "sync-filing-lww"))
        var remote = existing
        remote.filing = StudyFilingPath(type: "复习", subject: "线性代数", chapter: "矩阵")
        remote.folderIDs = StudyItemMetadata.defaultFolderIDs(for: remote.filing)
        remote.updatedAt = existing.updatedAt.addingTimeInterval(60)
        remote.modifiedByDeviceID = "iphone-device"
        let folder = StudyFolderMetadata(
            name: "矩阵",
            level: .chapter,
            path: remote.filing,
            itemIDs: [remote.itemID],
            updatedAt: remote.updatedAt
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-device",
            generatedAt: remote.updatedAt.addingTimeInterval(1),
            items: [remote],
            folders: [folder]
        )

        _ = try store.applySyncManifest(manifest, localDeviceID: "mac-device")
        let synced = try #require(store.item(recordingID: "sync-filing-lww"))
        let syncedFolder = try #require(store.folder(folderID: remote.folderIDs[0]))

        #expect(synced.filing.subject == "线性代数")
        #expect(syncedFolder.itemIDs.contains(remote.itemID))
    }

    @Test func syncManifestMissingPendingUploadsDecodesAsEmpty() throws {
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-device",
            generatedAt: Date(timeIntervalSince1970: 2_200),
            items: [],
            folders: []
        )
        var object = try #require(JSONSerialization.jsonObject(with: try Self.encoder.encode(manifest)) as? [String: Any])
        object.removeValue(forKey: "pendingUploads")
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try Self.decoder.decode(StudyLibrarySyncManifest.self, from: data)

        #expect(decoded.pendingUploads.isEmpty)
        #expect(decoded.hasValidChecksum)
    }

    @Test func deleteMetadataOnlyTombstoneDoesNotDeleteMacAudioFile() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let recordingDirectoryURL = try saveInboxRecording(id: "delete-metadata-only", title: "只删 metadata", store: fileStore)
        let audioURL = recordingDirectoryURL.appendingPathComponent("audio.m4a", isDirectory: false)
        let store = StudyLibraryStore(rootURL: rootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let item = try #require(store.item(recordingID: "delete-metadata-only"))
        let tombstone = StudyLibrarySyncTombstone(
            id: "item:\(item.itemID)",
            entityKind: .item,
            entityID: item.itemID,
            operation: .deleteMetadataOnly,
            updatedAt: item.updatedAt.addingTimeInterval(20),
            modifiedByDeviceID: "iphone-device"
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-device",
            generatedAt: Date(timeIntervalSince1970: 2_300),
            items: [],
            folders: [],
            tombstones: [tombstone]
        )

        let result = try store.applySyncManifest(manifest, localDeviceID: "mac-device")
        let synced = try #require(store.item(recordingID: "delete-metadata-only"))

        #expect(result.tombstoneCount == 1)
        #expect(synced.isTrashed)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    private static func makeFilteredCandidateItems() -> [StudyItemMetadata] {
        [
            StudyItemMetadata(
                recordingID: "candidate-filter-01",
                title: "矩阵乘法",
                createdAt: Date(timeIntervalSince1970: 1),
                duration: 1,
                studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
            ),
            StudyItemMetadata(
                recordingID: "candidate-filter-02",
                title: "行列式",
                createdAt: Date(timeIntervalSince1970: 2),
                duration: 1,
                studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "行列式", topic: "余子式")
            ),
            StudyItemMetadata(
                recordingID: "candidate-filter-03",
                title: "格林公式",
                createdAt: Date(timeIntervalSince1970: 3),
                duration: 1,
                studyFiling: StudyFilingPath(type: "课堂", subject: "高等数学", chapter: "多元函数积分", topic: "格林公式")
            ),
            StudyItemMetadata(
                recordingID: "candidate-filter-04",
                title: "复习矩阵",
                createdAt: Date(timeIntervalSince1970: 4),
                duration: 1,
                studyFiling: StudyFilingPath(type: "复习", subject: "线性代数", chapter: "矩阵", topic: "逆矩阵")
            )
        ]
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private func makeInboxItem(
    id: String,
    title: String,
    transcriptRelativePath: String? = nil,
    transcriptMarkdownRelativePath: String? = nil,
    noteRelativePath: String? = nil
) -> MacRecordingInboxItem {
    MacRecordingInboxItem(
        id: id,
        title: title,
        receivedAt: Date(timeIntervalSince1970: 1_800),
        duration: 90,
        fileSize: 1024,
        sourceDeviceName: "iPhone",
        transcriptionStatus: transcriptRelativePath == nil && transcriptMarkdownRelativePath == nil ? "notStarted" : "transcribed",
        noteStatus: noteRelativePath == nil ? "notGenerated" : "generated",
        receiveStatus: "received",
        hasAudio: true,
        transcriptRelativePath: transcriptRelativePath,
        transcriptMarkdownRelativePath: transcriptMarkdownRelativePath,
        transcriptionError: nil,
        noteRelativePath: noteRelativePath,
        noteError: nil
    )
}

private func makeScratchDirectory() throws -> URL {
    let scratchURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("RokuricsMacStudyLibraryTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
    return scratchURL
}

private func makeMacStore() throws -> (MacRecordingFileStore, URL) {
    let rootURL = try makeScratchDirectory()
        .appendingPathComponent("Rokurics", isDirectory: true)
    let store = MacRecordingFileStore(rootURL: rootURL)
    return (store, rootURL)
}

@discardableResult
private func saveInboxRecording(
    id: String,
    title: String,
    store: MacRecordingFileStore,
    studyFiling: StudyFilingPath? = nil
) throws -> URL {
    let sourceDevice = PairedDevice(
        id: "device-01",
        deviceName: "Vita iPhone",
        sharedSecretBase64URL: "secret",
        pairedAt: Date(timeIntervalSince1970: 1_000),
        lastSeenAt: nil
    )
    let metadata = IncomingRecordingMetadata(
        id: id,
        title: title,
        originalFileName: "\(id).m4a",
        relativeAudioPath: "Recordings/\(id).m4a",
        createdAt: Date(timeIntervalSince1970: 1_800),
        endedAt: Date(timeIntervalSince1970: 1_806),
        duration: 6,
        format: "m4a",
        codec: "AAC",
        sampleRate: 16_000,
        channels: 1,
        bitrate: 64_000,
        fileSize: 5,
        uploadStatus: "uploaded",
        transcriptionStatus: "notStarted",
        noteStatus: "notStarted",
        tags: [],
        studyFiling: studyFiling,
        sourceDeviceName: "Vita iPhone",
        sourceDeviceID: "device-01",
        uploadedAt: Date(timeIntervalSince1970: 1_807)
    )

    let receiveResult = try store.saveMetadata(metadata, sourceDevice: sourceDevice)
    _ = try store.saveAudio(body: Data("audio".utf8), recordingID: id, requestedFileName: "\(id).m4a", sourceDevice: sourceDevice)
    return receiveResult.directoryURL
}

private func writeTranscriptFile(rootURL: URL, recordingID: String) throws -> URL {
    let transcriptDirectoryURL = rootURL
        .appendingPathComponent("transcripts", isDirectory: true)
        .appendingPathComponent("1970-01-01", isDirectory: true)
        .appendingPathComponent(recordingID, isDirectory: true)
    try FileManager.default.createDirectory(at: transcriptDirectoryURL, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: transcriptDirectoryURL.appendingPathComponent("transcript.json", isDirectory: false))
    let markdownURL = transcriptDirectoryURL.appendingPathComponent("transcript.md", isDirectory: false)
    try "# transcript".write(to: markdownURL, atomically: true, encoding: .utf8)
    return markdownURL
}

private func writeNoteFile(rootURL: URL, recordingID: String) throws -> URL {
    let noteDirectoryURL = rootURL
        .appendingPathComponent("notes", isDirectory: true)
        .appendingPathComponent("1970-01-01", isDirectory: true)
        .appendingPathComponent(recordingID, isDirectory: true)
    try FileManager.default.createDirectory(at: noteDirectoryURL, withIntermediateDirectories: true)
    let noteURL = noteDirectoryURL.appendingPathComponent("note.md", isDirectory: false)
    try "# note".write(to: noteURL, atomically: true, encoding: .utf8)
    return noteURL
}

private func readReceiveRecord(rootURL: URL, recordingID: String) throws -> RecordingReceiveRecord {
    let receiveURL = rootURL
        .appendingPathComponent("audio", isDirectory: true)
        .appendingPathComponent("inbox", isDirectory: true)
        .appendingPathComponent("1970-01-01", isDirectory: true)
        .appendingPathComponent(recordingID, isDirectory: true)
        .appendingPathComponent("receive.json", isDirectory: false)
    let data = try Data(contentsOf: receiveURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(RecordingReceiveRecord.self, from: data)
}
