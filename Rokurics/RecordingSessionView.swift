//
//  RecordingSessionView.swift
//  Rokurics
//
//  Created by Codex on 2026/5/9.
//

import SwiftUI

struct RecordingSessionView: View {
    @ObservedObject var recordingManager: RecordingManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var didRequestStart = false
    @State private var filingType = ""
    @State private var filingSubject = ""
    @State private var filingChapter = ""
    @State private var filingTopic = ""
    @State private var isLowPowerDisplayMode = false
    @State private var lowPowerMinuteText = "00"
    @State private var lowPowerEntryTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if isLowPowerDisplayMode {
                Color.black
                    .ignoresSafeArea()

                Text(lowPowerMinuteText)
                    .font(RokuricsTypography.largeNumber(size: 104, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        exitLowPowerDisplayModeAfterInteraction()
                    }
            } else {
                normalRecordingContent
            }

            if !isLowPowerDisplayMode && isFilingOverlayPresented {
                RecordingFilingOverlay(
                    type: $filingType,
                    subject: $filingSubject,
                    chapter: $filingChapter,
                    topic: $filingTopic,
                    items: recordingManager.studyLibraryStore.effectiveStudyItems,
                    folders: recordingManager.studyLibraryStore.effectiveStudyFolders,
                    saveAction: saveFilingAndDismiss,
                    directSaveAction: directSaveAndDismiss
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(10)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .simultaneousGesture(
            TapGesture().onEnded {
                recordUserInteraction()
            }
        )
        .onAppear {
            startIfNeeded()
            scheduleLowPowerEntryIfNeeded()
        }
        .onChange(of: recordingManager.state) { _, newState in
            if newState == .filing {
                resetFilingDraft()
            }

            handleRecordingStateChange(newState)
        }
        .onChange(of: recordingManager.elapsedSeconds) { _, elapsedSeconds in
            updateLowPowerMinuteText(elapsedSeconds: elapsedSeconds)
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onDisappear {
            cancelLowPowerEntry()
            setLowPowerDisplayMode(false)

            if recordingManager.state == .filing {
                recordingManager.finalizeRecordingDirectSave()
            }
        }
    }

    private var normalRecordingContent: some View {
        RokuricsSharedRecordingSessionSurface(
            elapsedSeconds: recordingManager.elapsedSeconds,
            isPaused: recordingManager.state.isPaused,
            errorMessage: recordingManager.state == .failed ? recordingManager.lastErrorMessage : nil,
            transcriptText: transcriptDisplayText,
            pauseButtonTitle: pauseButtonTitle,
            pauseButtonSystemImage: pauseButtonImageName,
            canPauseOrResume: canPauseOrResume,
            canStop: canStop,
            backAction: dismissToHome,
            pauseResumeAction: togglePause,
            stopAction: stopAndDismiss
        )
    }

    private var transcriptDisplayText: String {
        recordingManager.liveTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFilingOverlayPresented: Bool {
        recordingManager.state == .filing
    }

    private var pauseButtonTitle: String {
        recordingManager.state == .paused ? RokuricsCopy.text("继续", "Resume") : RokuricsCopy.text("暂停", "Pause")
    }

    private var pauseButtonImageName: String {
        recordingManager.state == .paused ? "play.fill" : "pause.fill"
    }

    private var canPauseOrResume: Bool {
        recordingManager.state == .recording || recordingManager.state == .paused
    }

    private var canStop: Bool {
        recordingManager.state == .recording || recordingManager.state == .paused
    }

    private var canEnterLowPowerDisplayMode: Bool {
        RecordingLowPowerDisplayPolicy.canEnter(
            state: recordingManager.state,
            isAppActive: scenePhase == .active,
            isFilingOverlayPresented: isFilingOverlayPresented,
            hasBlockingPresentation: recordingManager.state == .failed || recordingManager.state == .permissionDenied
        )
    }

    private func startIfNeeded() {
        guard !didRequestStart else {
            return
        }

        didRequestStart = true

        switch recordingManager.state {
        case .recording, .paused, .requestingPermission, .configuringSession, .stopping, .filing, .saving:
            return
        case .idle, .saved, .permissionDenied, .failed:
            recordingManager.startRecording()
        }
    }

    private func togglePause() {
        recordUserInteraction()

        switch recordingManager.state {
        case .recording:
            setLowPowerDisplayMode(false)
            recordingManager.pauseRecording()
        case .paused:
            recordingManager.resumeRecording()
        default:
            break
        }
    }

    private func stopAndDismiss() {
        recordUserInteraction()
        setLowPowerDisplayMode(false)
        recordingManager.stopRecording()

        if recordingManager.state == .saved {
            dismiss()
        }
    }

    private func dismissToHome() {
        recordUserInteraction()
        setLowPowerDisplayMode(false)

        if recordingManager.state == .filing {
            directSaveAndDismiss()
            return
        }

        dismiss()
    }

    private func saveFilingAndDismiss() {
        setLowPowerDisplayMode(false)
        recordingManager.finalizeRecording(studyFiling: currentFilingDraft, directSave: false)

        if recordingManager.state == .saved {
            dismiss()
        }
    }

    private func directSaveAndDismiss() {
        setLowPowerDisplayMode(false)
        recordingManager.finalizeRecordingDirectSave()

        if recordingManager.state == .saved {
            dismiss()
        }
    }

    private var currentFilingDraft: StudyFilingPath {
        StudyFilingPath(
            type: filingType,
            subject: filingSubject,
            chapter: filingChapter,
            topic: filingTopic
        )
    }

    private func resetFilingDraft() {
        filingType = ""
        filingSubject = ""
        filingChapter = ""
        filingTopic = ""
    }

    private func recordUserInteraction() {
        guard !isFilingOverlayPresented else {
            cancelLowPowerEntry()
            return
        }

        if isLowPowerDisplayMode {
            exitLowPowerDisplayModeAfterInteraction()
        } else {
            scheduleLowPowerEntryIfNeeded()
        }
    }

    private func handleRecordingStateChange(_ state: RokuricsRecordingState) {
        if state == .recording {
            scheduleLowPowerEntryIfNeeded()
            return
        }

        cancelLowPowerEntry()
        setLowPowerDisplayMode(false)
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else {
            cancelLowPowerEntry()
            setLowPowerDisplayMode(false)
            return
        }

        recordingManager.refreshElapsedNow()
        scheduleLowPowerEntryIfNeeded()
    }

    private func scheduleLowPowerEntryIfNeeded() {
        lowPowerEntryTask?.cancel()

        guard !isLowPowerDisplayMode, canEnterLowPowerDisplayMode else {
            return
        }

        lowPowerEntryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: RecordingLowPowerDisplayPolicy.inactivityDelayNanoseconds)
            guard !Task.isCancelled, canEnterLowPowerDisplayMode else {
                return
            }

            enterLowPowerDisplayMode()
        }
    }

    private func cancelLowPowerEntry() {
        lowPowerEntryTask?.cancel()
        lowPowerEntryTask = nil
    }

    private func enterLowPowerDisplayMode() {
        guard canEnterLowPowerDisplayMode else {
            return
        }

        lowPowerMinuteText = RecordingLowPowerDisplayPolicy.minuteText(elapsedSeconds: recordingManager.elapsedSeconds)
        setLowPowerDisplayMode(true)
    }

    private func exitLowPowerDisplayModeAfterInteraction() {
        setLowPowerDisplayMode(false)
        recordingManager.refreshElapsedNow()
        scheduleLowPowerEntryIfNeeded()
    }

    private func setLowPowerDisplayMode(_ isEnabled: Bool) {
        guard isLowPowerDisplayMode != isEnabled else {
            return
        }

        isLowPowerDisplayMode = isEnabled
        recordingManager.setLowPowerElapsedRefreshEnabled(isEnabled)

        if isEnabled {
            lowPowerEntryTask?.cancel()
            lowPowerEntryTask = nil
        }
    }

    private func updateLowPowerMinuteText(elapsedSeconds: TimeInterval) {
        guard isLowPowerDisplayMode else {
            return
        }

        let updatedText = RecordingLowPowerDisplayPolicy.minuteText(elapsedSeconds: elapsedSeconds)
        if lowPowerMinuteText != updatedText {
            lowPowerMinuteText = updatedText
        }
    }
}

private struct RecordingFilingOverlay: View {
    @Binding var type: String
    @Binding var subject: String
    @Binding var chapter: String
    @Binding var topic: String
    let items: [StudyItemMetadata]
    let folders: [StudyFolderMetadata]
    let saveAction: () -> Void
    let directSaveAction: () -> Void
    @State private var activeLevel: StudyFolderLevel?
    @State private var newValueDraft = ""
    @FocusState private var isNewValueFocused: Bool

    private let levels: [StudyFolderLevel] = [.type, .subject, .chapter, .topic]

    var body: some View {
        ZStack {
            Color.white.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(RokuricsCopy.text("录音归档", "File Recording"))
                        .font(RokuricsTypography.font(for: .pageTitle))
                        .foregroundStyle(RokuricsColors.deepText)

                    Text(RokuricsCopy.text("选择 \(selectionLevel.title)", "Choose \(selectionLevel.title)"))
                        .font(RokuricsTypography.font(for: .pageSubtitle))
                        .foregroundStyle(RokuricsColors.softText)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        ForEach(levels) { level in
                            RecordingFilingLevelButton(
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
                            }
                        }
                    }

                    if currentCandidates.isEmpty {
                        Text(RokuricsCopy.text("暂无已有\(selectionLevel.title)，可以新建。", "No existing \(selectionLevel.title). Create one."))
                            .font(RokuricsTypography.font(for: .secondary))
                            .foregroundStyle(RokuricsColors.softText)
                            .padding(.vertical, 4)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(currentCandidates, id: \.self) { candidate in
                                RecordingFilingValueButton(
                                    title: candidate,
                                    isSelected: draft.value(for: selectionLevel) == candidate
                                ) {
                                    select(candidate, for: selectionLevel)
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(RokuricsCopy.newLabel(selectionLevel.title), text: $newValueDraft)
                            .font(RokuricsTypography.font(for: .body))
                            .foregroundStyle(RokuricsColors.deepText)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .focused($isNewValueFocused)
                            .onSubmit(createCurrentValue)

                        RokuricsIconCircleButton(
                            systemName: "plus",
                            accessibilityLabel: RokuricsCopy.newLabel(selectionLevel.title),
                            size: 36,
                            tint: RokuricsColors.aqua,
                            isEnabled: !newValueDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            action: createCurrentValue
                        )
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(RokuricsColors.glassSurface.opacity(0.52))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(RokuricsColors.glassStroke.opacity(0.42), lineWidth: 1)
                            }
                    )
                }

                HStack(spacing: 12) {
                    Button(action: directSaveAction) {
                        Text(RokuricsCopy.text("直接保存", "Save Directly"))
                            .font(RokuricsTypography.button(size: 15))
                            .foregroundStyle(RokuricsColors.softText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(RokuricsScaleButtonStyle())
                    .rokuricsGlassCapsule(fillOpacity: 0.30, strokeOpacity: 0.32, shadowOpacity: 0.04)

                    Button(action: saveAction) {
                        Text(RokuricsCopy.text("保存", "Save"))
                            .font(RokuricsTypography.button(size: 15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(RokuricsScaleButtonStyle())
                    .disabled(!hasAnyFiling)
                    .background(hasAnyFiling ? RokuricsColors.actionGradient : LinearGradient(colors: [RokuricsColors.tertiaryText.opacity(0.34)], startPoint: .leading, endPoint: .trailing), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.38), lineWidth: 1)
                    }
                    .opacity(hasAnyFiling ? 1 : 0.62)
                    .shadow(color: RokuricsColors.shadow.opacity(hasAnyFiling ? 0.16 : 0.04), radius: 14, y: 8)
                }
            }
            .padding(22)
            .frame(maxWidth: 360)
            .rokuricsLiquidGlassCard(cornerRadius: 30, fillOpacity: 0.52, strokeOpacity: 0.50, shadowOpacity: 0.16, shadowRadius: 26, shadowY: 14)
            .padding(.horizontal, 24)
        }
    }

    private var hasAnyFiling: Bool {
        !StudyFilingPath(type: type, subject: subject, chapter: chapter, topic: topic).isEmpty
    }

    private var draft: StudyFilingSelectionDraft {
        StudyFilingSelectionDraft(path: StudyFilingPath(type: type, subject: subject, chapter: chapter, topic: topic))
    }

    private var selectionLevel: StudyFolderLevel {
        if let activeLevel, canActivate(activeLevel) {
            return activeLevel
        }

        return levels.first { draft.value(for: $0).isEmpty } ?? .topic
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
        activeLevel = StudyFilingSelectionFlow.nextLevelAfterCommit(level)
        newValueDraft = ""
    }

    private func createCurrentValue() {
        let trimmedName = newValueDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        select(trimmedName, for: selectionLevel)
    }

    private func apply(_ updated: StudyFilingSelectionDraft) {
        type = updated.type
        subject = updated.subject
        chapter = updated.chapter
        topic = updated.topic
    }
}

private struct RecordingFilingLevelButton: View {
    let level: StudyFolderLevel
    let value: String
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(level.title)
                    .font(RokuricsTypography.secondary(size: 10, weight: .bold))
                    .foregroundStyle(RokuricsColors.tertiaryText)

                Text(value.isEmpty ? RokuricsCopy.text("未选择", "Not set") : value)
                    .font(RokuricsTypography.secondary(size: 12, weight: .bold))
                    .foregroundStyle(isEnabled ? RokuricsColors.deepText : RokuricsColors.tertiaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(minWidth: 72, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(RokuricsColors.glassSurface.opacity(isActive ? 0.58 : 0.34))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isActive ? RokuricsColors.aqua.opacity(0.46) : RokuricsColors.glassStroke.opacity(0.24), lineWidth: 1)
            }
        }
        .buttonStyle(RokuricsScaleButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.46)
    }
}

private struct RecordingFilingValueButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(RokuricsTypography.secondary(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? .white : RokuricsColors.deepText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? RokuricsColors.aqua : RokuricsColors.glassSurface.opacity(0.34))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? RokuricsColors.aqua.opacity(0.34) : RokuricsColors.glassStroke.opacity(0.22), lineWidth: 1)
                }
        }
        .buttonStyle(RokuricsScaleButtonStyle())
    }
}

private struct RecordingFilingField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let candidates: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(RokuricsTypography.caption(size: 12, weight: .bold))
                .foregroundStyle(RokuricsColors.softText)

            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .font(RokuricsTypography.body(size: 15, weight: .semibold))
                    .foregroundStyle(RokuricsColors.deepText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)

                Menu {
                    if candidates.isEmpty {
                        Text(RokuricsCopy.text("暂无已有值", "No existing values"))
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
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(RokuricsCopy.chooseLabel(title))
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RokuricsColors.glassSurface.opacity(0.52))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(RokuricsColors.glassStroke.opacity(0.42), lineWidth: 1)
                    }
            )
        }
    }
}

enum RecordingLowPowerDisplayPolicy {
    static let inactivityDelayNanoseconds: UInt64 = 5_000_000_000

    static func canEnter(
        state: RokuricsRecordingState,
        isAppActive: Bool,
        isFilingOverlayPresented: Bool,
        hasBlockingPresentation: Bool
    ) -> Bool {
        state == .recording && isAppActive && !isFilingOverlayPresented && !hasBlockingPresentation
    }

    static func minuteText(elapsedSeconds: TimeInterval) -> String {
        let clockText = RokuricsRecordingFormat.clock(elapsedSeconds)
        guard let separatorIndex = clockText.firstIndex(of: ":") else {
            return clockText
        }

        return String(clockText[..<separatorIndex])
    }
}

#Preview {
    NavigationStack {
        RecordingSessionView(recordingManager: RecordingManager())
    }
}
