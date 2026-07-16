//
//  RecordingLibraryView.swift
//  Rokurics
//
//  Created by Codex on 2026/5/9.
//

import SwiftUI

struct RecordingLibraryView: View {
    @ObservedObject var recordingManager: RecordingManager
    @ObservedObject var macConnectionStore: SecureMacConnectionStore
    @ObservedObject var uploadCoordinator: RecordingUploadCoordinator
    @ObservedObject private var studyLibraryStore: StudyLibraryStore
    @ObservedObject private var connectionStatusStore = DeviceConnectionStatusStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var browsePath = StudyBrowsePath()
    @State private var renameTarget: StudyItemMetadata?
    @State private var renameDraft = ""
    @State private var isRenameAlertPresented = false
    @State private var deleteTarget: StudyItemMetadata?
    @State private var isDeleteConfirmationPresented = false
    @State private var isTrashSheetPresented = false
    @State private var permanentDeleteTarget: RecordingMetadata?
    @State private var isPermanentDeleteConfirmationPresented = false
    @State private var operationErrorMessage: String?

    init(
        recordingManager: RecordingManager,
        macConnectionStore: SecureMacConnectionStore,
        uploadCoordinator: RecordingUploadCoordinator
    ) {
        self.recordingManager = recordingManager
        self.macConnectionStore = macConnectionStore
        self.uploadCoordinator = uploadCoordinator
        _studyLibraryStore = ObservedObject(wrappedValue: recordingManager.studyLibraryStore)
    }

    var body: some View {
        let _ = ConnectionDiagnosticsStore.shared.recordRuntimeCounterTick(
            scope: "iPhoneStudyLibraryList",
            kind: "body",
            deviceID: macConnectionStore.snapshot.deviceID
        )
        StudyLibraryPageShell {
            StudyLibraryBrowserView(
                items: studyLibraryStore.effectiveStudyItems,
                folders: studyLibraryStore.effectiveStudyFolders,
                browsePath: $browsePath,
                layout: .iPhone,
                emptyLibraryMessage: RokuricsCopy.text("收到或保存的录音会在这里按门类、课程、章节和主题逐层显示。", "Saved recordings appear here by type, course, chapter, and topic."),
                headerLeading: {
                    StudyLibraryPageBackButton(action: { dismiss() })
                },
                headerTrailing: {
                    StudyLibraryTrashButtonGroup(action: { isTrashSheetPresented = true })
                },
                navigationLeading: {
                    StudyLibraryFolderBackButton(isEnabled: !browsePath.isRoot) {
                        browsePath = browsePath.parent
                    }
                },
                navigationTrailing: {
                    EmptyView()
                },
                folderTile: { folder in
                    StudyFolderTile(
                        folder: folder,
                        onOpen: {
                            browsePath = folder.path
                        },
                        onRename: { rawName in
                            renameFolder(folder, to: rawName)
                        },
                        onSetColor: { colorToken in
                            setFolderColor(folder, colorToken: colorToken)
                        },
                        onMoveToTrash: {
                            moveFolderToTrash(folder)
                        }
                    )
                },
                recordingCard: { item in
                    recordingNavigationLink(for: item)
                },
                noteCard: { item in
                    StudyItemCard(
                        item: item,
                        metadataText: item.filing.displaySummary,
                        statusItems: [
                            .standaloneNote
                        ]
                    )
                }
            )
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            let perfStartedAt = Date()
            ConnectionDiagnosticsStore.shared.recordPerfLog(
                CanonicalPerfLog.started(operation: .enterStudyLibrary),
                deviceID: macConnectionStore.snapshot.deviceID
            )
            let traceID = UploadFlightRecorder.makeTraceID()
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshTriggeredLocalReloadOnly", traceID: traceID, eventResult: "begin")
            recordViewRefreshDecision(traceID: traceID)
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshReloadOnly", traceID: traceID, eventResult: "begin")
            macConnectionStore.refreshFromStorage()
            recordingManager.reloadRecordings()
            studyLibraryStore.refresh()
            keepBrowsePathValid()
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshDidNotEnqueueUpload", traceID: traceID, eventResult: "success")
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshReloadOnly", traceID: traceID, eventResult: "success")
            let totalMs = CanonicalPerfLog.elapsedMs(since: perfStartedAt)
            let stages = CanonicalPerfLog.StageDurations(projectionRebuildMs: totalMs)
            for record in CanonicalPerfLog.finishedRecords(
                operation: .enterStudyLibrary,
                totalMs: totalMs,
                stages: stages
            ) {
                ConnectionDiagnosticsStore.shared.recordPerfLog(
                    record,
                    deviceID: macConnectionStore.snapshot.deviceID
                )
            }
        }
        .onChange(of: studyLibraryStore.effectiveStudyItems) {
            keepBrowsePathValid()
        }
        .onChange(of: studyLibraryStore.effectiveStudyFolders) {
            keepBrowsePathValid()
        }
        .onReceive(NotificationCenter.default.publisher(for: .localNetworkStudyLibraryDidChange)) { _ in
            let traceID = UploadFlightRecorder.makeTraceID()
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshTriggeredLocalReloadOnly", traceID: traceID, eventResult: "begin")
            recordViewRefreshDecision(traceID: traceID)
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshReloadOnly", traceID: traceID, eventResult: "begin")
            recordingManager.reloadRecordings()
            studyLibraryStore.refresh()
            keepBrowsePathValid()
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshDidNotEnqueueUpload", traceID: traceID, eventResult: "success")
            UploadFlightRecorder.record(side: .iPhone, stage: "viewRefreshReloadOnly", traceID: traceID, eventResult: "success")
        }
        .alert(RecordingLocalOperationCopy.renameTitle, isPresented: $isRenameAlertPresented) {
            TextField(RokuricsCopy.text("录音名称", "Recording Name"), text: $renameDraft)

            Button(RokuricsCopy.text("保存", "Save")) {
                commitRename()
            }

            Button(RokuricsCopy.text("取消", "Cancel"), role: .cancel) {
                clearRenameState()
            }
        }
        .confirmationDialog(
            RecordingLocalOperationCopy.moveToTrashTitle,
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(RokuricsCopy.text("移入废纸篓", "Move to Trash"), role: .destructive) {
                commitDelete()
            }

            Button(RokuricsCopy.text("取消", "Cancel"), role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text(RecordingLocalOperationCopy.iPhoneMoveToTrashMessage)
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
            Text(RecordingLocalOperationCopy.iPhonePermanentDeleteMessage)
        }
        .sheet(isPresented: $isTrashSheetPresented) {
            StudyTrashSheet(items: recordingManager.trashedRecordings, emptyTitle: RokuricsCopy.text("废纸篓为空", "Trash is empty")) { metadata in
                StudyRecordingTrashRow(
                    title: metadata.title,
                    metadataText: metadataText(for: metadata),
                    onRestore: { restoreFromTrash(metadata) },
                    onPermanentDelete: { beginPermanentDelete(metadata) }
                )
            }
        }
        .alert(RokuricsCopy.text("操作失败", "Operation Failed"), isPresented: operationErrorBinding) {
            Button(RokuricsCopy.text("好", "OK"), role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "")
        }
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

    private func recordingNavigationLink(for item: StudyItemMetadata) -> some View {
        NavigationLink {
            RecordingStudyDetailPage(
                itemID: item.itemID,
                recordingManager: recordingManager,
                macConnectionStore: macConnectionStore,
                uploadCoordinator: uploadCoordinator,
                onRenameRequested: beginRename,
                onMoveToTrashRequested: beginDelete
            )
        } label: {
            StudyRecordingBundleCardContent(
                item: item,
                metadataText: metadataText(for: item),
                actions: cardActionModels(for: item),
                actionAreaPresentation: uploadActionAreaPresentation(for: item),
                onRename: { newTitle in
                    commitRename(item, rawTitle: newTitle)
                }
            )
        }
        .buttonStyle(RokuricsScaleButtonStyle())
    }

    private func uploadActionAreaPresentation(for item: StudyItemMetadata) -> StudyRecordingActionAreaPresentation? {
        let metadata = recordingMetadata(for: item)
        if let metadata,
           let record = uploadCoordinator.reconciliationRecord(for: metadata) {
            if record.targetDeviceID == macConnectionStore.snapshot.deviceID {
                return .statusWithActions(RokuricsCopy.text("等待从 Mac 接收", "Waiting to receive from Mac"))
            }
            if record.status == .deferred {
                return .statusWithActions(RokuricsCopy.text("同步差异待处理", "Sync difference deferred"))
            }
        }
        return RecordingUploadActionAreaPresentation.resolve(
            metadata: metadata,
            displaySyncState: canonicalDisplaySyncState(for: item),
            isMacPaired: canStartManualUpload
        )
    }

    private func canonicalDisplaySyncState(for item: StudyItemMetadata) -> CanonicalDisplaySyncState? {
        guard let recordingID = item.recordingID else {
            return nil
        }
        return uploadCoordinator.canonicalDisplaySyncState(for: CanonicalObjectID("recordingAudio:\(recordingID)"))
    }

    private func recordingMetadata(for item: StudyItemMetadata) -> RecordingMetadata? {
        guard let recordingID = item.recordingID else {
            return nil
        }

        return recordingManager.recordings.first { $0.id == recordingID }
    }

    private func metadataText(for item: StudyItemMetadata) -> String {
        StudyRecordingMetadataFormatter.cardMetadataText(for: item)
    }

    private func metadataText(for metadata: RecordingMetadata) -> String {
        "\(Self.dateFormatter.string(from: metadata.createdAt)) · \(RokuricsDocumentFormatting.duration(metadata.duration))"
    }

    private func cardActionModels(for item: StudyItemMetadata) -> [StudyRecordingCardActionModel] {
        let canUploadSelectedVersion = recordingMetadata(for: item).map {
            uploadCoordinator.pendingTransferRecord(
                for: $0,
                localDeviceID: macConnectionStore.snapshot.deviceID
            ) != nil
        } ?? false
        return IPhoneStudyRecordingCardActions.actions(
            for: item,
            displaySyncState: canonicalDisplaySyncState(for: item),
            isMacPaired: canStartManualUpload && canUploadSelectedVersion,
            uploadAction: {
                uploadRecording(from: item, source: "recordingCard")
            }
        )
    }

    private func uploadRecording(from item: StudyItemMetadata, source: String) {
        let traceID = UploadFlightRecorder.makeTraceID()
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadButtonTapped",
            traceID: traceID,
            recordingID: item.recordingID,
            eventResult: "begin",
            reasonCode: source
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadActionFired",
            traceID: traceID,
            recordingID: item.recordingID,
            eventResult: "begin",
            reasonCode: source
        )

        if let blockedReason = manualUploadHardBlockedReason() {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "manualUploadSkippedWithReason",
                traceID: traceID,
                recordingID: item.recordingID,
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
                recordingID: item.recordingID,
                eventResult: "continue",
                reasonCode: softReason
            )
        }

        recordingManager.reloadRecordings()
        guard let recordingID = item.recordingID,
              let latestMetadata = recordingManager.recordings.first(where: { $0.id == recordingID }) else {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "manualUploadSkippedWithReason",
                traceID: traceID,
                recordingID: item.recordingID,
                eventResult: "skip",
                reasonCode: "recording_metadata_missing"
            )
            return
        }

        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadRecordingResolved",
            traceID: traceID,
            recordingID: latestMetadata.id,
            eventResult: "success",
            uploadStatus: latestMetadata.uploadStatus,
            fileSize: latestMetadata.fileSize,
            resolvedRelativePathToken: latestMetadata.relativeAudioPath
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadCoordinatorCallStarted",
            traceID: traceID,
            recordingID: latestMetadata.id,
            eventResult: "begin",
            uploadStatus: latestMetadata.uploadStatus
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadAllowed",
            traceID: traceID,
            recordingID: latestMetadata.id,
            eventResult: "success",
            uploadStatus: latestMetadata.uploadStatus
        )

        uploadCoordinator.upload(
            metadata: latestMetadata,
            settings: macConnectionStore.snapshot,
            recordingManager: recordingManager,
            traceID: traceID,
            triggerSource: .manualUploadButton
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadCoordinatorCallReturned",
            traceID: traceID,
            recordingID: latestMetadata.id,
            eventResult: "success",
            uploadStatus: latestMetadata.uploadStatus
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

    private func recordViewRefreshDecision(traceID: String) {
        let decision = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .unknown,
            peerAudioState: .unknown,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .recordingListRefresh,
            syncRunID: nil,
            objectID: "recordingAudio:recordingListRefresh",
            recordingID: "recordingListRefresh"
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: decision.diagnosticStage,
            traceID: traceID,
            eventResult: decision.kind.rawValue,
            reasonCode: decision.reasonCode
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "viewRefreshUploadSuppressed",
            traceID: traceID,
            eventResult: "success",
            reasonCode: decision.reasonCode
        )
    }

    private func beginRename(_ item: StudyItemMetadata) {
        renameTarget = item
        renameDraft = item.title
        isRenameAlertPresented = true
    }

    private func commitRename() {
        guard let renameTarget else {
            clearRenameState()
            return
        }

        commitRename(renameTarget, rawTitle: renameDraft)
        clearRenameState()
    }

    private func commitRename(_ item: StudyItemMetadata, rawTitle: String) {
        guard let recordingID = item.recordingID else {
            operationErrorMessage = RecordingLocalOperationCopy.renameFailure
            return
        }

        do {
            try recordingManager.renameRecording(recordingID: recordingID, rawTitle: rawTitle)
            studyLibraryStore.refresh()
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.renameFailure
        }
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
            if browsePath == folder.path {
                browsePath = renamedBrowsePath(folder.path, level: level, rawName: rawName)
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

    private func clearRenameState() {
        renameTarget = nil
        renameDraft = ""
    }

    private func beginDelete(_ item: StudyItemMetadata) {
        deleteTarget = item
        isDeleteConfirmationPresented = true
    }

    private func commitDelete() {
        guard let deleteTarget, let recordingID = deleteTarget.recordingID else {
            return
        }

        do {
            try recordingManager.deleteRecording(recordingID: recordingID)
            studyLibraryStore.refresh()
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.deleteFailure
        }

        self.deleteTarget = nil
    }

    private func restoreFromTrash(_ metadata: RecordingMetadata) {
        do {
            try recordingManager.restoreRecording(recordingID: metadata.id)
            studyLibraryStore.refresh()
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.restoreFailure
        }
    }

    private func beginPermanentDelete(_ metadata: RecordingMetadata) {
        permanentDeleteTarget = metadata
        isPermanentDeleteConfirmationPresented = true
    }

    private func commitPermanentDelete() {
        guard let permanentDeleteTarget else {
            return
        }

        do {
            try recordingManager.permanentlyDeleteRecording(recordingID: permanentDeleteTarget.id)
            studyLibraryStore.refresh()
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.deleteFailure
        }

        self.permanentDeleteTarget = nil
    }

    private func keepBrowsePathValid() {
        while !browsePath.isRoot {
            let content = StudyLibraryBrowser.content(
                items: studyLibraryStore.effectiveStudyItems,
                folders: studyLibraryStore.effectiveStudyFolders,
                path: browsePath
            )
            guard content.folders.isEmpty && content.items.isEmpty else {
                break
            }

            browsePath = browsePath.parent
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

private enum IPhoneStudyRecordingCardActions {
    static func actions(
        for item: StudyItemMetadata,
        displaySyncState: CanonicalDisplaySyncState?,
        isMacPaired: Bool,
        uploadAction: @escaping () -> Void
    ) -> [StudyRecordingCardActionModel] {
        let uploadPresentation = uploadPresentation(
            displaySyncState: displaySyncState,
            isMacPaired: isMacPaired
        )

        return [
            StudyRecordingActionPolicy.uploadAction(
                systemImage: uploadPresentation.systemImage,
                tint: uploadPresentation.tint.color,
                accessibilityLabel: uploadPresentation.label,
                isEnabled: uploadPresentation.isEnabled,
                action: uploadAction
            ),
            StudyRecordingStatusPresentation.transcriptAction(for: item),
            StudyRecordingStatusPresentation.noteAction(for: item),
            StudyRecordingActionPolicy.detailAction()
        ]
    }

    private static func uploadPresentation(
        displaySyncState: CanonicalDisplaySyncState?,
        isMacPaired: Bool
    ) -> RecordingUploadCapsulePresentation {
        guard let displaySyncState else {
            return RecordingUploadCapsulePresentation.resolve(status: .localOnly, isMacPaired: isMacPaired)
        }

        let isUploadActionEnabled = isMacPaired && displaySyncState.kind != .uploading && displaySyncState.kind != .finalizing
        switch displaySyncState.kind {
        case .completed, .peerVerified:
            return RecordingUploadCapsulePresentation(
                label: RokuricsCopy.text("已上传", "Uploaded"),
                systemImage: "checkmark.circle.fill",
                tint: .success,
                isEnabled: false,
                fillOpacity: 0.24
            )
        case .uploading, .finalizing:
            return RecordingUploadCapsulePresentation(
                label: RokuricsCopy.text("上传中", "Uploading"),
                systemImage: "arrow.triangle.2.circlepath",
                tint: .active,
                isEnabled: false,
                fillOpacity: 0.24
            )
        case .blocked, .conflict, .failed:
            return RecordingUploadCapsulePresentation(
                label: RokuricsCopy.text("重试", "Retry"),
                systemImage: "arrow.clockwise",
                tint: .failure,
                isEnabled: isUploadActionEnabled,
                fillOpacity: isUploadActionEnabled ? 0.38 : 0.24
            )
        case .hidden, .deferred, .uploadNeeded, .stale:
            return RecordingUploadCapsulePresentation.resolve(status: .localOnly, isMacPaired: isMacPaired)
        }
    }
}

#Preview {
    NavigationStack {
        RecordingLibraryView(
            recordingManager: RecordingManager(),
            macConnectionStore: SecureMacConnectionStore(),
            uploadCoordinator: RecordingUploadCoordinator()
        )
    }
}
