//
//  MacAudioInboxView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/12.
//

import SwiftUI

struct MacAudioInboxView: View {
    @ObservedObject var audioInboxStore: AudioInboxStore
    @ObservedObject var transcriptionCoordinator: TranscriptionCoordinator
    @ObservedObject var noteGenerationCoordinator: NoteGenerationCoordinator
    @State private var selectedTranscriptItem: MacRecordingInboxItem?
    @State private var selectedNoteItem: MacRecordingInboxItem?
    @State private var deleteTarget: MacRecordingInboxItem?
    @State private var isDeleteConfirmationPresented = false
    @State private var isTrashSheetPresented = false
    @State private var permanentDeleteTarget: MacRecordingInboxItem?
    @State private var isPermanentDeleteConfirmationPresented = false
    @State private var operationErrorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            MacDetailContentContainer(maxWidth: selectedTranscriptItem == nil && selectedNoteItem == nil ? 980 : 940) {
                if let selectedTranscriptItem {
                    MacTranscriptDetailView(
                        item: selectedTranscriptItem,
                        onBack: {
                            self.selectedTranscriptItem = nil
                        }
                    )
                } else if let selectedNoteItem {
                    MacNoteDetailView(
                        item: selectedNoteItem,
                        onBack: {
                            self.selectedNoteItem = nil
                        }
                    )
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        MacPageHeader(
                            systemImage: "tray.and.arrow.down",
                            title: .english("Audio Inbox"),
                            subtitle: nil
                        )

                        HStack(spacing: 12) {
                            MacInboxMetricPill(title: "真实录音", value: "\(audioInboxStore.pendingCount)", tint: MacTheme.aqua)
                            MacInboxMetricPill(title: "待转写", value: "\(audioInboxStore.transcriptionPendingCount)", tint: MacTheme.mint)
                            MacInboxMetricPill(title: "已转写", value: "\(audioInboxStore.transcribedCount)", tint: MacTheme.leaf)

                            Spacer(minLength: 8)

                            MacInboxTrashButton(count: audioInboxStore.trashItems.count) {
                                isTrashSheetPresented = true
                            }
                        }

                        Text("1516")
                            .font(MacTypography.numberBody(size: 10, weight: .medium))
                            .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                            .opacity(0.64)

                        if audioInboxStore.recordingItems.isEmpty {
                            Text("暂无收到的录音")
                                .font(MacTypography.chineseBody(size: 15, weight: .medium))
                                .foregroundStyle(MacTheme.softText(for: colorScheme))
                                .padding(22)
                                .frame(maxWidth: 620, alignment: .leading)
                                .macLiquidGlassCard(cornerRadius: 22, material: .ultraThinMaterial, fillOpacity: 0.32, strokeOpacity: 0.28, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(audioInboxStore.recordingItems) { item in
                                    MacAudioInboxListRow(
                                        item: item,
                                        isTranscribing: transcriptionCoordinator.isTranscribing(recordingID: item.id),
                                        isGeneratingNote: noteGenerationCoordinator.isGenerating(recordingID: item.id),
                                        onTranscribe: {
                                            transcriptionCoordinator.startTranscription(recordingID: item.id)
                                        },
                                        onViewTranscript: {
                                            selectedTranscriptItem = item
                                        },
                                        onGenerateNote: {
                                            noteGenerationCoordinator.startNoteGeneration(recordingID: item.id)
                                        },
                                        onViewNote: {
                                            selectedNoteItem = item
                                        },
                                        onRename: { rawTitle in
                                            commitInlineRename(item: item, rawTitle: rawTitle)
                                        },
                                        onDelete: {
                                            beginDelete(item)
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .onAppear {
            audioInboxStore.refreshRecordingInbox()
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
            Text(RecordingLocalOperationCopy.macMoveToTrashMessage)
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
        .alert("操作失败", isPresented: operationErrorBinding) {
            Button("好", role: .cancel) {
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

    private func commitInlineRename(item: MacRecordingInboxItem, rawTitle: String) {
        guard RecordingTitleEditRules.shouldSave(rawTitle: rawTitle, currentTitle: item.title) else {
            return
        }

        do {
            try audioInboxStore.renameRecording(recordingID: item.id, rawTitle: rawTitle)
            if selectedTranscriptItem?.id == item.id {
                selectedTranscriptItem = audioInboxStore.recordingItems.first { $0.id == item.id }
            }
            if selectedNoteItem?.id == item.id {
                selectedNoteItem = audioInboxStore.recordingItems.first { $0.id == item.id }
            }
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.renameFailure
        }
    }

    private func beginDelete(_ item: MacRecordingInboxItem) {
        deleteTarget = item
        isDeleteConfirmationPresented = true
    }

    private func commitDelete() {
        guard let deleteTarget else {
            return
        }

        do {
            try audioInboxStore.deleteRecording(recordingID: deleteTarget.id)
            if selectedTranscriptItem?.id == deleteTarget.id {
                selectedTranscriptItem = nil
            }
            if selectedNoteItem?.id == deleteTarget.id {
                selectedNoteItem = nil
            }
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.deleteFailure
        }

        self.deleteTarget = nil
    }

    private func restoreFromTrash(_ item: MacRecordingInboxItem) {
        do {
            try audioInboxStore.restoreRecording(recordingID: item.id)
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
        } catch {
            operationErrorMessage = RecordingLocalOperationCopy.deleteFailure
        }

        self.permanentDeleteTarget = nil
    }
}

private struct MacInboxMetricPill: View {
    let title: String
    let value: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.softText(for: colorScheme))

            Text(value)
                .font(MacTypography.numberBody(size: 18, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .macGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.30)
    }
}

private struct MacInboxTrashButton: View {
    let count: Int
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Label(count > 0 ? "废纸篓 \(count)" : "废纸篓", systemImage: "trash")
                .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .macGlassCapsule(fillOpacity: 0.24, strokeOpacity: 0.24)
        }
        .buttonStyle(.plain)
        .help("打开废纸篓")
    }
}

struct MacAudioInboxIconPresentation: Equatable {
    let systemImage: String
    let isDestructive: Bool
    let glyphSize: CGFloat
    let containerSize: CGFloat

    static func resolve(isDeleteIconHovered: Bool) -> MacAudioInboxIconPresentation {
        MacAudioInboxIconPresentation(
            systemImage: isDeleteIconHovered ? "trash.fill" : "waveform",
            isDestructive: isDeleteIconHovered,
            glyphSize: isDeleteIconHovered ? 14 : 16,
            containerSize: 38
        )
    }
}

private struct MacRecordingLeadingIcon: View {
    let isDeleteIconHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var presentation: MacAudioInboxIconPresentation {
        MacAudioInboxIconPresentation.resolve(isDeleteIconHovered: isDeleteIconHovered)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(containerFill)

            Circle()
                .stroke(containerStroke, lineWidth: 1)

            Image(systemName: presentation.systemImage)
                .font(.system(size: presentation.glyphSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(glyphColor)
                .frame(width: 20, height: 20)
        }
        .background(.ultraThinMaterial, in: Circle())
        .frame(width: presentation.containerSize, height: presentation.containerSize)
        .scaleEffect(isDeleteIconHovered ? 1.015 : 1)
        .animation(.easeInOut(duration: 0.12), value: isDeleteIconHovered)
    }

    private var containerFill: Color {
        if presentation.isDestructive {
            return MacTheme.coral.opacity(colorScheme == .dark ? 0.11 : 0.09)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.075)
            : Color.white.opacity(0.58)
    }

    private var containerStroke: LinearGradient {
        let accent = presentation.isDestructive ? MacTheme.coral : MacTheme.aqua

        return LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.62),
                accent.opacity(presentation.isDestructive ? 0.42 : 0.34)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glyphColor: Color {
        presentation.isDestructive
            ? MacTheme.coral.opacity(colorScheme == .dark ? 0.86 : 0.78)
            : MacTheme.aqua
    }
}

struct MacAudioInboxListRow: View {
    let item: MacRecordingInboxItem
    let isTranscribing: Bool
    let isGeneratingNote: Bool
    let onTranscribe: () -> Void
    let onViewTranscript: () -> Void
    let onGenerateNote: () -> Void
    let onViewNote: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void
    @State private var isDeleteIconHovered = false
    @State private var isTitleEditing = false
    @State private var titleDraft = ""
    @FocusState private var isTitleFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let action = MacAudioInboxRowAction.resolve(for: item, isTranscribing: isTranscribing)
        let noteAction = MacAudioInboxNoteRowAction.resolve(for: item, isGenerating: isGeneratingNote)
        let regenerateNoteAction = MacAudioInboxNoteRowAction.regenerateAction(for: item, isGenerating: isGeneratingNote)

        HStack(spacing: 14) {
            deleteHoverIcon

            titleArea
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            Text(Self.dateTimeFormatter.string(from: item.receivedAt))
                .font(rowMetaFont)
                .foregroundStyle(rowMetaColor)
                .lineLimit(1)
                .frame(width: 98, alignment: .trailing)

            Text(durationText(item.duration))
                .font(rowMetaFont)
                .foregroundStyle(rowMetaColor)
                .frame(width: 62, alignment: .trailing)

            actionArea(
                action: action,
                noteAction: noteAction,
                regenerateNoteAction: regenerateNoteAction
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassCard(cornerRadius: 18, material: .ultraThinMaterial, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
        .onChange(of: item.title) {
            if !isTitleEditing {
                titleDraft = item.title
            }
        }
    }

    private var deleteHoverIcon: some View {
        let presentation = MacAudioInboxIconPresentation.resolve(isDeleteIconHovered: isDeleteIconHovered)

        return Button {
            if isDeleteIconHovered {
                onDelete()
            }
        } label: {
            MacRecordingLeadingIcon(isDeleteIconHovered: presentation.isDestructive)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.12)) {
                isDeleteIconHovered = isHovered
            }
        }
        .help(isDeleteIconHovered ? "移入废纸篓" : "录音")
    }

    @ViewBuilder
    private var titleArea: some View {
        if isTitleEditing {
            TextField("录音名称", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(MacTypography.chineseBody(size: 16, weight: .semibold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.42))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MacTheme.aqua.opacity(colorScheme == .dark ? 0.26 : 0.32), lineWidth: 1)
                }
                .focused($isTitleFocused)
                .onSubmit(commitTitleEdit)
                .onExitCommand(perform: cancelTitleEdit)
                .onChange(of: isTitleFocused) { _, isFocused in
                    if !isFocused && isTitleEditing {
                        commitTitleEdit()
                    }
                }
        } else {
            Button(action: beginTitleEdit) {
                MacMixedFontText(
                    text: item.title,
                    chineseFont: MacTypography.chineseBody(size: 16, weight: .semibold),
                    englishFont: MacTypography.englishBody(size: 16, weight: .semibold),
                    numberFont: MacTypography.numberBody(size: 16, weight: .semibold)
                )
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("点击重命名")
        }
    }

    private var rowMetaFont: Font {
        MacTypography.numberBody(size: 15, weight: .semibold)
    }

    private var rowMetaColor: Color {
        MacTheme.softText(for: colorScheme)
    }

    @ViewBuilder
    private func actionArea(
        action: MacAudioInboxRowAction,
        noteAction: MacAudioInboxNoteRowAction?,
        regenerateNoteAction: MacAudioInboxNoteRowAction?
    ) -> some View {
        let width = actionGroupWidth(noteAction: noteAction, regenerateNoteAction: regenerateNoteAction)
        if let transfer = item.localNetworkReceiveTransferProgress,
           transfer.isVisibleInActionArea {
            StudyRecordingTransferProgressView(transfer: transfer)
                .frame(width: max(width, 132), alignment: .trailing)
        } else {
            HStack(spacing: 8) {
                MacAudioInboxActionCapsule(
                    action: action,
                    helpText: action.intent == .startTranscription ? item.transcriptionError : nil,
                    onAction: {
                        switch action.intent {
                        case .startTranscription:
                            onTranscribe()
                        case .viewTranscript:
                            onViewTranscript()
                        case .wait:
                            break
                        }
                    }
                )
                .frame(width: 92, alignment: .trailing)

                if let noteAction {
                    MacAudioInboxNoteActionCapsule(
                        action: noteAction,
                        helpText: item.noteError,
                        onAction: {
                            switch noteAction.intent {
                            case .generate:
                                onGenerateNote()
                            case .viewNote:
                                onViewNote()
                            case .wait:
                                break
                            }
                        }
                    )
                    .frame(width: 92, alignment: .trailing)
                }

                if let regenerateNoteAction {
                    MacAudioInboxNoteActionCapsule(
                        action: regenerateNoteAction,
                        helpText: nil,
                        onAction: {
                            switch regenerateNoteAction.intent {
                            case .generate:
                                onGenerateNote()
                            case .viewNote:
                                onViewNote()
                            case .wait:
                                break
                            }
                        }
                    )
                    .frame(width: 92, alignment: .trailing)
                }
            }
            .frame(width: width, alignment: .trailing)
        }
    }

    private func beginTitleEdit() {
        titleDraft = item.title
        isTitleEditing = true
        DispatchQueue.main.async {
            isTitleFocused = true
        }
    }

    private func commitTitleEdit() {
        guard isTitleEditing else {
            return
        }

        let submittedTitle = titleDraft
        isTitleEditing = false
        isTitleFocused = false
        onRename(submittedTitle)
    }

    private func cancelTitleEdit() {
        titleDraft = item.title
        isTitleEditing = false
        isTitleFocused = false
    }

    private func actionGroupWidth(
        noteAction: MacAudioInboxNoteRowAction?,
        regenerateNoteAction: MacAudioInboxNoteRowAction?
    ) -> CGFloat {
        let buttonCount = 1
            + (noteAction == nil ? 0 : 1)
            + (regenerateNoteAction == nil ? 0 : 1)
        let buttonWidth: CGFloat = 92
        let gapWidth: CGFloat = 8
        return CGFloat(buttonCount) * buttonWidth + CGFloat(max(0, buttonCount - 1)) * gapWidth
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60

        if minutes == 0 {
            return "\(remainingSeconds)''"
        }

        return "\(minutes)'\(String(format: "%02d", remainingSeconds))''"
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

struct MacAudioInboxRowAction: Equatable {
    enum Intent: Equatable {
        case startTranscription
        case wait
        case viewTranscript
    }

    let label: String
    let intent: Intent
    let isEnabled: Bool

    static func resolve(
        for item: MacRecordingInboxItem,
        isTranscribing: Bool
    ) -> MacAudioInboxRowAction {
        if isTranscribing || item.isTranscriptionActive {
            return MacAudioInboxRowAction(label: "转写中", intent: .wait, isEnabled: false)
        }

        if item.isTranscribed {
            return MacAudioInboxRowAction(label: "查看转写", intent: .viewTranscript, isEnabled: true)
        }

        return MacAudioInboxRowAction(
            label: "转写",
            intent: .startTranscription,
            isEnabled: item.hasAudio
        )
    }
}

struct MacAudioInboxNoteRowAction: Equatable {
    enum Intent: Equatable {
        case generate
        case wait
        case viewNote
    }

    let label: String
    let intent: Intent
    let isEnabled: Bool

    static func resolve(
        for item: MacRecordingInboxItem,
        isGenerating: Bool
    ) -> MacAudioInboxNoteRowAction? {
        guard item.isTranscribed else {
            return nil
        }

        if isGenerating || item.isNoteGenerating {
            return MacAudioInboxNoteRowAction(label: "生成中", intent: .wait, isEnabled: false)
        }

        if item.isNoteGenerated {
            return MacAudioInboxNoteRowAction(label: "查看笔记", intent: .viewNote, isEnabled: true)
        }

        if item.isNoteFailed {
            return MacAudioInboxNoteRowAction(label: "重试笔记", intent: .generate, isEnabled: true)
        }

        return MacAudioInboxNoteRowAction(label: "生成笔记", intent: .generate, isEnabled: true)
    }

    static func regenerateAction(
        for item: MacRecordingInboxItem,
        isGenerating: Bool
    ) -> MacAudioInboxNoteRowAction? {
        guard item.isTranscribed,
              item.isNoteGenerated,
              !isGenerating,
              !item.isNoteGenerating else {
            return nil
        }

        return MacAudioInboxNoteRowAction(label: "重新生成", intent: .generate, isEnabled: true)
    }
}

private struct MacAudioInboxActionCapsule: View {
    let action: MacAudioInboxRowAction
    let helpText: String?
    let onAction: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if action.intent == .wait {
                capsuleLabel
            } else {
                Button(action: onAction) {
                    capsuleLabel
                }
                .buttonStyle(.plain)
                .disabled(!action.isEnabled)
            }
        }
        .opacity(action.isEnabled || action.intent == .wait ? 1 : 0.52)
        .help(helpText ?? action.label)
    }

    private var capsuleLabel: some View {
        Text(action.label)
            .font(MacTypography.chineseCaption(size: 12, weight: .bold))
            .foregroundStyle(MacTheme.deepText(for: colorScheme))
            .lineLimit(1)
            .frame(width: 76)
            .padding(.vertical, 7)
            .macGlassCapsule(fillOpacity: fillOpacity, strokeOpacity: 0.30)
    }

    private var fillOpacity: Double {
        switch action.intent {
        case .startTranscription:
            return 0.34
        case .wait:
            return 0.26
        case .viewTranscript:
            return 0.38
        }
    }
}

private struct MacAudioInboxNoteActionCapsule: View {
    let action: MacAudioInboxNoteRowAction
    let helpText: String?
    let onAction: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if action.intent == .wait {
                capsuleLabel
            } else {
                Button(action: onAction) {
                    capsuleLabel
                }
                .buttonStyle(.plain)
                .disabled(!action.isEnabled)
            }
        }
        .opacity(action.isEnabled || action.intent == .wait ? 1 : 0.52)
        .help(helpText ?? action.label)
    }

    private var capsuleLabel: some View {
        Text(action.label)
            .font(MacTypography.chineseCaption(size: 12, weight: .bold))
            .foregroundStyle(MacTheme.deepText(for: colorScheme))
            .lineLimit(1)
            .frame(width: 76)
            .padding(.vertical, 7)
            .macGlassCapsule(fillOpacity: fillOpacity, strokeOpacity: 0.30)
    }

    private var fillOpacity: Double {
        switch action.intent {
        case .generate:
            return 0.34
        case .wait:
            return 0.26
        case .viewNote:
            return 0.40
        }
    }
}

struct MacAudioInboxTrashSheet: View {
    let items: [MacRecordingInboxItem]
    let onRestore: (MacRecordingInboxItem) -> Void
    let onPermanentDelete: (MacRecordingInboxItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("废纸篓")
                            .font(MacTypography.chineseHeadline(size: 22))
                            .foregroundStyle(MacTheme.deepText(for: colorScheme))

                        Text("已移入废纸篓的录音")
                            .font(MacTypography.chineseCaption(size: 12, weight: .medium))
                            .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                    }

                    Spacer()

                    Button("完成") {
                        dismiss()
                    }
                    .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .macGlassCapsule(fillOpacity: 0.28, strokeOpacity: 0.26)
                }

                if items.isEmpty {
                    Text("废纸篓为空")
                        .font(RokuricsDetailTypography.metadataValue)
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .macLiquidGlassCard(cornerRadius: 18, material: .ultraThinMaterial, fillOpacity: 0.30, strokeOpacity: 0.26, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(items) { item in
                                MacAudioInboxTrashRow(
                                    item: item,
                                    onRestore: { onRestore(item) },
                                    onPermanentDelete: { onPermanentDelete(item) }
                                )
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct MacAudioInboxTrashRow: View {
    let item: MacRecordingInboxItem
    let onRestore: () -> Void
    let onPermanentDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trash")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 6) {
                MacMixedFontText(
                    text: item.title,
                    chineseFont: MacTypography.chineseBody(size: 15, weight: .semibold),
                    englishFont: MacTypography.englishBody(size: 15, weight: .semibold),
                    numberFont: MacTypography.numberBody(size: 15, weight: .semibold)
                )
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(1)

                HStack(spacing: 6) {
                    Text(Self.dateFormatter.string(from: item.receivedAt))
                    Text("·")
                    Text(Self.durationText(item.duration))
                }
                .font(MacTypography.numberBody(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
            }

            Spacer(minLength: 12)

            Button("恢复", action: onRestore)
                .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .macGlassCapsule(fillOpacity: 0.30, strokeOpacity: 0.26)

            Button("永久删除", action: onPermanentDelete)
                .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                .foregroundStyle(MacTheme.coral)
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .macGlassCapsule(fillOpacity: 0.20, strokeOpacity: 0.22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .macLiquidGlassCard(cornerRadius: 16, material: .ultraThinMaterial, fillOpacity: 0.30, strokeOpacity: 0.24, shadowOpacity: 0.03, shadowRadius: 7, shadowY: 3)
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

private enum RecordingRowLayout {
    case regular
}

private struct RecordingRowContent<Trailing: View>: View {
    let title: String
    let dateTimeText: String
    let durationText: String
    let layout: RecordingRowLayout
    private let trailing: Trailing
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        dateTimeText: String,
        durationText: String,
        layout: RecordingRowLayout,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.dateTimeText = dateTimeText
        self.durationText = durationText
        self.layout = layout
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(MacTheme.aqua, .white.opacity(0.88))
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 7) {
                MacMixedFontText(
                    text: title,
                    chineseFont: MacTypography.chineseBody(size: 16, weight: .semibold),
                    englishFont: MacTypography.englishBody(size: 16, weight: .semibold),
                    numberFont: MacTypography.numberBody(size: 16, weight: .semibold)
                )
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(1)
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            Text(dateTimeText)
                .font(rowMetaFont)
                .foregroundStyle(rowMetaColor)
                .lineLimit(1)
                .frame(width: 98, alignment: .trailing)

            Text(durationText)
                .font(rowMetaFont)
                .foregroundStyle(rowMetaColor)
                .frame(width: 62, alignment: .trailing)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassCard(cornerRadius: 18, material: .ultraThinMaterial, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
    }

    private var rowMetaFont: Font {
        switch layout {
        case .regular:
            return MacTypography.numberBody(size: 15, weight: .semibold)
        }
    }

    private var rowMetaColor: Color {
        MacTheme.softText(for: colorScheme)
    }
}

struct MacTranscriptDetailView: View {
    let item: MacRecordingInboxItem
    let onBack: () -> Void
    var loader = TranscriptMarkdownDocumentLoader()
    var metadataLoader = RecordingDocumentMetadataLoader()

    @State private var loadResult: TranscriptMarkdownLoadResult = .loading
    @State private var isInfoPresented = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                header

                transcriptContent

                Spacer(minLength: 0)
            }
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: loadMarkdown)
        .onChange(of: item.id) {
            loadMarkdown()
        }
    }

    @ViewBuilder
    private var header: some View {
        switch loadResult {
        case .loaded(let markdown):
            let transcriptResult = loader.loadTranscriptResult(item: item)
            let receiveRecord = metadataLoader.loadReceiveRecord(item: item)
            RokuricsDocumentPageHeader(title: item.title, subtitle: "转写文本 / transcript", onBack: onBack) {
                RokuricsInfoButton {
                    isInfoPresented = true
                }
                .popover(isPresented: $isInfoPresented, arrowEdge: .bottom) {
                    RokuricsDocumentInfoPopover(
                        primaryRows: RokuricsDocumentDisplayRows.transcriptInfoRows(
                            item: item,
                            markdown: markdown,
                            transcriptResult: transcriptResult,
                            receiveRecord: receiveRecord
                        ),
                        advancedRows: RokuricsDocumentDisplayRows.transcriptAdvancedRows(
                            item: item,
                            markdown: markdown,
                            transcriptResult: transcriptResult,
                            receiveRecord: receiveRecord
                        )
                    )
                }
            }
        default:
            RokuricsDocumentPageHeader(title: item.title, subtitle: "转写文本 / transcript", onBack: onBack)
        }
    }

    @ViewBuilder
    private var transcriptContent: some View {
        switch loadResult {
        case .loading:
            RokuricsDocumentContentCard {
                Text("正在读取转写文本")
                    .font(RokuricsDetailTypography.metadataValue)
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
            }
        case .loaded(let markdown):
            RokuricsDocumentContentCard(title: "转写正文") {
                RokuricsMarkdownContentView(markdown: RokuricsTranscriptMarkdownCleaner.cleanedBody(from: markdown))
            }
        case .failed(let message):
            RokuricsDocumentContentCard {
                Text(message)
                    .font(RokuricsDetailTypography.metadataValue)
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
            }
        }
    }

    private func loadMarkdown() {
        loadResult = loader.load(item: item)
    }

}

enum TranscriptMarkdownLoadResult: Equatable {
    case loading
    case loaded(String)
    case failed(String)
}

struct TranscriptMarkdownDocumentLoader {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            self.rootURL = MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
        }
    }

    func load(item: MacRecordingInboxItem) -> TranscriptMarkdownLoadResult {
        let paths = candidateMarkdownRelativePaths(for: item)
        guard !paths.isEmpty else {
            return .failed("未找到转写文档")
        }

        for path in paths {
            guard let url = resolvedURL(relativePath: path) else {
                continue
            }

            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            do {
                return .loaded(try String(contentsOf: url, encoding: .utf8))
            } catch {
                return .failed("无法读取转写文档")
            }
        }

        return .failed("未找到转写文档")
    }

    func loadTranscriptResult(item: MacRecordingInboxItem) -> TranscriptionResult? {
        for path in candidateJSONRelativePaths(for: item) {
            guard let url = resolvedURL(relativePath: path),
                  fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else {
                continue
            }
            if let result = try? Self.decoder.decode(TranscriptionResult.self, from: data) {
                return result
            }
        }
        return nil
    }

    private func candidateMarkdownRelativePaths(for item: MacRecordingInboxItem) -> [String] {
        var paths: [String] = []
        if let transcriptMarkdownRelativePath = item.transcriptMarkdownRelativePath,
           !transcriptMarkdownRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paths.append(transcriptMarkdownRelativePath)
        }

        if let transcriptRelativePath = item.transcriptRelativePath,
           !transcriptRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let directory = (transcriptRelativePath as NSString).deletingLastPathComponent
            if !directory.isEmpty {
                paths.append((directory as NSString).appendingPathComponent("transcript.md"))
            }
        }

        return unique(paths)
    }

    private func candidateJSONRelativePaths(for item: MacRecordingInboxItem) -> [String] {
        var paths: [String] = []
        if let transcriptRelativePath = item.transcriptRelativePath,
           !transcriptRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paths.append(transcriptRelativePath)
        }

        if let transcriptMarkdownRelativePath = item.transcriptMarkdownRelativePath,
           !transcriptMarkdownRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let directory = (transcriptMarkdownRelativePath as NSString).deletingLastPathComponent
            if !directory.isEmpty {
                paths.append((directory as NSString).appendingPathComponent("transcript.json"))
            }
        }

        return unique(paths)
    }

    private func unique(_ paths: [String]) -> [String] {
        var uniquePaths: [String] = []
        for path in paths where !uniquePaths.contains(path) {
            uniquePaths.append(path)
        }
        return uniquePaths
    }

    private func resolvedURL(relativePath: String) -> URL? {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("/") else {
            return nil
        }

        let url = rootURL.appendingPathComponent(trimmedPath, isDirectory: false).standardizedFileURL
        return isInsideRoot(url) ? url : nil
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = rootURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
