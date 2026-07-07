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
    @ObservedObject private var connectionStatusStore = DeviceConnectionStatusStore.shared
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
                    items: studyLibraryStore.effectiveStudyItems,
                    folders: studyLibraryStore.effectiveStudyFolders,
                    statusMessage: statusMessage,
                    fileStatusRows: StudyRecordingFileStatusRows.rows(for: item),
                    detailActions: detailActionModels(for: item),
                    actionAreaPresentation: uploadActionAreaPresentation,
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
            let traceID = UploadFlightRecorder.makeTraceID()
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshTriggeredLocalReloadOnly", traceID: traceID, recordingID: item?.recordingID, eventResult: "begin")
            recordViewRefreshDecision(traceID: traceID, recordingID: item?.recordingID)
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshReloadOnly", traceID: traceID, recordingID: item?.recordingID, eventResult: "begin")
            loadDraft()
            loadPreview()
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshDidNotEnqueueUpload", traceID: traceID, recordingID: item?.recordingID, eventResult: "success")
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshReloadOnly", traceID: traceID, recordingID: item?.recordingID, eventResult: "success")
        }
        .onChange(of: itemID) {
            let traceID = UploadFlightRecorder.makeTraceID()
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshTriggeredLocalReloadOnly", traceID: traceID, recordingID: item?.recordingID, eventResult: "begin")
            recordViewRefreshDecision(traceID: traceID, recordingID: item?.recordingID)
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshReloadOnly", traceID: traceID, recordingID: item?.recordingID, eventResult: "begin")
            loadDraft()
            loadPreview()
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshDidNotEnqueueUpload", traceID: traceID, recordingID: item?.recordingID, eventResult: "success")
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshReloadOnly", traceID: traceID, recordingID: item?.recordingID, eventResult: "success")
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
            displaySyncState: canonicalDisplaySyncState,
            isMacPaired: canStartManualUpload,
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
            displaySyncState: canonicalDisplaySyncState,
            isMacPaired: canStartManualUpload,
            uploadAction: uploadCurrentRecording,
            transcriptAction: { readingRoute = .transcript },
            noteAction: { readingRoute = .note },
            renameAction: beginInlineRename
        )
    }

    private var canonicalDisplaySyncState: CanonicalDisplaySyncState? {
        guard let recordingID = item?.recordingID else {
            return nil
        }
        return uploadCoordinator.canonicalDisplaySyncState(for: CanonicalObjectID("recordingAudio:\(recordingID)"))
    }

    private var uploadActionAreaPresentation: StudyRecordingActionAreaPresentation? {
        RecordingUploadActionAreaPresentation.resolve(
            metadata: recordingMetadata,
            displaySyncState: canonicalDisplaySyncState,
            isMacPaired: canStartManualUpload
        )
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
        let traceID = UploadFlightRecorder.makeTraceID()
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadButtonTapped",
            traceID: traceID,
            recordingID: item?.recordingID,
            eventResult: "begin",
            reasonCode: "recordingDetail"
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadActionFired",
            traceID: traceID,
            recordingID: item?.recordingID,
            eventResult: "begin",
            reasonCode: "recordingDetail"
        )

        if let blockedReason = manualUploadHardBlockedReason() {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "manualUploadSkippedWithReason",
                traceID: traceID,
                recordingID: item?.recordingID,
                eventResult: "skip",
                reasonCode: blockedReason == "not_paired" ? "mac_not_paired" : blockedReason
            )
            return
        }
        if let softReason = manualUploadSoftBlockedReason() {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "manualUploadPresenceSoftBypassed",
                traceID: traceID,
                recordingID: item?.recordingID,
                eventResult: "continue",
                reasonCode: softReason
            )
        }

        recordingManager.reloadRecordings()
        guard let recordingID = item?.recordingID,
              let recordingMetadata = recordingManager.recordings.first(where: { $0.id == recordingID }) else {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "manualUploadSkippedWithReason",
                traceID: traceID,
                recordingID: item?.recordingID,
                eventResult: "skip",
                reasonCode: "recording_metadata_missing"
            )
            return
        }

        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadRecordingResolved",
            traceID: traceID,
            recordingID: recordingMetadata.id,
            eventResult: "success",
            uploadStatus: recordingMetadata.uploadStatus,
            fileSize: recordingMetadata.fileSize,
            resolvedRelativePathToken: recordingMetadata.relativeAudioPath
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadCoordinatorCallStarted",
            traceID: traceID,
            recordingID: recordingMetadata.id,
            eventResult: "begin",
            uploadStatus: recordingMetadata.uploadStatus
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadAllowed",
            traceID: traceID,
            recordingID: recordingMetadata.id,
            eventResult: "success",
            uploadStatus: recordingMetadata.uploadStatus
        )
        uploadCoordinator.upload(
            metadata: recordingMetadata,
            settings: macConnectionStore.snapshot,
            recordingManager: recordingManager,
            traceID: traceID,
            triggerSource: .manualUploadButton
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadCoordinatorCallReturned",
            traceID: traceID,
            recordingID: recordingMetadata.id,
            eventResult: "success",
            uploadStatus: recordingMetadata.uploadStatus
        )
    }

    private var canStartManualUpload: Bool {
        manualUploadHardBlockedReason() == nil
    }

    private func manualUploadHardBlockedReason(now: Date = Date()) -> String? {
        let snapshot = macConnectionStore.snapshot
        guard snapshot.isPaired else {
            return "not_paired"
        }
        guard macConnectionStore.userConnectionIntent == .wantsConnected else {
            return "user_does_not_want_connection"
        }
        guard let status = connectionStatusStore.status(for: snapshot.deviceID, now: now) else {
            return nil
        }
        if status.presenceSnapshot(now: now).state == .securityError {
            return "security_error"
        }
        return nil
    }

    private func manualUploadSoftBlockedReason(now: Date = Date()) -> String? {
        guard manualUploadHardBlockedReason(now: now) == nil else {
            return nil
        }
        let snapshot = macConnectionStore.snapshot
        guard let status = connectionStatusStore.status(for: snapshot.deviceID, now: now) else {
            return "presence_unavailable"
        }
        let blockedReason = MacUploadTestPresenceGate.blockedReason(
            snapshot: snapshot,
            status: status,
            now: now,
            userConnectionIntent: macConnectionStore.userConnectionIntent
        )
        switch blockedReason {
        case "heartbeat_interrupted", "heartbeat_disconnected", "heartbeat_not_online", "presence_unavailable":
            return blockedReason
        default:
            return nil
        }
    }

    private func beginInlineRename() {
        titleRenameTriggerID += 1
    }

    private func recordViewRefreshDecision(traceID: String, recordingID: String?) {
        let safeRecordingID = recordingID ?? "recordingDetailRefresh"
        let decision = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .unknown,
            peerAudioState: .unknown,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .folderViewRefresh,
            syncRunID: nil,
            objectID: "recordingAudio:\(safeRecordingID)",
            recordingID: safeRecordingID
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: decision.diagnosticStage,
            traceID: traceID,
            recordingID: recordingID,
            eventResult: decision.kind.rawValue,
            reasonCode: decision.reasonCode
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "viewRefreshUploadSuppressed",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            reasonCode: decision.reasonCode
        )
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
        displaySyncState: CanonicalDisplaySyncState?,
        isMacPaired: Bool,
        renameTint: Color,
        uploadAction: @escaping () -> Void,
        renameAction: @escaping () -> Void,
        trashAction: @escaping () -> Void
    ) -> [StudyDetailHeaderActionModel] {
        let uploadPresentation = RecordingUploadCapsulePresentation.resolve(
            displaySyncState: displaySyncState,
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
        displaySyncState: CanonicalDisplaySyncState?,
        isMacPaired: Bool,
        uploadAction: @escaping () -> Void,
        transcriptAction: @escaping () -> Void,
        noteAction: @escaping () -> Void,
        renameAction: @escaping () -> Void
    ) -> [StudyDetailActionModel] {
        let uploadPresentation = RecordingUploadCapsulePresentation.resolve(
            displaySyncState: displaySyncState,
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

private extension RecordingUploadCapsulePresentation {
    static func resolve(
        displaySyncState: CanonicalDisplaySyncState?,
        isMacPaired: Bool
    ) -> RecordingUploadCapsulePresentation {
        guard let displaySyncState else {
            return resolve(status: .localOnly, isMacPaired: isMacPaired)
        }

        let isUploadActionEnabled = isMacPaired && displaySyncState.kind != .uploading && displaySyncState.kind != .finalizing
        switch displaySyncState.kind {
        case .completed, .peerVerified:
            return RecordingUploadCapsulePresentation(
                label: "已上传",
                systemImage: "checkmark.circle.fill",
                tint: .success,
                isEnabled: false,
                fillOpacity: 0.24
            )
        case .uploading, .finalizing:
            return RecordingUploadCapsulePresentation(
                label: "上传中",
                systemImage: "arrow.triangle.2.circlepath",
                tint: .active,
                isEnabled: false,
                fillOpacity: 0.24
            )
        case .blocked, .conflict, .failed:
            return RecordingUploadCapsulePresentation(
                label: "重试",
                systemImage: "arrow.clockwise",
                tint: .failure,
                isEnabled: isUploadActionEnabled,
                fillOpacity: isUploadActionEnabled ? 0.38 : 0.24
            )
        case .hidden, .deferred, .uploadNeeded, .stale:
            return resolve(status: .localOnly, isMacPaired: isMacPaired)
        }
    }
}
