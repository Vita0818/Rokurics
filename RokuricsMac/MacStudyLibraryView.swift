//
//  MacStudyLibraryView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import AppKit
import SwiftUI

struct MacStudyLibraryHeaderModel {
    static var title: String { RokuricsCopy.text("学习库", "Library") }
    static let showsLeadingIcon = false
    static let titleStyle: RokuricsTextStyle = .pageTitle
}

struct MacStudyLibraryNavigationState: Equatable {
    var browsePath = StudyBrowsePath()
    private(set) var selectedRecordingDetailID: String?
    private(set) var detailReturnPath = StudyBrowsePath()

    var isShowingRecordingDetail: Bool {
        selectedRecordingDetailID != nil
    }

    mutating func openRecordingDetail(recordingID: String) {
        detailReturnPath = browsePath
        selectedRecordingDetailID = recordingID
    }

    mutating func closeRecordingDetail() {
        browsePath = detailReturnPath
        selectedRecordingDetailID = nil
    }

    mutating func navigate(to path: StudyBrowsePath) {
        browsePath = path
    }
}

struct MacStudyLibraryView: View {
    @ObservedObject var studyLibraryStore: StudyLibraryStore
    @ObservedObject var audioInboxStore: AudioInboxStore
    @ObservedObject var transcriptionCoordinator: TranscriptionCoordinator
    @ObservedObject var noteGenerationCoordinator: NoteGenerationCoordinator
    let onImportContext: (ChatContext) -> Void

    @State private var navigationState = MacStudyLibraryNavigationState()
    @State private var selectedTranscriptItem: MacRecordingInboxItem?
    @State private var selectedNoteItem: MacRecordingInboxItem?
    @State private var isTrashSheetPresented = false
    @State private var permanentDeleteTarget: MacRecordingInboxItem?
    @State private var isPermanentDeleteConfirmationPresented = false
    @State private var isNewFolderSheetPresented = false
    @State private var newFolderNameDraft = ""
    @State private var typeDraft = ""
    @State private var subjectDraft = ""
    @State private var chapterDraft = ""
    @State private var topicDraft = ""
    @State private var statusMessage: String?
    @State private var operationErrorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    private let folderGridColumns = [
        GridItem(.adaptive(minimum: 142, maximum: 210), spacing: 16, alignment: .top)
    ]

    var body: some View {
        let _ = ConnectionDiagnosticsStore.shared.recordRuntimeCounterTick(scope: "MacStudyLibraryList", kind: "body")
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            MacDetailContentContainer(maxWidth: 1120) {
                content
            }
        }
        .onAppear {
            let perfStartedAt = Date()
            ConnectionDiagnosticsStore.shared.recordPerfLog(
                CanonicalPerfLog.started(operation: .enterStudyLibrary)
            )
            audioInboxStore.refreshRecordingInbox()
            studyLibraryStore.refresh()
            keepBrowsePathValid()
            let totalMs = CanonicalPerfLog.elapsedMs(since: perfStartedAt)
            let stages = CanonicalPerfLog.StageDurations(projectionRebuildMs: totalMs)
            for record in CanonicalPerfLog.finishedRecords(
                operation: .enterStudyLibrary,
                totalMs: totalMs,
                stages: stages
            ) {
                ConnectionDiagnosticsStore.shared.recordPerfLog(record)
            }
        }
        .onChange(of: audioInboxStore.recordingItems) {
            studyLibraryStore.refresh()
            keepBrowsePathValid()
        }
        .onChange(of: studyLibraryStore.effectiveStudyItems) {
            keepBrowsePathValid()
        }
        .onChange(of: studyLibraryStore.effectiveStudyFolders) {
            keepBrowsePathValid()
        }
        .confirmationDialog(
            RecordingLocalOperationCopy.permanentDeleteTitle,
            isPresented: $isPermanentDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(RokuricsCopy.text("永久删除", "Delete"), role: .destructive) {
                commitPermanentDelete()
            }

            Button(RokuricsCopy.text("取消", "Cancel"), role: .cancel) {
                permanentDeleteTarget = nil
            }
        } message: {
            Text(RecordingLocalOperationCopy.macPermanentDeleteMessage)
        }
        .sheet(isPresented: $isTrashSheetPresented) {
            MacAudioInboxTrashSheet(
                items: audioInboxStore.trashItems,
                onRestore: restoreFromTrash,
                onPermanentDelete: beginPermanentDelete
            )
            .frame(minWidth: 560, minHeight: 420)
        }
        .sheet(isPresented: $isNewFolderSheetPresented) {
            MacStudyNewFolderSheet(
                levelTitle: newFolderLevelTitle,
                name: $newFolderNameDraft,
                onCancel: {
                    isNewFolderSheetPresented = false
                },
                onSave: commitCreateFolder
            )
            .frame(minWidth: 360, minHeight: 190)
        }
        .alert(RokuricsCopy.text("学习库操作失败", "Library Operation Failed"), isPresented: operationErrorBinding) {
            Button(RokuricsCopy.text("好", "OK"), role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let selectedTranscriptItem {
            MacTranscriptDetailView(item: selectedTranscriptItem) {
                self.selectedTranscriptItem = nil
            }
        } else if let selectedNoteItem {
            MacNoteDetailView(item: selectedNoteItem) {
                self.selectedNoteItem = nil
            }
        } else if let detailItem = selectedRecordingDetailItem {
            let displaySyncState = canonicalDisplaySyncState(for: detailItem)
            MacStudyRecordingDetailPage(
                item: detailItem,
                displaySyncState: displaySyncState,
                allStudyItems: studyLibraryStore.effectiveStudyItems,
                allStudyFolders: studyLibraryStore.effectiveStudyFolders,
                type: $typeDraft,
                subject: $subjectDraft,
                chapter: $chapterDraft,
                topic: $topicDraft,
                isTranscribing: transcriptionCoordinator.isTranscribing(recordingID: detailItem.id),
                isGeneratingNote: noteGenerationCoordinator.isGenerating(recordingID: detailItem.id),
                statusMessage: statusMessage,
                onBack: {
                    navigationState.closeRecordingDetail()
                },
                onSaveFiling: {
                    saveFilingDraft(for: detailItem.id)
                },
                onCreateFilingValue: { level, name in
                    createFilingValue(level: level, name: name, for: detailItem.id)
                },
                onViewTranscript: {
                    selectedTranscriptItem = detailItem
                },
                onTranscribe: {
                    transcriptionCoordinator.startTranscription(recordingID: detailItem.id)
                    statusMessage = RokuricsCopy.text("转写任务已提交", "Transcription queued")
                },
                onViewNote: {
                    selectedNoteItem = detailItem
                },
                onGenerateNote: {
                    noteGenerationCoordinator.startNoteGeneration(recordingID: detailItem.id)
                    statusMessage = RokuricsCopy.text("笔记任务已提交", "Note queued")
                },
                onImportToChat: {
                    importRecordingToChat(detailItem)
                },
                onMoveToTrash: {
                    moveToTrashImmediately(detailItem)
                }
            )
        } else {
            studyLibraryContent
        }
    }

    private var studyLibraryContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(MacStudyLibraryHeaderModel.title)
                .font(MacTypography.font(for: MacStudyLibraryHeaderModel.titleStyle))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(1)

            browserNavigation

            browserContent

            Spacer(minLength: 0)
        }
    }

    private var browserNavigation: some View {
        HStack(spacing: 10) {
            MacStudyToolbarIconButton(systemImage: "chevron.left", isEnabled: !navigationState.browsePath.isRoot) {
                navigationState.browsePath = navigationState.browsePath.parent
            }
            .help(RokuricsCopy.text("返回上一级", "Back"))
            .accessibilityLabel(RokuricsCopy.text("返回上一级", "Back"))

            MacStudyBreadcrumbView(path: navigationState.browsePath) { path in
                navigationState.navigate(to: path)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            MacStudyToolbarIconButton(systemImage: "folder.badge.plus", isEnabled: canCreateFolderHere) {
                newFolderNameDraft = ""
                isNewFolderSheetPresented = true
            }
                .help(newFolderHelpText)
                .accessibilityLabel(RokuricsCopy.text("新建文件夹", "New Folder"))

            MacStudyToolbarIconButton(systemImage: "bubble.left.and.bubble.right", isEnabled: true) {
                importCurrentBrowseContext()
            }
            .help(RokuricsCopy.text("导入 AI 对话上下文", "Import to AI Chat"))
            .accessibilityLabel(RokuricsCopy.text("导入 AI 对话上下文", "Import to AI Chat"))

            MacStudyToolbarIconButton(systemImage: "trash", isEnabled: true) {
                isTrashSheetPresented = true
            }
            .help(RokuricsCopy.text("打开废纸篓", "Open Trash"))
            .accessibilityLabel(RokuricsCopy.text("打开废纸篓", "Open Trash"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canCreateFolderHere: Bool {
        StudyFolderMetadata.level(forDepth: navigationState.browsePath.depth) != nil
            && !navigationState.browsePath.isUncategorizedTypeSelection
    }

    private var newFolderLevelTitle: String {
        StudyFolderMetadata.level(forDepth: navigationState.browsePath.depth)?.title ?? RokuricsCopy.text("文件夹", "Folder")
    }

    private var newFolderHelpText: String {
        canCreateFolderHere ? RokuricsCopy.text("新建\(newFolderLevelTitle)虚拟文件夹", "New \(newFolderLevelTitle) folder") : RokuricsCopy.text("当前层级不能新建子文件夹", "Cannot create a child folder here")
    }

    private var browserContent: some View {
        let content = StudyLibraryBrowser.content(
            items: studyLibraryStore.effectiveStudyItems,
            folders: studyLibraryStore.effectiveStudyFolders,
            path: navigationState.browsePath
        )

        return Group {
            if studyLibraryStore.effectiveStudyItems.isEmpty && studyLibraryStore.effectiveStudyFolders.isEmpty {
                emptyLibraryState
            } else if content.folders.isEmpty && content.items.isEmpty {
                emptyFolderState
            } else {
                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 18) {
                        if !content.folders.isEmpty {
                            LazyVGrid(columns: folderGridColumns, alignment: .leading, spacing: 16) {
                                ForEach(content.folders) { folder in
                                    MacStudyFolderTile(
                                        folder: folder,
                                        onOpen: {
                                            navigationState.browsePath = folder.path
                                        },
                                        onRename: { name in
                                            renameFolder(folder, to: name)
                                        },
                                        onSetColor: { colorToken in
                                            setFolderColor(folder, colorToken: colorToken)
                                        },
                                        onMoveToTrash: {
                                            moveFolderToTrash(folder)
                                        }
                                    )
                                }
                            }
                        }

                        if !content.items.isEmpty {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(content.items) { item in
                                    if item.kind == .recordingBundle, let recordingID = item.recordingID {
                                        let inboxItem = liveInboxItem(for: recordingID) ?? item.asInboxItem()
                                        let displaySyncState = canonicalDisplaySyncState(for: inboxItem)
                                        MacStudyRecordingCard(
                                            item: inboxItem,
                                            displaySyncState: displaySyncState,
                                            isTranscribing: transcriptionCoordinator.isTranscribing(recordingID: inboxItem.id),
                                            isGeneratingNote: noteGenerationCoordinator.isGenerating(recordingID: inboxItem.id),
                                            onPlay: {
                                                playRecording(inboxItem)
                                            },
                                            onTranscribe: {
                                                transcriptionCoordinator.startTranscription(recordingID: inboxItem.id)
                                            },
                                            onGenerateNote: {
                                                noteGenerationCoordinator.startNoteGeneration(recordingID: inboxItem.id)
                                            },
                                            onImportToChat: {
                                                importStudyItemToChat(item.mergedWithCurrentInboxItem(inboxItem))
                                            },
                                            onOpenDetail: {
                                                openDetail(inboxItem)
                                            },
                                            onRename: { title in
                                                renameStudyItem(itemID: item.itemID, to: title)
                                            },
                                            onDelete: {
                                                moveToTrashImmediately(inboxItem)
                                            }
                                        )
                                    } else {
                                        MacStudyStandaloneNoteCard(
                                            item: item,
                                            onImportToChat: {
                                                importStudyItemToChat(item)
                                            },
                                            onRename: { title in
                                                renameStudyItem(itemID: item.itemID, to: title)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(4)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var emptyLibraryState: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: "books.vertical")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(MacTheme.aqua)

            Text(RokuricsCopy.text("暂无学习内容", "No study items"))
                .font(RokuricsCopy.usesChinese ? MacTypography.chineseTitle(size: 22, weight: .bold) : MacTypography.englishTitle(size: 22, weight: .bold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            Text(RokuricsCopy.text("收到或保存的录音会在这里按门类、课程、章节和主题逐层显示。", "Saved recordings appear by type, course, chapter, and topic."))
                .font(RokuricsCopy.usesChinese ? MacTypography.chineseBody(size: 14, weight: .medium) : MacTypography.englishBody(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassCard(cornerRadius: 22, material: .thinMaterial, fillOpacity: 0.36, strokeOpacity: 0.30, shadowOpacity: 0.04, shadowRadius: 10, shadowY: 5)
    }

    private var emptyFolderState: some View {
        Text(RokuricsCopy.text("这个文件夹里暂时没有学习内容", "This folder is empty for now."))
            .font(RokuricsCopy.usesChinese ? MacTypography.chineseBody(size: 14, weight: .medium) : MacTypography.englishBody(size: 14, weight: .medium))
            .foregroundStyle(MacTheme.softText(for: colorScheme))
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .macLiquidGlassCard(cornerRadius: 22, material: .thinMaterial, fillOpacity: 0.32, strokeOpacity: 0.28, shadowOpacity: 0.04, shadowRadius: 10, shadowY: 5)
    }

    private var operationErrorBinding: Binding<Bool> {
        Binding {
            operationErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                operationErrorMessage = nil
            }
        }
    }

    private var selectedRecordingDetailItem: MacRecordingInboxItem? {
        guard let recordingID = navigationState.selectedRecordingDetailID else {
            return nil
        }

        return liveInboxItem(for: recordingID) ?? studyLibraryStore.item(recordingID: recordingID)?.asInboxItem()
    }

    private func canonicalDisplaySyncState(for item: MacRecordingInboxItem) -> CanonicalDisplaySyncState? {
        let objectID = CanonicalObjectID("recordingAudio:\(item.id)")
        return studyLibraryStore.canonicalDisplaySyncState(for: objectID)
    }

    private func openDetail(_ item: MacRecordingInboxItem) {
        loadDraft(from: item)
        statusMessage = nil
        navigationState.openRecordingDetail(recordingID: item.id)
    }

    private func loadDraft(from item: MacRecordingInboxItem) {
        let studyItem = studyLibraryStore.item(recordingID: item.id)
        let filing = studyItem?.filingPath ?? item.studyFiling ?? StudyFilingPath()
        typeDraft = filing.type ?? ""
        subjectDraft = filing.subject ?? ""
        chapterDraft = filing.chapter ?? ""
        topicDraft = filing.topic ?? ""
    }

    private func saveFilingDraft(for recordingID: String) {
        do {
            try studyLibraryStore.updateFiling(for: recordingID, studyFiling: currentFilingDraft.filingPath)
            statusMessage = RokuricsCopy.text("归档已保存", "Filing saved")
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private var currentFilingDraft: StudyFilingSelectionDraft {
        StudyFilingSelectionDraft(
            path: StudyFilingPath(
                type: typeDraft,
                subject: subjectDraft,
                chapter: chapterDraft,
                topic: topicDraft
            )
        )
    }

    private func applyFilingDraft(_ draft: StudyFilingSelectionDraft) {
        typeDraft = draft.type
        subjectDraft = draft.subject
        chapterDraft = draft.chapter
        topicDraft = draft.topic
    }

    private func createFilingValue(level: StudyFolderLevel, name: String, for recordingID: String) {
        let draft = currentFilingDraft
        guard let parentPath = draft.parentBrowsePath(for: level) else {
            operationErrorMessage = RokuricsCopy.text("请先选择上一级归类", "Choose the parent category first")
            return
        }

        do {
            _ = try studyLibraryStore.createFolder(named: name, at: parentPath)
            var updatedDraft = draft
            updatedDraft.select(level, value: name)
            applyFilingDraft(updatedDraft)
            try studyLibraryStore.updateFiling(for: recordingID, studyFiling: updatedDraft.filingPath)
            statusMessage = RokuricsCopy.text("归档已保存", "Filing saved")
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func commitCreateFolder() {
        do {
            let folder = try studyLibraryStore.createFolder(named: newFolderNameDraft, at: navigationState.browsePath)
            statusMessage = RokuricsCopy.text("已新建\(folder.level.title)：\(folder.name)", "Created \(folder.level.title): \(folder.name)")
            isNewFolderSheetPresented = false
            newFolderNameDraft = ""
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func importCurrentBrowseContext() {
        let exporter = StudyLibraryContextExporter(rootURL: studyLibraryStore.libraryRootURL)
        let context = exporter.export(items: studyLibraryStore.effectiveStudyItems, path: navigationState.browsePath)
        onImportContext(context)
    }

    private func importStudyItemToChat(_ item: StudyItemMetadata) {
        let exporter = StudyLibraryContextExporter(rootURL: studyLibraryStore.libraryRootURL)
        onImportContext(exporter.export(item: item))
    }

    private func importRecordingToChat(_ item: MacRecordingInboxItem) {
        let metadata = studyLibraryStore.item(recordingID: item.id)?.mergedWithCurrentInboxItem(item)
            ?? StudyItemMetadata.defaultMetadata(for: item)
        importStudyItemToChat(metadata)
    }

    private func renameFolder(_ folder: StudyBrowseFolder, to rawName: String) {
        guard let level = StudyFolderLevel(rawValue: folder.levelKey) else {
            return
        }

        do {
            if let folderID = folder.folderID {
                _ = try studyLibraryStore.renameFolder(folderID: folderID, to: rawName)
            } else {
                _ = try studyLibraryStore.renameFolder(path: folder.path, level: level, to: rawName)
            }
            if navigationState.browsePath == folder.path {
                navigationState.browsePath = renamedBrowsePath(folder.path, level: level, rawName: rawName)
            }
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func setFolderColor(_ folder: StudyBrowseFolder, colorToken: StudyFolderColorToken) {
        guard let level = StudyFolderLevel(rawValue: folder.levelKey) else {
            return
        }

        do {
            let folderID: StudyFolderID
            if let existingFolderID = folder.folderID {
                folderID = existingFolderID
            } else {
                let metadata = try studyLibraryStore.renameFolder(path: folder.path, level: level, to: folder.title)
                folderID = metadata.folderID
            }
            _ = try studyLibraryStore.setFolderColor(folderID: folderID, colorToken: colorToken)
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func moveFolderToTrash(_ folder: StudyBrowseFolder) {
        guard let level = StudyFolderLevel(rawValue: folder.levelKey) else {
            return
        }

        do {
            let folderID: StudyFolderID
            if let existingFolderID = folder.folderID {
                folderID = existingFolderID
            } else {
                let metadata = try studyLibraryStore.renameFolder(path: folder.path, level: level, to: folder.title)
                folderID = metadata.folderID
            }
            _ = try studyLibraryStore.moveFolderToTrash(folderID: folderID)
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = error.localizedDescription == "study_folder_not_empty"
                ? RokuricsCopy.text("文件夹不为空", "Folder is not empty")
                : error.localizedDescription
        }
    }

    private func renameStudyItem(itemID: StudyItemID, to rawTitle: String) {
        do {
            _ = try studyLibraryStore.renameItem(itemID: itemID, to: rawTitle)
            audioInboxStore.refreshRecordingInbox()
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.renameFailure
        }
    }

    private func renamedBrowsePath(_ path: StudyBrowsePath, level: StudyFolderLevel, rawName: String) -> StudyBrowsePath {
        guard let name = StudyItemMetadata.normalized(rawName) else {
            return path
        }

        var components = path.components
        switch level {
        case .type:
            if components.indices.contains(0) { components[0] = name }
        case .subject:
            if components.indices.contains(1) { components[1] = name }
        case .chapter:
            if components.indices.contains(2) { components[2] = name }
        case .topic:
            if components.indices.contains(3) { components[3] = name }
        case .custom:
            break
        }
        return StudyBrowsePath(components: components)
    }

    private func keepBrowsePathValid() {
        while !navigationState.browsePath.isRoot {
            let content = StudyLibraryBrowser.content(
                items: studyLibraryStore.effectiveStudyItems,
                folders: studyLibraryStore.effectiveStudyFolders,
                path: navigationState.browsePath
            )
            guard content.folders.isEmpty && content.items.isEmpty else {
                break
            }

            navigationState.browsePath = navigationState.browsePath.parent
        }
    }

    private func liveInboxItem(for recordingID: String) -> MacRecordingInboxItem? {
        audioInboxStore.recordingItems.first { $0.id == recordingID }
    }

    private func playRecording(_ item: MacRecordingInboxItem) {
        do {
            let audioURL = try audioInboxStore.audioFileURL(recordingID: item.id)
            NSWorkspace.shared.open(audioURL)
        } catch {
            operationErrorMessage = RokuricsCopy.text("无法打开录音文件", "Could not open audio file")
        }
    }

    private func moveToTrashImmediately(_ item: MacRecordingInboxItem) {
        performSoftDelete(item)
    }

    private func performSoftDelete(_ item: MacRecordingInboxItem) {
        do {
            try audioInboxStore.deleteRecording(recordingID: item.id)
            studyLibraryStore.refresh()
            keepBrowsePathValid()
            if navigationState.selectedRecordingDetailID == item.id {
                navigationState.closeRecordingDetail()
            }
            if selectedTranscriptItem?.id == item.id {
                selectedTranscriptItem = nil
            }
            if selectedNoteItem?.id == item.id {
                selectedNoteItem = nil
            }
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.deleteFailure
        }
    }

    private func restoreFromTrash(_ item: MacRecordingInboxItem) {
        do {
            try audioInboxStore.restoreRecording(recordingID: item.id)
            studyLibraryStore.refresh()
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.restoreFailure
        }
    }

    private func beginPermanentDelete(_ item: MacRecordingInboxItem) {
        permanentDeleteTarget = item
        isPermanentDeleteConfirmationPresented = true
    }

    private func commitPermanentDelete() {
        guard let permanentDeleteTarget else {
            return
        }

        do {
            try audioInboxStore.permanentlyDeleteRecording(recordingID: permanentDeleteTarget.id)
            studyLibraryStore.refresh()
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.deleteFailure
        }

        self.permanentDeleteTarget = nil
    }
}

private struct MacStudyBreadcrumbView: View {
    let path: StudyBrowsePath
    let onSelect: (StudyBrowsePath) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var breadcrumbs: [(title: String, path: StudyBrowsePath)] {
        StudyLibraryBrowser.breadcrumbs(for: path)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { index, breadcrumb in
                if index > 0 {
                    Text("/")
                        .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                        .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                }

                BreadcrumbSegmentButton(
                    title: breadcrumb.title,
                    isCurrent: index == breadcrumbs.count - 1,
                    action: {
                        onSelect(breadcrumb.path)
                    }
                )
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BreadcrumbSegmentButton: View {
    let title: String
    let isCurrent: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                .foregroundStyle(isCurrent ? MacTheme.deepText(for: colorScheme) : MacTheme.softText(for: colorScheme))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background {
                    Capsule(style: .continuous)
                        .fill(isHovered ? MacTheme.glassSurface(for: colorScheme).opacity(0.30) : Color.clear)
                }
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
    }
}

private struct MacStudyToolbarIconButton: View {
    let systemImage: String
    let isEnabled: Bool
    var accessibilityTitle = RokuricsCopy.text("操作", "Action")
    let action: () -> Void

    var body: some View {
        RokuricsCircleIconButton(
            systemImage: systemImage,
            accessibilityTitle: accessibilityTitle,
            isEnabled: isEnabled,
            action: action
        )
    }
}

private struct InlineEditableText<Display: View>: View {
    let text: String
    let editFont: Font
    var textAlignment: TextAlignment = .leading
    var editTriggerID: Int = 0
    let onCommit: (String) -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }
    let display: (String) -> Display

    @State private var draft = ""
    @State private var isEditing = false
    @State private var handledEditTriggerID = 0
    @FocusState private var isFocused: Bool

    init(
        text: String,
        editFont: Font,
        textAlignment: TextAlignment = .leading,
        editTriggerID: Int = 0,
        onCommit: @escaping (String) -> Void,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder display: @escaping (String) -> Display
    ) {
        self.text = text
        self.editFont = editFont
        self.textAlignment = textAlignment
        self.editTriggerID = editTriggerID
        self.onCommit = onCommit
        self.onEditingChanged = onEditingChanged
        self.display = display
        self._draft = State(initialValue: text)
    }

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $draft)
                    .font(editFont)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(textAlignment)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
            } else {
                display(text)
                    .highPriorityGesture(TapGesture().onEnded(beginEditing))
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && isEditing {
                commit()
            }
        }
        .onChange(of: text) { _, newValue in
            if !isEditing {
                draft = newValue
            }
        }
        .onChange(of: editTriggerID) { _, newValue in
            guard newValue != handledEditTriggerID else {
                return
            }

            handledEditTriggerID = newValue
            beginEditing()
        }
    }

    private func beginEditing() {
        draft = text
        isEditing = true
        onEditingChanged(true)
        DispatchQueue.main.async {
            isFocused = true
        }
    }

    private func commit() {
        let submitted = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        isFocused = false
        onEditingChanged(false)
        guard !submitted.isEmpty else {
            draft = text
            return
        }
        onCommit(submitted)
    }

    private func cancel() {
        draft = text
        isEditing = false
        isFocused = false
        onEditingChanged(false)
    }
}

private struct MacSystemFolderIconView: View {
    let colorToken: StudyFolderColorToken?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: MacSystemFolderIconProvider.makeIcon())
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 58, height: 50)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 5, x: 0, y: 3)

            if let color = colorToken?.accentColor {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.35 : 0.78), lineWidth: 1)
                    }
                    .offset(x: -2, y: -3)
            }
        }
        .frame(height: 52)
    }
}

enum MacSystemFolderIconProvider {
    static let folderFileType = "public.folder"

    static func makeIcon() -> NSImage {
        let image = NSWorkspace.shared.icon(forFileType: folderFileType)
        image.size = NSSize(width: 96, height: 96)
        image.isTemplate = false
        return image
    }
}

enum MacFolderContextMenuModel {
    static let primaryActionTitles = StudyFolderMenuModel.primaryActionTitles
    static let colorTokens = StudyFolderMenuModel.colorTokens
    static let colorColumnsPerRow = StudyFolderMenuModel.colorColumnsPerRow

    static var colorRows: [[StudyFolderColorToken]] {
        StudyFolderMenuModel.colorRows
    }
}

private extension StudyFolderColorToken {
    var accentColor: Color? {
        switch self {
        case .default:
            return nil
        case .orange:
            return Color(red: 0.96, green: 0.52, blue: 0.16)
        case .blue:
            return MacTheme.aqua
        case .green:
            return MacTheme.leaf
        case .mint:
            return Color(red: 0.33, green: 0.82, blue: 0.62)
        case .teal:
            return Color(red: 0.17, green: 0.68, blue: 0.66)
        case .cyan:
            return Color(red: 0.22, green: 0.72, blue: 0.92)
        case .yellow:
            return MacTheme.amber
        case .red:
            return MacTheme.coral
        case .indigo:
            return Color(red: 0.34, green: 0.42, blue: 0.86)
        case .purple:
            return Color(red: 0.55, green: 0.43, blue: 0.94)
        case .gray:
            return Color.secondary
        }
    }
}

private struct MacStudyFolderTile: View {
    let folder: StudyBrowseFolder
    let onOpen: () -> Void
    let onRename: (String) -> Void
    let onSetColor: (StudyFolderColorToken) -> Void
    let onMoveToTrash: () -> Void
    @State private var isEditingName = false
    @State private var renameTriggerID = 0
    @State private var isContextMenuPresented = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            MacSystemFolderIconView(colorToken: folder.colorToken)

            InlineEditableText(
                text: folder.title,
                editFont: MacTypography.chineseBody(size: 14, weight: .bold),
                textAlignment: .center,
                editTriggerID: renameTriggerID,
                onCommit: onRename,
                onEditingChanged: { isEditingName = $0 }
            ) { title in
                Text(title)
                    .font(MacTypography.chineseBody(size: 14, weight: .bold))
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .minimumScaleFactor(0.82)
            }

            Text(RokuricsCopy.itemCount(folder.itemCount))
                .font(RokuricsCopy.usesChinese ? MacTypography.chineseCaption(size: 11, weight: .semibold) : MacTypography.englishCaption(size: 11, weight: .semibold))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 128)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .macLiquidGlassCard(cornerRadius: 18, material: .thinMaterial, fillOpacity: 0.34, strokeOpacity: 0.28, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
        .onTapGesture {
            if !isEditingName {
                onOpen()
            }
        }
        .overlay {
            MacSecondaryClickCatcher {
                isContextMenuPresented = true
            }
        }
        .popover(isPresented: $isContextMenuPresented, arrowEdge: .top) {
            MacStudyFolderContextMenuPopover(
                selectedColorToken: folder.colorToken ?? .default,
                onRename: {
                    isContextMenuPresented = false
                    renameTriggerID += 1
                },
                onMoveToTrash: {
                    isContextMenuPresented = false
                    onMoveToTrash()
                },
                onSetColor: { colorToken in
                    isContextMenuPresented = false
                    onSetColor(colorToken)
                }
            )
        }
        .help(RokuricsCopy.openLabel(folder.title))
    }
}

private struct MacStudyFolderContextMenuPopover: View {
    let selectedColorToken: StudyFolderColorToken
    let onRename: () -> Void
    let onMoveToTrash: () -> Void
    let onSetColor: (StudyFolderColorToken) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                MacFolderContextActionButton(title: MacFolderContextMenuModel.primaryActionTitles[0], role: nil, action: onRename)
                MacFolderContextActionButton(title: MacFolderContextMenuModel.primaryActionTitles[1], role: .destructive, action: onMoveToTrash)
            }

            VStack(spacing: 8) {
                ForEach(MacFolderContextMenuModel.colorRows.indices, id: \.self) { rowIndex in
                    HStack(spacing: 10) {
                        ForEach(MacFolderContextMenuModel.colorRows[rowIndex]) { colorToken in
                            MacStudyFolderColorDotButton(
                                colorToken: colorToken,
                                isSelected: selectedColorToken == colorToken,
                                action: {
                                    onSetColor(colorToken)
                                }
                            )
                        }
                    }
                }
            }
            .frame(width: 194)
            .padding(.top, 1)
        }
        .padding(12)
        .frame(width: 260)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MacTheme.glassStroke(for: colorScheme).opacity(0.30), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, x: 0, y: 10)
    }
}

private struct MacFolderContextActionButton: View {
    let title: String
    let role: ButtonRole?
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                .foregroundStyle(role == .destructive ? MacTheme.coral : MacTheme.deepText(for: colorScheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            role == .destructive
                                ? MacTheme.coral.opacity(isHovered ? 0.18 : 0.10)
                                : MacTheme.glassSurface(for: colorScheme).opacity(isHovered ? 0.36 : 0.22)
                        )
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct MacStudyFolderColorDotButton: View {
    let colorToken: StudyFolderColorToken
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(colorToken.accentColor ?? Color.clear)
                    .frame(width: 15, height: 15)
                    .overlay {
                        Circle()
                            .stroke(
                                colorToken.accentColor == nil
                                    ? MacTheme.softText(for: colorScheme).opacity(0.55)
                                    : Color.white.opacity(colorScheme == .dark ? 0.22 : 0.70),
                                lineWidth: 1
                            )
                    }

                if isSelected {
                    Circle()
                        .stroke(MacTheme.deepText(for: colorScheme).opacity(0.72), lineWidth: 1.5)
                        .frame(width: 21, height: 21)
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(colorToken.title)
    }
}

private struct MacSecondaryClickCatcher: NSViewRepresentable {
    let onSecondaryClick: () -> Void

    func makeNSView(context: Context) -> SecondaryClickCaptureView {
        let view = SecondaryClickCaptureView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: SecondaryClickCaptureView, context: Context) {
        nsView.onSecondaryClick = onSecondaryClick
    }
}

private final class SecondaryClickCaptureView: NSView {
    var onSecondaryClick: () -> Void = {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = window?.currentEvent ?? NSApp.currentEvent else {
            return nil
        }

        if event.type == .rightMouseDown {
            return self
        }

        if event.type == .leftMouseDown, event.modifierFlags.contains(.control) {
            return self
        }

        return nil
    }

    override func rightMouseDown(with event: NSEvent) {
        onSecondaryClick()
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onSecondaryClick()
        } else {
            super.mouseDown(with: event)
        }
    }
}

private struct MacStudyStandaloneNoteCard: View {
    let item: StudyItemMetadata
    let onImportToChat: () -> Void
    let onRename: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(MacTheme.mint)
                .frame(width: 42, height: 42)
                .background {
                    Circle()
                        .fill(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.36))
                }
                .overlay {
                    Circle()
                        .stroke(MacTheme.glassStroke(for: colorScheme).opacity(0.24), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 8) {
                InlineEditableText(
                    text: item.title,
                    editFont: MacTypography.chineseBody(size: 15, weight: .bold),
                    onCommit: onRename
                ) { title in
                    Text(title)
                        .font(MacTypography.chineseBody(size: 15, weight: .bold))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .lineLimit(1)
                }

                Text(Self.dateFormatter.string(from: item.createdAt))
                    .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    MacStudyStatusChip(text: RokuricsCopy.text("笔记", "Note"), systemImage: "doc.text", tint: MacTheme.mint)
                    MacStudyStatusChip(text: item.filingPath.displaySummary, systemImage: "folder", tint: MacTheme.softText(for: colorScheme))
                }
            }

            Spacer(minLength: 10)

            MacStudyCardIconButton(
                systemImage: "bubble.left.and.bubble.right",
                isEnabled: true,
                tint: MacTheme.aqua,
                helpText: RokuricsCopy.text("导入 AI 对话", "Import to AI Chat"),
                action: onImportToChat
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .macLiquidGlassCard(cornerRadius: 20, material: .thinMaterial, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.05, shadowRadius: 9, shadowY: 4)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = RokuricsCopy.displayLocale
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private struct MacStudyRecordingCard: View {
    let item: MacRecordingInboxItem
    let displaySyncState: CanonicalDisplaySyncState?
    let isTranscribing: Bool
    let isGeneratingNote: Bool
    let onPlay: () -> Void
    let onTranscribe: () -> Void
    let onGenerateNote: () -> Void
    let onImportToChat: () -> Void
    let onOpenDetail: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void
    @State private var isIconHovered = false
    @State private var isTitleEditing = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            MacStudyRecordingLeadingIcon(isDeleteIconHovered: isIconHovered)
                .contentShape(Circle())
                .onHover { isHovered in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isIconHovered = isHovered
                    }
                }
                .onTapGesture(count: 2, perform: onDelete)
                .help(RokuricsCopy.text("双击移入废纸篓", "Double-click to trash"))

            VStack(alignment: .leading, spacing: 8) {
                InlineEditableText(
                    text: item.title,
                    editFont: MacTypography.chineseBody(size: 16, weight: .semibold),
                    onCommit: onRename,
                    onEditingChanged: { isTitleEditing = $0 }
                ) { title in
                    MacMixedFontText(
                        text: title,
                        chineseFont: MacTypography.chineseBody(size: 16, weight: .semibold),
                        englishFont: MacTypography.englishBody(size: 16, weight: .semibold),
                        numberFont: MacTypography.numberBody(size: 16, weight: .semibold)
                    )
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))
                    .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(Self.dateFormatter.string(from: item.receivedAt))
                        .font(MacTypography.numberBody(size: 13, weight: .semibold))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                        .lineLimit(1)

                    Text(MacStudyLibraryViewDuration.text(item.duration))
                        .font(MacTypography.numberBody(size: 13, weight: .semibold))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            actionArea
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .macLiquidGlassCard(cornerRadius: 18, material: .ultraThinMaterial, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
        .onTapGesture {
            if !isTitleEditing {
                onOpenDetail()
            }
        }
    }

    private var canUseTranscriptionButton: Bool {
        displayAudioAvailable && !isTranscribing && !item.isTranscriptionActive
    }

    private var canUseNoteButton: Bool {
        item.canStartNoteGeneration && !isGeneratingNote
    }

    @ViewBuilder
    private var actionArea: some View {
        if !displayAudioAvailable,
           let transfer = item.localNetworkReceiveTransferProgress,
           transfer.isVisibleInActionArea {
            StudyRecordingTransferProgressView(transfer: transfer)
        } else {
            HStack(spacing: 8) {
                MacStudyCardIconButton(
                    systemImage: "play.fill",
                    isEnabled: displayAudioAvailable,
                    tint: MacTheme.leaf,
                    helpText: RokuricsCopy.text("播放录音", "Play Recording"),
                    action: onPlay
                )

                MacStudyCardIconButton(
                    systemImage: item.isTranscribed ? "arrow.clockwise" : "waveform.and.magnifyingglass",
                    isEnabled: canUseTranscriptionButton,
                    tint: MacTheme.aqua,
                    helpText: item.isTranscribed ? RokuricsCopy.text("重新转写", "Transcribe Again") : transcriptionHelpText,
                    action: onTranscribe
                )

                MacStudyCardIconButton(
                    systemImage: item.isNoteGenerated ? "sparkles.rectangle.stack" : "sparkles",
                    isEnabled: canUseNoteButton,
                    tint: MacTheme.mint,
                    helpText: item.isNoteGenerated ? RokuricsCopy.text("重新总结", "Summarize Again") : noteHelpText,
                    action: onGenerateNote
                )

                MacStudyCardIconButton(
                    systemImage: "bubble.left.and.bubble.right",
                    isEnabled: true,
                    tint: MacTheme.aqua,
                    helpText: RokuricsCopy.text("导入 AI 对话", "Import to AI Chat"),
                    action: onImportToChat
                )
            }
        }
    }

    private var displayAudioAvailable: Bool {
        displaySyncState?.canDisplayAsComplete == true
    }

    private var transcriptionHelpText: String {
        if isTranscribing || item.isTranscriptionActive {
            return RokuricsCopy.text("转写中", "Transcribing")
        }

        return item.transcriptionActionText
    }

    private var noteHelpText: String {
        if isGeneratingNote || item.isNoteGenerating {
            return RokuricsCopy.text("总结中", "Summarizing")
        }

        return item.isNoteGenerated ? RokuricsCopy.text("重新总结", "Summarize Again") : RokuricsCopy.text("AI 总结", "AI Summary")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = RokuricsCopy.displayLocale
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

private struct MacStudyRecordingLeadingIcon: View {
    let isDeleteIconHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(containerFill)

            Circle()
                .stroke(containerStroke, lineWidth: 1)

            Image(systemName: isDeleteIconHovered ? "trash.fill" : "waveform")
                .font(.system(size: isDeleteIconHovered ? 14 : 16, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(glyphColor)
                .frame(width: 20, height: 20)
        }
        .background(.ultraThinMaterial, in: Circle())
        .frame(width: 38, height: 38)
        .scaleEffect(isDeleteIconHovered ? 1.015 : 1)
        .animation(.easeInOut(duration: 0.12), value: isDeleteIconHovered)
    }

    private var containerFill: Color {
        if isDeleteIconHovered {
            return MacTheme.coral.opacity(colorScheme == .dark ? 0.11 : 0.09)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.075)
            : Color.white.opacity(0.58)
    }

    private var containerStroke: LinearGradient {
        let accent = isDeleteIconHovered ? MacTheme.coral : MacTheme.aqua

        return LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.62),
                accent.opacity(isDeleteIconHovered ? 0.42 : 0.34)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glyphColor: Color {
        isDeleteIconHovered
            ? MacTheme.coral.opacity(colorScheme == .dark ? 0.86 : 0.78)
            : MacTheme.aqua
    }
}

private struct MacStudyCardIconButton: View {
    let systemImage: String
    let isEnabled: Bool
    let tint: Color
    let helpText: String
    let action: () -> Void

    var body: some View {
        RokuricsCircleIconButton(
            systemImage: systemImage,
            accessibilityTitle: helpText,
            tint: tint,
            isEnabled: isEnabled,
            action: action
        )
    }
}

private struct MacStudySheetCircularIconButton: View {
    let systemImage: String
    let tint: Color
    let helpText: String
    let role: ButtonRole?
    let action: () -> Void

    var body: some View {
        RokuricsCircleIconButton(
            systemImage: systemImage,
            accessibilityTitle: helpText,
            tint: tint,
            role: role,
            action: action
        )
    }
}

private struct MacStudyNewFolderSheet: View {
    let levelTitle: String
    @Binding var name: String
    let onCancel: () -> Void
    let onSave: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(RokuricsCopy.text("新建\(levelTitle)", "New \(levelTitle)"))
                .font(RokuricsCopy.usesChinese ? MacTypography.chineseTitle(size: 20, weight: .bold) : MacTypography.englishTitle(size: 20, weight: .bold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            TextField(levelTitle, text: $name)
                .textFieldStyle(.roundedBorder)
                .font(MacTypography.chineseBody(size: 14, weight: .medium))

            HStack {
                Spacer()

                Button(RokuricsCopy.text("取消", "Cancel"), action: onCancel)

                Button(RokuricsCopy.text("保存", "Save"), action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacTheme.pageGradient(for: colorScheme))
    }
}

private struct MacStudyRecordingDetailPage: View {
    let item: MacRecordingInboxItem
    let displaySyncState: CanonicalDisplaySyncState?
    let allStudyItems: [StudyItemMetadata]
    let allStudyFolders: [StudyFolderMetadata]
    @Binding var type: String
    @Binding var subject: String
    @Binding var chapter: String
    @Binding var topic: String
    let isTranscribing: Bool
    let isGeneratingNote: Bool
    let statusMessage: String?
    let onBack: () -> Void
    let onSaveFiling: () -> Void
    let onCreateFilingValue: (StudyFolderLevel, String) -> Void
    let onViewTranscript: () -> Void
    let onTranscribe: () -> Void
    let onViewNote: () -> Void
    let onGenerateNote: () -> Void
    let onImportToChat: () -> Void
    let onMoveToTrash: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                header

                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 10) {
                    MacStudyDetailActionButton(
                        title: transcriptionActionTitle,
                        systemImage: item.isTranscribed ? "arrow.clockwise" : "waveform.and.magnifyingglass",
                        isEnabled: canUseTranscriptionButton,
                        action: onTranscribe
                    )

                    MacStudyDetailActionButton(
                        title: RokuricsCopy.text("查看转写", "Transcript"),
                        systemImage: "text.quote",
                        isEnabled: item.isTranscribed,
                        action: onViewTranscript
                    )

                    MacStudyDetailActionButton(
                        title: noteActionTitle,
                        systemImage: item.isNoteGenerated ? "sparkles.rectangle.stack" : "sparkles",
                        isEnabled: item.canStartNoteGeneration && !isGeneratingNote,
                        action: onGenerateNote
                    )

                    MacStudyDetailActionButton(
                        title: RokuricsCopy.text("查看总结", "Summary"),
                        systemImage: "doc.text",
                        isEnabled: item.isNoteGenerated,
                        action: onViewNote
                    )
                }

                detailPanel {
                    MacStudyFilingPicker(
                        type: $type,
                        subject: $subject,
                        chapter: $chapter,
                        topic: $topic,
                        items: allStudyItems,
                        folders: allStudyFolders,
                        onSave: onSaveFiling,
                        onCreate: onCreateFilingValue
                    )

                    if let statusMessage {
                        Text(statusMessage)
                            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                            .foregroundStyle(MacTheme.leaf)
                    }
                }

                MacStudyFileStatusPanel(item: item, displaySyncState: displaySyncState)

                MacStudyNoteSummaryPreviewCard(item: item, onOpenNote: onViewNote)
            }
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RokuricsBackButton(action: onBack)

            VStack(alignment: .leading, spacing: 7) {
                RokuricsPageTitle(text: item.title)
                RokuricsPageSubtitle(text: "\(Self.dateFormatter.string(from: item.receivedAt)) · \(MacStudyLibraryViewDuration.text(item.duration))")
            }

            Spacer(minLength: 12)

            MacStudySheetCircularIconButton(
                systemImage: "bubble.left.and.bubble.right",
                tint: MacTheme.aqua,
                helpText: RokuricsCopy.text("导入 AI 对话", "Import to AI Chat"),
                role: nil,
                action: onImportToChat
            )

            MacStudySheetCircularIconButton(
                systemImage: "trash",
                tint: MacTheme.coral,
                helpText: RokuricsCopy.text("移入废纸篓", "Move to Trash"),
                role: .destructive,
                action: onMoveToTrash
            )
        }
    }

    private var actionColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 116), spacing: 10),
            GridItem(.flexible(minimum: 116), spacing: 10),
            GridItem(.flexible(minimum: 116), spacing: 10),
            GridItem(.flexible(minimum: 116), spacing: 10)
        ]
    }

    private var canUseTranscriptionButton: Bool {
        displayAudioAvailable && !isTranscribing && !item.isTranscriptionActive
    }

    private var displayAudioAvailable: Bool {
        displaySyncState?.canDisplayAsComplete == true
    }

    private var transcriptionActionTitle: String {
        if isTranscribing || item.isTranscriptionActive {
            return RokuricsCopy.text("转写中", "Transcribing")
        }

        if item.isTranscribed {
            return RokuricsCopy.text("重新转写", "Transcribe Again")
        }

        return item.transcriptionActionText
    }

    private var noteActionTitle: String {
        if isGeneratingNote || item.isNoteGenerating {
            return RokuricsCopy.text("总结中", "Summarizing")
        }

        return item.isNoteGenerated ? RokuricsCopy.text("重新总结", "Summarize Again") : RokuricsCopy.text("AI 总结", "AI Summary")
    }

    private func detailPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassCard(cornerRadius: 16, material: .thinMaterial, fillOpacity: 0.30, strokeOpacity: 0.24, shadowOpacity: 0.035, shadowRadius: 7, shadowY: 3)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = RokuricsCopy.displayLocale
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

enum MacStudyRecordingDetailDisplayModel {
    static func defaultSummaryTexts(for item: MacRecordingInboxItem) -> [String] {
        [
            item.title,
            RokuricsDocumentFormatting.dateTime(item.receivedAt),
            RokuricsDocumentFormatting.duration(item.duration),
            item.statusText,
            noteStatusText(for: item)
        ]
        .compactMap { $0 }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func advancedFileStatusRows(
        for item: MacRecordingInboxItem,
        displaySyncState: CanonicalDisplaySyncState?
    ) -> [RokuricsDocumentMetadataRow] {
        [
            RokuricsDocumentMetadataRow("recordingID", item.id, isTechnical: true),
            RokuricsDocumentMetadataRow("audio", displaySyncState?.canDisplayAsComplete == true ? RokuricsCopy.text("可用", "Available") : RokuricsCopy.text("缺失", "Missing")),
            RokuricsDocumentMetadataRow("audio path", item.audioRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow("transcript", transcriptStatusText(for: item)),
            RokuricsDocumentMetadataRow("transcript path", item.transcriptMarkdownRelativePath ?? item.transcriptRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow("note", noteStatusText(for: item)),
            RokuricsDocumentMetadataRow("note path", item.noteRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow("receive", item.receiveRelativePath, isTechnical: true)
        ]
    }

    private static func transcriptStatusText(for item: MacRecordingInboxItem) -> String {
        if item.isTranscribed {
            return RokuricsCopy.text("已生成", "Ready")
        }
        if item.isTranscriptionActive {
            return RokuricsCopy.text("转写中", "Transcribing")
        }
        if item.transcriptionStatus == "failed" {
            return RokuricsCopy.text("失败", "Failed")
        }
        return RokuricsCopy.text("未生成", "Not ready")
    }

    private static func noteStatusText(for item: MacRecordingInboxItem) -> String {
        if item.isNoteGenerated {
            return RokuricsCopy.text("已生成", "Ready")
        }
        if item.isNoteGenerating {
            return RokuricsCopy.text("生成中", "Generating")
        }
        if item.isNoteFailed {
            return RokuricsCopy.text("失败", "Failed")
        }
        return RokuricsCopy.text("未生成", "Not ready")
    }
}

private struct MacStudyFileStatusPanel: View {
    let item: MacRecordingInboxItem
    let displaySyncState: CanonicalDisplaySyncState?

    var body: some View {
        RokuricsDocumentAdvancedInfoCard(
            title: RokuricsCopy.text("文件状态", "File Status"),
            rows: MacStudyRecordingDetailDisplayModel.advancedFileStatusRows(for: item, displaySyncState: displaySyncState)
        )
    }
}

private struct MacStudyNoteSummaryPreviewCard: View {
    let item: MacRecordingInboxItem
    let onOpenNote: () -> Void
    var noteStore = NoteStore()

    @State private var preview: NoteSummaryPreview?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RokuricsDocumentContentCard(title: RokuricsCopy.text("AI 摘要", "AI Summary")) {
            VStack(alignment: .leading, spacing: 12) {
                if let preview, preview.isVisible {
                    Text(preview.shortSummary)
                        .font(RokuricsDetailTypography.body)
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    if !preview.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(preview.keyPoints.prefix(4), id: \.self) { point in
                                HStack(alignment: .firstTextBaseline, spacing: 9) {
                                    Text("•")
                                        .font(RokuricsDetailTypography.bodyEmphasis)
                                        .foregroundStyle(MacTheme.aqua)
                                    Text(point)
                                        .font(RokuricsDetailTypography.body)
                                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                } else {
                    Text(RokuricsCopy.text("暂无摘要", "No summary yet"))
                        .font(RokuricsDetailTypography.metadataValue)
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if item.isNoteGenerated {
                    onOpenNote()
                }
            }
        }
        .onAppear(perform: loadPreview)
        .onChange(of: item.noteRelativePath) {
            loadPreview()
        }
    }

    private func loadPreview() {
        preview = noteStore.loadSummaryPreview(noteRelativePath: item.noteRelativePath)
    }
}

private struct MacStudyFilingPicker: View {
    @Binding var type: String
    @Binding var subject: String
    @Binding var chapter: String
    @Binding var topic: String
    let items: [StudyItemMetadata]
    let folders: [StudyFolderMetadata]
    let onSave: () -> Void
    let onCreate: (StudyFolderLevel, String) -> Void
    @State private var activeLevel: StudyFolderLevel?
    @State private var newValueDraft = ""
    @FocusState private var isNewValueFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private let levels: [StudyFolderLevel] = [.type, .subject, .chapter, .topic]
    private let candidateColumns = [
        GridItem(.adaptive(minimum: 96, maximum: 168), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(levels, id: \.self) { level in
                    MacStudyFilingLevelButton(
                        level: level,
                        value: draft.value(for: level),
                        isActive: selectionLevel == level,
                        isEnabled: canActivate(level)
                    ) {
                        guard canActivate(level) else {
                            return
                        }

                        activeLevel = level
                        newValueDraft = ""
                        isNewValueFocused = false
                    }
                }
            }

            LazyVGrid(columns: candidateColumns, alignment: .leading, spacing: 8) {
                ForEach(currentCandidates, id: \.self) { candidate in
                    MacStudyFilingValueButton(title: candidate, isSelected: draft.value(for: selectionLevel) == candidate) {
                        select(candidate, for: selectionLevel)
                    }
                }

                HStack(spacing: 6) {
                    TextField(RokuricsCopy.text("新建", "New"), text: $newValueDraft)
                        .textFieldStyle(.plain)
                        .font(MacTypography.chineseBody(size: 13, weight: .medium))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .focused($isNewValueFocused)
                        .onSubmit(createCurrentValue)

                    RokuricsCircleIconButton(
                        systemImage: "plus",
                        accessibilityTitle: RokuricsCopy.newLabel(selectionLevel.title),
                        tint: MacTheme.aqua,
                        isEnabled: !newValueDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: createCurrentValue
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.14 : 0.30))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MacTheme.glassStroke(for: colorScheme).opacity(0.22), lineWidth: 1)
                }
            }
        }
    }

    private var draft: StudyFilingSelectionDraft {
        StudyFilingSelectionDraft(
            path: StudyFilingPath(
                type: type,
                subject: subject,
                chapter: chapter,
                topic: topic
            )
        )
    }

    private var selectionLevel: StudyFolderLevel {
        if let activeLevel, canActivate(activeLevel) {
            return activeLevel
        }

        return firstMissingLevel ?? .topic
    }

    private var firstMissingLevel: StudyFolderLevel? {
        levels.first { draft.value(for: $0).isEmpty }
    }

    private var currentCandidates: [String] {
        StudyFilingCandidateResolver.candidates(
            for: selectionLevel,
            current: draft.filingPath,
            items: items,
            folders: folders
        )
    }

    private func canActivate(_ level: StudyFolderLevel) -> Bool {
        switch level {
        case .type:
            return true
        case .subject:
            return !type.isEmpty
        case .chapter:
            return !type.isEmpty && !subject.isEmpty
        case .topic:
            return !type.isEmpty && !subject.isEmpty && !chapter.isEmpty
        case .custom:
            return false
        }
    }

    private func select(_ value: String, for level: StudyFolderLevel) {
        var updated = draft
        updated.select(level, value: value)
        apply(updated)
        finishCommit(for: level)
        newValueDraft = ""
        onSave()
    }

    private func createCurrentValue() {
        let trimmedName = newValueDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        let level = selectionLevel
        onCreate(level, trimmedName)
        finishCommit(for: level)
        newValueDraft = ""
    }

    private func finishCommit(for level: StudyFolderLevel) {
        activeLevel = StudyFilingSelectionFlow.nextLevelAfterCommit(level)
        isNewValueFocused = false
    }

    private func apply(_ updated: StudyFilingSelectionDraft) {
        type = updated.type
        subject = updated.subject
        chapter = updated.chapter
        topic = updated.topic
    }
}

private struct MacStudyFilingLevelButton: View {
    let level: StudyFolderLevel
    let value: String
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(level.title)
                    .font(MacTypography.chineseCaption(size: 10, weight: .bold))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))

                Text(value.isEmpty ? RokuricsCopy.text("未选择", "Not set") : value)
                    .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                    .foregroundStyle(isEnabled ? MacTheme.deepText(for: colorScheme) : MacTheme.tertiaryText(for: colorScheme))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(minWidth: 82, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(MacTheme.glassSurface(for: colorScheme).opacity(isActive ? (colorScheme == .dark ? 0.24 : 0.50) : (colorScheme == .dark ? 0.13 : 0.28)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isActive ? MacTheme.aqua.opacity(0.42) : MacTheme.glassStroke(for: colorScheme).opacity(0.20), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
    }
}

private struct MacStudyFilingValueButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? .white : MacTheme.deepText(for: colorScheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? MacTheme.aqua : MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.14 : 0.30))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? MacTheme.aqua.opacity(0.34) : MacTheme.glassStroke(for: colorScheme).opacity(0.20), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct MacStudyDetailActionButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? MacTheme.deepText(for: colorScheme) : MacTheme.tertiaryText(for: colorScheme))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .macGlassCapsule(fillOpacity: isEnabled ? 0.28 : 0.16, strokeOpacity: 0.24)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct MacStudyStatusChip: View {
    let text: String
    let systemImage: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(MacTypography.chineseCaption(size: 11, weight: .bold))
            .foregroundStyle(tint)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .macGlassCapsule(fillOpacity: 0.24, strokeOpacity: 0.22)
    }
}

private enum MacStudyLibraryViewDuration {
    static func text(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes == 0 {
            return "\(seconds)''"
        }

        return "\(minutes)'\(String(format: "%02d", seconds))''"
    }
}
