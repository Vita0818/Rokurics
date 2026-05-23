//
//  RecordingStudyDetailPage.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import SwiftUI

struct RecordingStudyDetailPage: View {
    let itemID: StudyItemID
    @ObservedObject var recordingManager: RecordingManager
    @ObservedObject var macConnectionStore: SecureMacConnectionStore
    @ObservedObject var uploadCoordinator: RecordingUploadCoordinator
    let onRenameRequested: (StudyItemMetadata) -> Void
    let onMoveToTrashRequested: (StudyItemMetadata) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var studyLibraryStore: StudyLibraryStore
    @State private var typeDraft = ""
    @State private var subjectDraft = ""
    @State private var chapterDraft = ""
    @State private var topicDraft = ""
    @State private var statusMessage: String?
    @State private var operationErrorMessage: String?
    @State private var notePreview: NoteSummaryPreview?
    @State private var readingRoute: RecordingStudyReadingRoute?
    @State private var titleRenameTriggerID = 0

    init(
        itemID: StudyItemID,
        recordingManager: RecordingManager,
        macConnectionStore: SecureMacConnectionStore,
        uploadCoordinator: RecordingUploadCoordinator,
        onRenameRequested: @escaping (StudyItemMetadata) -> Void,
        onMoveToTrashRequested: @escaping (StudyItemMetadata) -> Void
    ) {
        self.itemID = itemID
        self.recordingManager = recordingManager
        self.macConnectionStore = macConnectionStore
        self.uploadCoordinator = uploadCoordinator
        self.onRenameRequested = onRenameRequested
        self.onMoveToTrashRequested = onMoveToTrashRequested
        _studyLibraryStore = ObservedObject(wrappedValue: recordingManager.studyLibraryStore)
    }

    var body: some View {
        Group {
            if let item {
                StudyLibraryDetailContent(
                    title: item.title,
                    metadataText: StudyRecordingMetadataFormatter.detailMetadataText(for: item),
                    type: $typeDraft,
                    subject: $subjectDraft,
                    chapter: $chapterDraft,
                    topic: $topicDraft,
                    items: studyLibraryStore.allStudyItems,
                    folders: studyLibraryStore.allStudyFolders,
                    statusMessage: statusMessage,
                    fileStatusRows: StudyRecordingFileStatusRows.rows(for: item),
                    detailActions: detailActionModels(for: item),
                    titleRenameTriggerID: titleRenameTriggerID,
                    onRenameTitle: { newTitle in
                        commitRename(item, rawTitle: newTitle)
                    },
                    layout: .iPhone,
                    onBack: { dismiss() },
                    onSaveFiling: saveFilingDraft,
                    onCreateFilingValue: createFilingValue,
                    headerTrailing: {
                        headerActions(item)
                    },
                    summary: {
                        if let notePreview, notePreview.isVisible {
                            NavigationLink {
                                StudyNoteReadingPage(item: item, rootURL: studyLibraryStore.libraryRootURL)
                            } label: {
                                StudyNoteSummaryPreviewCard(preview: notePreview)
                            }
                            .buttonStyle(RokuricsScaleButtonStyle())
                        }
                    }
                )
            } else {
                StudyMissingContentView(message: "未找到学习内容")
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            loadDraft()
            loadPreview()
        }
        .onChange(of: itemID) {
            loadDraft()
            loadPreview()
        }
        .onChange(of: item?.noteRelativePath) {
            loadPreview()
        }
        .navigationDestination(item: $readingRoute) { route in
            switch route {
            case .transcript:
                if let item {
                    StudyTranscriptReadingPage(item: item, rootURL: studyLibraryStore.libraryRootURL)
                } else {
                    StudyMissingContentView(message: "未找到转写内容")
                }
            case .note:
                if let item {
                    StudyNoteReadingPage(item: item, rootURL: studyLibraryStore.libraryRootURL)
                } else {
                    StudyMissingContentView(message: "未找到总结内容")
                }
            }
        }
        .alert("操作失败", isPresented: operationErrorBinding) {
            Button("好", role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "")
        }
    }

    private var item: StudyItemMetadata? {
        studyLibraryStore.item(itemID: itemID)
    }

    private var recordingMetadata: RecordingMetadata? {
        guard let recordingID = item?.recordingID else {
            return nil
        }

        return recordingManager.recordings.first { $0.id == recordingID }
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

    private func headerActions(_ item: StudyItemMetadata) -> some View {
        StudyDetailHeaderActionGroup(actions: IPhoneStudyDetailActions.headerActions(
            for: item,
            status: uploadStatus,
            isMacPaired: macConnectionStore.isPaired,
            renameTint: RokuricsSharedStyle.softText(for: colorScheme),
            uploadAction: uploadCurrentRecording,
            renameAction: beginInlineRename,
            trashAction: {
                dismiss()
                onMoveToTrashRequested(item)
            }
        ))
    }

    private func detailActionModels(for item: StudyItemMetadata) -> [StudyDetailActionModel] {
        IPhoneStudyDetailActions.detailActions(
            for: item,
            status: uploadStatus,
            isMacPaired: macConnectionStore.isPaired,
            uploadAction: uploadCurrentRecording,
            transcriptAction: { readingRoute = .transcript },
            noteAction: { readingRoute = .note },
            renameAction: beginInlineRename
        )
    }

    private var uploadStatus: RecordingUploadStatus {
        recordingMetadata.map { uploadCoordinator.displayStatus(for: $0) } ?? .localOnly
    }

    private func loadDraft() {
        guard let item else {
            return
        }

        typeDraft = item.filing.type ?? ""
        subjectDraft = item.filing.subject ?? ""
        chapterDraft = item.filing.chapter ?? ""
        topicDraft = item.filing.topic ?? ""
    }

    private func loadPreview() {
        guard let item else {
            notePreview = nil
            return
        }

        notePreview = StudyDocumentLoader(rootURL: studyLibraryStore.libraryRootURL)
            .loadNoteSummaryPreview(item: item)
    }

    private func saveFilingDraft() {
        guard let item, let recordingID = item.recordingID else {
            return
        }

        do {
            try recordingManager.updateStudyFiling(recordingID: recordingID, studyFiling: currentFilingDraft.filingPath)
            statusMessage = "归档已保存"
            studyLibraryStore.refresh()
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func createFilingValue(level: StudyFolderLevel, name: String) {
        let draft = currentFilingDraft
        guard let parentPath = draft.parentBrowsePath(for: level) else {
            operationErrorMessage = "请先选择上一级归类"
            return
        }

        do {
            _ = try studyLibraryStore.createFolder(named: name, at: parentPath)
            statusMessage = "已新建\(level.title)：\(name)"
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func uploadCurrentRecording() {
        guard let recordingMetadata else {
            return
        }

        uploadCoordinator.upload(
            metadata: recordingMetadata,
            settings: macConnectionStore.snapshot,
            recordingManager: recordingManager
        )
    }

    private func beginInlineRename() {
        titleRenameTriggerID += 1
    }

    private func commitRename(_ item: StudyItemMetadata, rawTitle: String) {
        guard let recordingID = item.recordingID else {
            operationErrorMessage = RecordingLocalOperationCopy.renameFailure
            return
        }

        do {
            try recordingManager.renameRecording(recordingID: recordingID, rawTitle: rawTitle)
            studyLibraryStore.refresh()
            loadDraft()
            loadPreview()
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.renameFailure
        }
    }

    private var currentFilingDraft: StudyFilingSelectionDraft {
        StudyFilingSelectionDraft(
            path: StudyFilingPath(type: typeDraft, subject: subjectDraft, chapter: chapterDraft, topic: topicDraft)
        )
    }

}

private enum RecordingStudyReadingRoute: String, Identifiable {
    case transcript
    case note

    var id: String { rawValue }
}

private enum IPhoneStudyDetailActions {
    static func headerActions(
        for item: StudyItemMetadata,
        status: RecordingUploadStatus,
        isMacPaired: Bool,
        renameTint: Color,
        uploadAction: @escaping () -> Void,
        renameAction: @escaping () -> Void,
        trashAction: @escaping () -> Void
    ) -> [StudyDetailHeaderActionModel] {
        let uploadPresentation = RecordingUploadCapsulePresentation.resolve(
            status: status,
            isMacPaired: isMacPaired
        )

        return [
            StudyDetailActionPolicy.uploadHeaderAction(
                systemImage: uploadPresentation.systemImage,
                title: uploadPresentation.label,
                tint: uploadPresentation.tint.color,
                isEnabled: uploadPresentation.isEnabled,
                action: uploadAction
            ),
            StudyDetailActionPolicy.renameHeaderAction(
                tint: renameTint,
                action: renameAction
            ),
            StudyDetailActionPolicy.trashHeaderAction(
                isEnabled: item.recordingID != nil,
                action: trashAction
            )
        ]
    }

    static func detailActions(
        for item: StudyItemMetadata,
        status: RecordingUploadStatus,
        isMacPaired: Bool,
        uploadAction: @escaping () -> Void,
        transcriptAction: @escaping () -> Void,
        noteAction: @escaping () -> Void,
        renameAction: @escaping () -> Void
    ) -> [StudyDetailActionModel] {
        let uploadPresentation = RecordingUploadCapsulePresentation.resolve(
            status: status,
            isMacPaired: isMacPaired
        )

        return [
            StudyDetailActionPolicy.uploadDetailAction(
                title: uploadPresentation.label,
                systemImage: uploadPresentation.systemImage,
                isEnabled: uploadPresentation.isEnabled,
                action: uploadAction
            ),
            StudyDetailActionPolicy.viewTranscriptAction(
                isEnabled: item.hasTranscript,
                action: transcriptAction
            ),
            StudyDetailActionPolicy.viewNoteAction(
                isEnabled: item.hasNote,
                action: noteAction
            ),
            StudyDetailActionPolicy.renameDetailAction(action: renameAction)
        ]
    }
}
