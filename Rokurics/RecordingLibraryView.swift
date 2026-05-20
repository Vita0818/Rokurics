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
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uploadCoordinator = RecordingUploadCoordinator()
    @State private var browsePath = RecordingStudyBrowsePath()
    @State private var detailTarget: RecordingMetadata?
    @State private var renameTarget: RecordingMetadata?
    @State private var renameDraft = ""
    @State private var isRenameAlertPresented = false
    @State private var deleteTarget: RecordingMetadata?
    @State private var isDeleteConfirmationPresented = false
    @State private var isTrashSheetPresented = false
    @State private var permanentDeleteTarget: RecordingMetadata?
    @State private var isPermanentDeleteConfirmationPresented = false
    @State private var typeDraft = ""
    @State private var subjectDraft = ""
    @State private var chapterDraft = ""
    @State private var topicDraft = ""
    @State private var operationStatusMessage: String?
    @State private var operationErrorMessage: String?

    var body: some View {
        ZStack {
            RokuricsColors.pageGradient
                .ignoresSafeArea()

            VStack(spacing: 18) {
                header
                    .padding(.top, 18)
                    .padding(.horizontal, 22)

                if recordingManager.recordings.isEmpty {
                    emptyState
                        .padding(.horizontal, 22)
                    Spacer()
                } else {
                    browserNavigation
                        .padding(.horizontal, 22)

                    browserContent
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            macConnectionStore.refreshFromStorage()
            recordingManager.reloadRecordings()
            keepBrowsePathValid()
        }
        .onChange(of: recordingManager.recordings) {
            keepBrowsePathValid()
        }
        .sheet(item: $detailTarget) { metadata in
            let latestMetadata = recordingManager.recordings.first { $0.id == metadata.id } ?? metadata
            RecordingStudyDetailSheet(
                metadata: latestMetadata,
                uploadStatus: uploadCoordinator.displayStatus(for: latestMetadata),
                isMacPaired: macConnectionStore.isPaired,
                errorMessage: uploadCoordinator.errorMessage(for: latestMetadata),
                type: $typeDraft,
                subject: $subjectDraft,
                chapter: $chapterDraft,
                topic: $topicDraft,
                candidates: recordingManager.filingCandidates,
                statusMessage: operationStatusMessage,
                onUpload: {
                    uploadRecording(latestMetadata)
                },
                onSaveFiling: {
                    saveFilingDraft(for: latestMetadata.id)
                },
                onRenameRequested: {
                    beginRename(latestMetadata)
                },
                onMoveToTrashRequested: {
                    detailTarget = nil
                    beginDelete(latestMetadata)
                }
            )
        }
        .alert(RecordingLocalOperationCopy.renameTitle, isPresented: $isRenameAlertPresented) {
            TextField("录音名称", text: $renameDraft)

            Button("保存") {
                commitRename()
            }

            Button("取消", role: .cancel) {
                clearRenameState()
            }
        }
        .confirmationDialog(
            RecordingLocalOperationCopy.moveToTrashTitle,
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("移入废纸篓", role: .destructive) {
                commitDelete()
            }

            Button("取消", role: .cancel) {
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
            Button("永久删除", role: .destructive) {
                commitPermanentDelete()
            }

            Button("取消", role: .cancel) {
                permanentDeleteTarget = nil
            }
        } message: {
            Text(RecordingLocalOperationCopy.iPhonePermanentDeleteMessage)
        }
        .sheet(isPresented: $isTrashSheetPresented) {
            RecordingTrashSheet(
                recordings: recordingManager.trashedRecordings,
                onRestore: restoreFromTrash,
                onPermanentDelete: beginPermanentDelete
            )
        }
        .alert("操作失败", isPresented: operationErrorBinding) {
            Button("好", role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                RokuricsIconCircleButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "返回首页",
                    size: 44,
                    action: { dismiss() }
                )

                Spacer()

                HStack(spacing: 8) {
                    RokuricsIconCircleButton(
                        systemName: "trash",
                        accessibilityLabel: "打开废纸篓",
                        tint: RokuricsColors.softText,
                        action: {
                            isTrashSheetPresented = true
                        }
                    )

                    Text("\(recordingManager.recordings.count)")
                        .font(RokuricsTypography.largeNumber(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(RokuricsColors.aqua)
                        .frame(width: 44, height: 44)
                        .rokuricsGlassCircle(fillOpacity: 0.32, strokeOpacity: 0.36, shadowOpacity: 0.08, shadowRadius: 8, shadowY: 4)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("学习库")
                    .font(RokuricsTypography.font(for: .pageTitle))
                    .foregroundStyle(RokuricsColors.deepText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

            }
        }
    }

    private var browserNavigation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    browsePath = browsePath.parent
                } label: {
                    Label("上一级", systemImage: "chevron.left")
                        .font(RokuricsTypography.caption(size: 12, weight: .bold))
                        .foregroundStyle(browsePath.isRoot ? RokuricsColors.tertiaryText : RokuricsColors.deepText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .rokuricsGlassCapsule(fillOpacity: 0.24, strokeOpacity: 0.26)
                }
                .buttonStyle(RokuricsScaleButtonStyle())
                .disabled(browsePath.isRoot)

                Text("当前：\(RecordingStudyBrowser.levelTitle(for: browsePath))")
                    .font(RokuricsTypography.caption(size: 12, weight: .bold))
                    .foregroundStyle(RokuricsColors.softText)

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(RecordingStudyBrowser.breadcrumbs(for: browsePath).enumerated()), id: \.offset) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(RokuricsColors.tertiaryText)
                        }

                        Button {
                            browsePath = crumb.path
                        } label: {
                            Text(crumb.title)
                                .font(RokuricsTypography.caption(size: 12, weight: index == 0 ? .bold : .semibold))
                                .foregroundStyle(index == 0 ? RokuricsColors.aqua : RokuricsColors.deepText)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .rokuricsGlassCapsule(fillOpacity: 0.18, strokeOpacity: 0.18)
                        }
                        .buttonStyle(RokuricsScaleButtonStyle())
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .rokuricsLiquidGlassCard(cornerRadius: 22, fillOpacity: 0.32, strokeOpacity: 0.34, shadowOpacity: 0.06, shadowRadius: 8, shadowY: 4)
    }

    private var browserContent: some View {
        let content = RecordingStudyBrowser.content(recordings: recordingManager.recordings, path: browsePath)

        return ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(content.folders) { folder in
                    RecordingStudyFolderRow(folder: folder) {
                        browsePath = folder.path
                    }
                }

                ForEach(content.recordings) { metadata in
                    RecordingStudyCard(
                        metadata: metadata,
                        uploadStatus: uploadCoordinator.displayStatus(for: metadata),
                        isMacPaired: macConnectionStore.isPaired,
                        onOpenDetail: {
                            openDetail(metadata)
                        }
                    )
                }

                if content.folders.isEmpty && content.recordings.isEmpty {
                    Text("这里暂时没有录音")
                        .font(RokuricsTypography.body(size: 15, weight: .medium))
                        .foregroundStyle(RokuricsColors.softText)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .rokuricsLiquidGlassCard(cornerRadius: 20, fillOpacity: 0.30, strokeOpacity: 0.30, shadowOpacity: 0.05, shadowRadius: 8, shadowY: 4)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(RokuricsColors.aqua)
                .frame(width: 64, height: 64)
                .rokuricsGlassCircle(fillOpacity: 0.38, strokeOpacity: 0.38, shadowOpacity: 0.08, shadowRadius: 12, shadowY: 6)

            Text("暂无学习内容")
                .font(RokuricsTypography.headline(size: 18, weight: .semibold))
                .foregroundStyle(RokuricsColors.deepText)

            Text("新的录音会先保存在本地，再按门类、课程、章节和主题显示。")
                .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                .foregroundStyle(RokuricsColors.softText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .rokuricsLiquidGlassCard(cornerRadius: 30, fillOpacity: 0.38, strokeOpacity: 0.42, shadowOpacity: 0.10, shadowRadius: 18, shadowY: 10)
    }

    private func openDetail(_ metadata: RecordingMetadata) {
        let filing = metadata.studyFiling ?? StudyFilingPath()
        typeDraft = filing.type ?? ""
        subjectDraft = filing.subject ?? ""
        chapterDraft = filing.chapter ?? ""
        topicDraft = filing.topic ?? ""
        operationStatusMessage = nil
        detailTarget = metadata
    }

    private func uploadRecording(_ metadata: RecordingMetadata) {
        uploadCoordinator.upload(
            metadata: metadata,
            settings: macConnectionStore.snapshot,
            recordingManager: recordingManager
        )
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

    private func beginRename(_ metadata: RecordingMetadata) {
        renameTarget = metadata
        renameDraft = metadata.title
        isRenameAlertPresented = true
    }

    private func commitRename() {
        guard let renameTarget else {
            clearRenameState()
            return
        }

        do {
            try recordingManager.renameRecording(recordingID: renameTarget.id, rawTitle: renameDraft)
            if let updated = recordingManager.recordings.first(where: { $0.id == renameTarget.id }) {
                detailTarget = updated
            }
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.renameFailure
        }

        clearRenameState()
    }

    private func clearRenameState() {
        renameTarget = nil
        renameDraft = ""
    }

    private func saveFilingDraft(for recordingID: String) {
        let filing = StudyFilingPath(
            type: typeDraft,
            subject: subjectDraft,
            chapter: chapterDraft,
            topic: topicDraft
        )

        do {
            try recordingManager.updateStudyFiling(recordingID: recordingID, studyFiling: filing)
            operationStatusMessage = "归档已保存"
            keepBrowsePathValid()
            if let updated = recordingManager.recordings.first(where: { $0.id == recordingID }) {
                detailTarget = updated
            }
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func beginDelete(_ metadata: RecordingMetadata) {
        deleteTarget = metadata
        isDeleteConfirmationPresented = true
    }

    private func commitDelete() {
        guard let deleteTarget else {
            return
        }

        do {
            try recordingManager.deleteRecording(recordingID: deleteTarget.id)
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.deleteFailure
        }

        self.deleteTarget = nil
    }

    private func restoreFromTrash(_ metadata: RecordingMetadata) {
        do {
            try recordingManager.restoreRecording(recordingID: metadata.id)
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
            keepBrowsePathValid()
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.deleteFailure
        }

        self.permanentDeleteTarget = nil
    }

    private func keepBrowsePathValid() {
        while !browsePath.isRoot {
            let content = RecordingStudyBrowser.content(recordings: recordingManager.recordings, path: browsePath)
            guard content.folders.isEmpty && content.recordings.isEmpty else {
                break
            }

            browsePath = browsePath.parent
        }
    }
}

private struct RecordingStudyFolderRow: View {
    let folder: RecordingStudyFolder
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 13) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(folder.isFallback ? RokuricsColors.softTeal : RokuricsColors.aqua)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.title)
                        .font(RokuricsTypography.font(for: .cardTitle))
                        .foregroundStyle(RokuricsColors.deepText)
                        .lineLimit(1)

                    Text("\(folder.itemCount) 项")
                        .font(RokuricsTypography.caption(size: 11, weight: .semibold))
                        .foregroundStyle(RokuricsColors.softText)
                }

                Spacer(minLength: 10)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RokuricsColors.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rokuricsLiquidGlassCard(cornerRadius: 20, fillOpacity: 0.34, strokeOpacity: 0.34, shadowOpacity: 0.06, shadowRadius: 9, shadowY: 4)
        }
        .buttonStyle(RokuricsScaleButtonStyle())
    }
}

private struct RecordingStudyCard: View {
    let metadata: RecordingMetadata
    let uploadStatus: RecordingUploadStatus
    let isMacPaired: Bool
    let onOpenDetail: () -> Void

    var body: some View {
        let uploadPresentation = RecordingUploadCapsulePresentation.resolve(
            status: uploadStatus,
            isMacPaired: isMacPaired
        )

        Button(action: onOpenDetail) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(RokuricsColors.aqua)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(metadata.title)
                            .font(RokuricsTypography.cardTitle(size: 15, weight: .semibold))
                            .foregroundStyle(RokuricsColors.deepText)
                            .lineLimit(1)

                        Text("\(Self.dateFormatter.string(from: metadata.createdAt)) · \(Self.durationText(metadata.duration))")
                            .font(RokuricsTypography.numberBody(size: 12, weight: .semibold))
                            .foregroundStyle(RokuricsColors.softText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "info.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(RokuricsColors.softText)
                }

                HStack(spacing: 8) {
                    RecordingStudyStatusChip(text: uploadPresentation.label, systemImage: "arrow.up.circle")
                    RecordingStudyStatusChip(text: transcriptionText, systemImage: metadata.transcriptionStatus == "transcribed" ? "checkmark.circle" : "text.quote")
                    RecordingStudyStatusChip(text: noteText, systemImage: metadata.noteStatus == "generated" ? "doc.text.fill" : "doc.text")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rokuricsLiquidGlassCard(cornerRadius: 20, fillOpacity: 0.34, strokeOpacity: 0.34, shadowOpacity: 0.06, shadowRadius: 9, shadowY: 4)
        }
        .buttonStyle(RokuricsScaleButtonStyle())
    }

    private var transcriptionText: String {
        switch metadata.transcriptionStatus {
        case "transcribed":
            return "已转写"
        case "transcribing", "queued":
            return "转写中"
        case "failed":
            return "转写失败"
        default:
            return "未转写"
        }
    }

    private var noteText: String {
        switch metadata.noteStatus {
        case "generated":
            return "有笔记"
        case "generating":
            return "笔记中"
        case "failed":
            return "笔记失败"
        default:
            return "无笔记"
        }
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return minutes == 0 ? "\(remainingSeconds)''" : "\(minutes)'\(String(format: "%02d", remainingSeconds))''"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

private struct RecordingStudyDetailSheet: View {
    let metadata: RecordingMetadata
    let uploadStatus: RecordingUploadStatus
    let isMacPaired: Bool
    let errorMessage: String?
    @Binding var type: String
    @Binding var subject: String
    @Binding var chapter: String
    @Binding var topic: String
    let candidates: StudyFilingCandidates
    let statusMessage: String?
    let onUpload: () -> Void
    let onSaveFiling: () -> Void
    let onRenameRequested: () -> Void
    let onMoveToTrashRequested: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let uploadPresentation = RecordingUploadCapsulePresentation.resolve(
            status: uploadStatus,
            isMacPaired: isMacPaired
        )

        NavigationStack {
            ZStack {
                RokuricsColors.pageGradient
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(metadata.title)
                                .font(RokuricsTypography.pageTitle(size: 26, weight: .bold))
                                .foregroundStyle(RokuricsColors.deepText)
                                .lineLimit(2)

                            Text("\(Self.dateFormatter.string(from: metadata.createdAt)) · \(Self.durationText(metadata.duration))")
                                .font(RokuricsTypography.numberBody(size: 12, weight: .semibold))
                                .foregroundStyle(RokuricsColors.softText)
                        }

                        HStack(spacing: 8) {
                            RecordingStudyStatusChip(text: uploadPresentation.label, systemImage: "arrow.up.circle")
                            RecordingStudyStatusChip(text: transcriptionText, systemImage: metadata.transcriptionStatus == "transcribed" ? "checkmark.circle" : "text.quote")
                            RecordingStudyStatusChip(text: noteText, systemImage: metadata.noteStatus == "generated" ? "doc.text.fill" : "doc.text")
                        }

                        detailSection(title: "四层归档") {
                            RecordingStudyFilingEditor(
                                type: $type,
                                subject: $subject,
                                chapter: $chapter,
                                topic: $topic,
                                candidates: candidates,
                                onSave: onSaveFiling
                            )

                            if let statusMessage {
                                Text(statusMessage)
                                    .font(RokuricsTypography.caption(size: 12, weight: .bold))
                                    .foregroundStyle(RokuricsColors.softTeal)
                            }
                        }

                        detailSection(title: "操作") {
                            VStack(spacing: 10) {
                                Button(action: onUpload) {
                                    Label(uploadPresentation.label, systemImage: "arrow.up.circle")
                                        .font(RokuricsTypography.caption(size: 12, weight: .bold))
                                        .foregroundStyle(uploadPresentation.isEnabled ? RokuricsColors.deepText : RokuricsColors.tertiaryText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .rokuricsGlassCapsule(fillOpacity: uploadPresentation.isEnabled ? 0.32 : 0.18, strokeOpacity: 0.26)
                                }
                                .buttonStyle(RokuricsScaleButtonStyle())
                                .disabled(!uploadPresentation.isEnabled)

                                Button(action: onRenameRequested) {
                                    Label("重命名", systemImage: "pencil")
                                        .font(RokuricsTypography.caption(size: 12, weight: .bold))
                                        .foregroundStyle(RokuricsColors.deepText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .rokuricsGlassCapsule(fillOpacity: 0.28, strokeOpacity: 0.26)
                                }
                                .buttonStyle(RokuricsScaleButtonStyle())

                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(RokuricsTypography.caption(size: 11, weight: .semibold))
                                        .foregroundStyle(RokuricsColors.coral)
                                        .lineLimit(3)
                                }
                            }
                        }

                        detailSection(title: "危险操作") {
                            Button(role: .destructive, action: onMoveToTrashRequested) {
                                Label("移入废纸篓", systemImage: "trash")
                                    .font(RokuricsTypography.caption(size: 12, weight: .bold))
                                    .foregroundStyle(RokuricsColors.coral)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .rokuricsGlassCapsule(fillOpacity: 0.20, strokeOpacity: 0.24)
                            }
                            .buttonStyle(RokuricsScaleButtonStyle())
                        }
                    }
                    .padding(22)
                }
            }
            .navigationTitle("录音详情")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var transcriptionText: String {
        switch metadata.transcriptionStatus {
        case "transcribed":
            return "已转写"
        case "transcribing", "queued":
            return "转写中"
        case "failed":
            return "转写失败"
        default:
            return "未转写"
        }
    }

    private var noteText: String {
        switch metadata.noteStatus {
        case "generated":
            return "有笔记"
        case "generating":
            return "笔记中"
        case "failed":
            return "笔记失败"
        default:
            return "无笔记"
        }
    }

    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(RokuricsTypography.sectionTitle(size: 18, weight: .bold))
                .foregroundStyle(RokuricsColors.deepText)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsLiquidGlassCard(cornerRadius: 22, fillOpacity: 0.34, strokeOpacity: 0.34, shadowOpacity: 0.06, shadowRadius: 9, shadowY: 4)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return minutes == 0 ? "\(remainingSeconds)''" : "\(minutes)'\(String(format: "%02d", remainingSeconds))''"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private struct RecordingStudyFilingEditor: View {
    @Binding var type: String
    @Binding var subject: String
    @Binding var chapter: String
    @Binding var topic: String
    let candidates: StudyFilingCandidates
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RecordingStudyFilingField(title: "门类", placeholder: "课堂", text: $type, candidates: candidates.types)
            RecordingStudyFilingField(title: "课程", placeholder: "线性代数", text: $subject, candidates: candidates.subjects)
            RecordingStudyFilingField(title: "章节", placeholder: "矩阵", text: $chapter, candidates: candidates.chapters)
            RecordingStudyFilingField(title: "主题", placeholder: "矩阵乘法", text: $topic, candidates: candidates.topics)

            Button(action: onSave) {
                Label("保存归档", systemImage: "checkmark")
                    .font(RokuricsTypography.caption(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RokuricsColors.actionGradient, in: Capsule())
            }
            .buttonStyle(RokuricsScaleButtonStyle())
            .padding(.top, 2)
        }
    }
}

private struct RecordingStudyFilingField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let candidates: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(RokuricsTypography.caption(size: 11, weight: .bold))
                .foregroundStyle(RokuricsColors.softText)

            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .font(RokuricsTypography.body(size: 14, weight: .medium))
                    .textFieldStyle(.plain)

                Menu {
                    if candidates.isEmpty {
                        Text("暂无已有值")
                    } else {
                        ForEach(candidates, id: \.self) { candidate in
                            Button(candidate) {
                                text = candidate
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(RokuricsColors.aqua)
                        .frame(width: 30, height: 30)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .rokuricsGlassCapsule(fillOpacity: 0.24, strokeOpacity: 0.26)
        }
    }
}

private struct RecordingStudyStatusChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(RokuricsTypography.caption(size: 10, weight: .bold))
            .foregroundStyle(RokuricsColors.softText)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .rokuricsGlassCapsule(fillOpacity: 0.22, strokeOpacity: 0.22)
    }
}

private struct RecordingTrashSheet: View {
    let recordings: [RecordingMetadata]
    let onRestore: (RecordingMetadata) -> Void
    let onPermanentDelete: (RecordingMetadata) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                RokuricsColors.pageGradient
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    if recordings.isEmpty {
                        Text("废纸篓为空")
                            .font(RokuricsTypography.body(size: 15, weight: .medium))
                            .foregroundStyle(RokuricsColors.softText)
                            .padding(22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .rokuricsLiquidGlassCard(cornerRadius: 22, fillOpacity: 0.34, strokeOpacity: 0.34, shadowOpacity: 0.08, shadowRadius: 8, shadowY: 4)
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 12) {
                                ForEach(recordings) { metadata in
                                    RecordingTrashRow(
                                        metadata: metadata,
                                        onRestore: { onRestore(metadata) },
                                        onPermanentDelete: { onPermanentDelete(metadata) }
                                    )
                                }
                            }
                            .padding(.bottom, 18)
                        }
                    }
                }
                .padding(22)
            }
            .navigationTitle("废纸篓")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct RecordingTrashRow: View {
    let metadata: RecordingMetadata
    let onRestore: () -> Void
    let onPermanentDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(RokuricsColors.softText)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 6) {
                RokuricsMixedFontText(
                    text: metadata.title,
                    chineseFont: RokuricsTypography.chineseBody(size: 15, weight: .semibold),
                    englishFont: RokuricsTypography.englishBody(size: 15, weight: .semibold),
                    numberFont: RokuricsTypography.numberBody(size: 15, weight: .semibold)
                )
                .foregroundStyle(RokuricsColors.deepText)
                .lineLimit(1)

                HStack(spacing: 6) {
                    Text(Self.dateFormatter.string(from: metadata.createdAt))
                    Text("·")
                    Text(Self.durationText(metadata.duration))
                }
                .font(RokuricsTypography.numberBody(size: 12, weight: .semibold))
                .foregroundStyle(RokuricsColors.softText)
            }

            Spacer(minLength: 10)

            Button("恢复", action: onRestore)
                .font(RokuricsTypography.caption(size: 12, weight: .bold))
                .foregroundStyle(RokuricsColors.deepText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .rokuricsGlassCapsule(fillOpacity: 0.28, strokeOpacity: 0.28)

            Button("永久删除", action: onPermanentDelete)
                .font(RokuricsTypography.caption(size: 12, weight: .bold))
                .foregroundStyle(RokuricsColors.coral)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .rokuricsGlassCapsule(fillOpacity: 0.20, strokeOpacity: 0.24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .rokuricsLiquidGlassCard(cornerRadius: 18, fillOpacity: 0.32, strokeOpacity: 0.30, shadowOpacity: 0.06, shadowRadius: 8, shadowY: 4)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return minutes == 0 ? "\(remainingSeconds)''" : "\(minutes)'\(String(format: "%02d", remainingSeconds))''"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        RecordingLibraryView(
            recordingManager: RecordingManager(),
            macConnectionStore: SecureMacConnectionStore()
        )
    }
}
