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
    @State private var renameTarget: RecordingMetadata?
    @State private var renameDraft = ""
    @State private var isRenameAlertPresented = false
    @State private var deleteTarget: RecordingMetadata?
    @State private var isDeleteConfirmationPresented = false
    @State private var isTrashSheetPresented = false
    @State private var permanentDeleteTarget: RecordingMetadata?
    @State private var isPermanentDeleteConfirmationPresented = false
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
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            ForEach(recordingManager.recordings) { metadata in
                                UploadableRecordingRow(
                                    metadata: metadata,
                                    uploadStatus: uploadCoordinator.displayStatus(for: metadata),
                                    isMacPaired: macConnectionStore.isPaired,
                                    errorMessage: uploadCoordinator.errorMessage(for: metadata),
                                    onUpload: {
                                        uploadCoordinator.upload(
                                            metadata: metadata,
                                            settings: macConnectionStore.snapshot,
                                            recordingManager: recordingManager
                                        )
                                    },
                                    onRenameRequested: {
                                        beginRename(metadata)
                                    },
                                    onMoveToTrashRequested: {
                                        beginDelete(metadata)
                                    }
                                )
                                .contextMenu {
                                    Button {
                                        beginRename(metadata)
                                    } label: {
                                        Label("重命名", systemImage: "pencil")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.bottom, 28)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            macConnectionStore.refreshFromStorage()
            recordingManager.reloadRecordings()
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
                    Button {
                        isTrashSheetPresented = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(RokuricsColors.softText)
                            .frame(width: 40, height: 40)
                            .rokuricsGlassCircle(fillOpacity: 0.26, strokeOpacity: 0.30, shadowOpacity: 0.06, shadowRadius: 7, shadowY: 3)
                    }
                    .buttonStyle(RokuricsScaleButtonStyle())
                    .accessibilityLabel("打开废纸篓")

                    Text("\(recordingManager.recordings.count)")
                        .font(RokuricsTypography.largeNumber(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(RokuricsColors.aqua)
                        .frame(width: 44, height: 44)
                        .rokuricsGlassCircle(fillOpacity: 0.32, strokeOpacity: 0.36, shadowOpacity: 0.08, shadowRadius: 8, shadowY: 4)
                }
            }

            Text("录音")
                .font(RokuricsTypography.chineseTitle(size: 34, weight: .bold))
                .foregroundStyle(RokuricsColors.deepText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(RokuricsColors.aqua)
                .frame(width: 64, height: 64)
                .rokuricsGlassCircle(fillOpacity: 0.38, strokeOpacity: 0.38, shadowOpacity: 0.08, shadowRadius: 12, shadowY: 6)

            Text("暂无录音")
                .font(RokuricsTypography.headline(size: 18, weight: .semibold))
                .foregroundStyle(RokuricsColors.deepText)

            Text("新的录音会保存在本地沙盒，并在这里显示 metadata。")
                .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                .foregroundStyle(RokuricsColors.softText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .rokuricsLiquidGlassCard(cornerRadius: 30, fillOpacity: 0.38, strokeOpacity: 0.42, shadowOpacity: 0.10, shadowRadius: 18, shadowY: 10)
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
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.renameFailure
        }

        clearRenameState()
    }

    private func clearRenameState() {
        renameTarget = nil
        renameDraft = ""
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
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.deleteFailure
        }

        self.deleteTarget = nil
    }

    private func restoreFromTrash(_ metadata: RecordingMetadata) {
        do {
            try recordingManager.restoreRecording(recordingID: metadata.id)
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
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.deleteFailure
        }

        self.permanentDeleteTarget = nil
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
