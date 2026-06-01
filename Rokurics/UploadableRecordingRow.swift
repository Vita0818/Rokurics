//
//  UploadableRecordingRow.swift
//  Rokurics
//
//  Created by Codex on 2026/5/12.
//

import SwiftUI

struct UploadableRecordingRow: View {
    let metadata: RecordingMetadata
    let uploadStatus: RecordingUploadStatus
    let isMacPaired: Bool
    let errorMessage: String?
    let onUpload: () -> Void
    var onRenameRequested: () -> Void = {}
    var onMoveToTrashRequested: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecordingRowContent(
                title: metadata.title,
                dateTimeText: Self.dateFormatter.string(from: metadata.createdAt),
                durationText: compactDurationText(metadata.duration),
                onTitleTap: onRenameRequested,
                onIconDoubleTap: handleLeadingIconDoubleTap
            ) {
                uploadButton
            }

            if let errorMessage, uploadStatus == .failed {
                Text(errorMessage)
                    .font(RokuricsTypography.caption(size: 11, weight: .semibold))
                    .foregroundStyle(RokuricsColors.coral)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsLiquidGlassCard(cornerRadius: 18, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.08, shadowRadius: 8, shadowY: 4)
    }

    private var uploadButton: some View {
        let presentation = RecordingUploadCapsulePresentation.resolve(
            status: uploadStatus,
            isMacPaired: isMacPaired
        )

        return Button(action: onUpload) {
            Label(presentation.label, systemImage: presentation.systemImage)
                .font(RokuricsTypography.caption(size: 12, weight: .bold))
                .foregroundStyle(presentation.tint.color)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(width: 88)
                .padding(.vertical, 8)
                .rokuricsGlassCapsule(fillOpacity: presentation.fillOpacity, strokeOpacity: 0.30, shadowOpacity: 0.03, shadowRadius: 5, shadowY: 2)
        }
        .buttonStyle(RokuricsScaleButtonStyle())
        .disabled(!presentation.isEnabled)
    }

    private func handleLeadingIconDoubleTap() {
        guard RecordingRowIconInteraction.intent(for: .doubleTap) == .moveToTrash else {
            return
        }

        onMoveToTrashRequested()
    }

    private func compactDurationText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60

        if minutes == 0 {
            return "\(remainingSeconds)''"
        }

        return "\(minutes)'\(String(format: "%02d", remainingSeconds))''"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

struct RecordingUploadCapsulePresentation: Equatable {
    enum Tint: Equatable {
        case primary
        case muted
        case active
        case success
        case failure

        var color: Color {
            switch self {
            case .primary:
                return RokuricsColors.deepText
            case .muted:
                return RokuricsColors.softText
            case .active:
                return RokuricsColors.softTeal
            case .success:
                return RokuricsColors.mint
            case .failure:
                return RokuricsColors.coral
            }
        }
    }

    let label: String
    let systemImage: String
    let tint: Tint
    let isEnabled: Bool
    let fillOpacity: Double

    static func resolve(status: RecordingUploadStatus, isMacPaired: Bool) -> RecordingUploadCapsulePresentation {
        let isEnabled = isMacPaired && status != .uploading

        switch status {
        case .localOnly:
            return RecordingUploadCapsulePresentation(
                label: "上传",
                systemImage: "arrow.up.circle",
                tint: isMacPaired ? .primary : .muted,
                isEnabled: isEnabled,
                fillOpacity: isEnabled ? 0.38 : 0.24
            )
        case .uploading:
            return RecordingUploadCapsulePresentation(
                label: "上传中",
                systemImage: "arrow.triangle.2.circlepath",
                tint: .active,
                isEnabled: isEnabled,
                fillOpacity: 0.24
            )
        case .uploaded:
            return RecordingUploadCapsulePresentation(
                label: "已上传",
                systemImage: "checkmark.circle.fill",
                tint: .success,
                isEnabled: isEnabled,
                fillOpacity: 0.24
            )
        case .failed:
            return RecordingUploadCapsulePresentation(
                label: "重试",
                systemImage: "arrow.clockwise",
                tint: .failure,
                isEnabled: isEnabled,
                fillOpacity: isEnabled ? 0.38 : 0.24
            )
        }
    }
}

struct RecordingUploadActionAreaPresentation {
    static func resolve(
        metadata: RecordingMetadata?,
        status: RecordingUploadStatus,
        isMacPaired _: Bool
    ) -> StudyRecordingActionAreaPresentation? {
        guard let metadata else {
            return nil
        }

        let displayState = displayState(metadata: metadata, status: status)
        if case .failed(let reason) = displayState, reason == "local_audio_missing" {
            return .statusWithActions("本地音频缺失")
        }

        switch displayState {
        case .waiting:
            return .statusWithActions("等待上传")
        case .retryPending:
            return .statusWithActions("等待自动重试")
        case .manualRetryAvailable:
            return .statusWithActions("可手动重试")
        case .preparing:
            return .progressOnly(preparingProgress(for: metadata))
        case .uploading:
            guard let progress = StudyItemMetadata.recordingUploadTransferProgress(for: metadata, status: .uploading),
                  progress.isVisibleInActionArea else {
                return .progressOnly(preparingProgress(for: metadata))
            }
            return .progressOnly(progress)
        case .finalizing:
            return .progressOnly(preparingProgress(for: metadata))
        case .hidden, .uploaded:
            return nil
        case .conflict:
            return .statusWithActions("上传冲突")
        case .fatalFailed:
            return .statusWithActions("上传失败")
        case .failed:
            return .statusWithActions("上传失败")
        }
    }

    static func displayState(
        metadata: RecordingMetadata?,
        status: RecordingUploadStatus
    ) -> RecordingUploadDisplayState {
        guard let metadata else {
            return .hidden
        }
        if hasMissingLocalAudio(metadata) {
            return .failed("local_audio_missing")
        }

        switch status {
        case .localOnly:
            return .waiting
        case .uploading:
            let phase = metadata.uploadPhase?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if phase.contains("conflict") {
                return .conflict(metadata.uploadProgressDescription)
            }
            if phase.contains("fatal") {
                return .fatalFailed(metadata.uploadProgressDescription)
            }
            if phase.contains("retry") {
                return .retryPending
            }
            if phase.contains("finalizing") || phase.contains("completed") {
                return .finalizing
            }
            if phase.contains("preparing") || phase.contains("starting") || phase.contains("metadata") {
                return .preparing
            }
            return .uploading(progressFraction: metadata.uploadProgressFraction)
        case .uploaded:
            return .hidden
        case .failed:
            let phase = metadata.uploadPhase?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if phase.contains("conflict") {
                return .conflict(metadata.uploadProgressDescription)
            }
            if phase.contains("fatal") {
                return .fatalFailed(metadata.uploadProgressDescription)
            }
            if phase.contains("retry") {
                return .retryPending
            }
            return .failed(nil)
        }
    }

    private static func hasMissingLocalAudio(_ metadata: RecordingMetadata) -> Bool {
        metadata.relativeAudioPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || metadata.fileSize <= 0
    }

    private static func preparingProgress(for metadata: RecordingMetadata) -> LocalNetworkTransferProgress {
        LocalNetworkTransferProgress(
            objectID: "recordingAudio:\(metadata.id)",
            objectKind: LocalNetworkSyncObjectKind.recordingAudio.rawValue,
            state: .pending,
            progressFraction: 0,
            receivedBytes: metadata.uploadProgressConfirmedBytes,
            totalBytes: metadata.uploadProgressTotalBytes ?? (metadata.fileSize > 0 ? metadata.fileSize : nil),
            sourceDeviceID: nil,
            statusText: "准备上传"
        )
    }
}

enum RecordingRowIconTapTrigger: Equatable {
    case singleTap
    case doubleTap
}

enum RecordingRowIconTapIntent: Equatable {
    case none
    case moveToTrash
}

struct RecordingRowIconInteraction: Equatable {
    static let deletionTapCount = 2

    static func intent(for trigger: RecordingRowIconTapTrigger) -> RecordingRowIconTapIntent {
        switch trigger {
        case .singleTap:
            return .none
        case .doubleTap:
            return .moveToTrash
        }
    }
}

private struct RecordingRowContent<Trailing: View>: View {
    let title: String
    let dateTimeText: String
    let durationText: String
    let onTitleTap: () -> Void
    let onIconDoubleTap: () -> Void
    private let trailing: Trailing

    init(
        title: String,
        dateTimeText: String,
        durationText: String,
        onTitleTap: @escaping () -> Void = {},
        onIconDoubleTap: @escaping () -> Void = {},
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.dateTimeText = dateTimeText
        self.durationText = durationText
        self.onTitleTap = onTitleTap
        self.onIconDoubleTap = onIconDoubleTap
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RecordingLeadingIcon()
                .contentShape(Circle())
                .onTapGesture(count: RecordingRowIconInteraction.deletionTapCount, perform: onIconDoubleTap)
                .accessibilityLabel("录音图标，双击移入废纸篓")
                .accessibilityAction(named: Text("移入废纸篓"), onIconDoubleTap)

            VStack(alignment: .leading, spacing: 9) {
                Button(action: onTitleTap) {
                    RokuricsMixedFontText(
                        text: title,
                        chineseFont: RokuricsTypography.chineseBody(size: 16, weight: .semibold),
                        englishFont: RokuricsTypography.englishBody(size: 16, weight: .semibold),
                        numberFont: RokuricsTypography.numberBody(size: 16, weight: .semibold)
                    )
                    .foregroundStyle(RokuricsColors.deepText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(dateTimeText)
                        Text("·")
                        Text(durationText)
                    }
                    .font(rowMetaFont)
                    .foregroundStyle(RokuricsColors.softText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                    Spacer(minLength: 8)

                    trailing
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rowMetaFont: Font {
        RokuricsTypography.numberBody(size: 12, weight: .semibold)
    }
}

private struct RecordingLeadingIcon: View {
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 21, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(RokuricsColors.aqua)
            .frame(width: 50, height: 50)
            .rokuricsGlassCircle(fillOpacity: 0.34, strokeOpacity: 0.38, shadowOpacity: 0.08, shadowRadius: 9, shadowY: 4)
    }
}
