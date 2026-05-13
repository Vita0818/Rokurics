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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RecordingRowContent(
                title: metadata.title,
                dateTimeText: Self.dateFormatter.string(from: metadata.createdAt),
                durationText: compactDurationText(metadata.duration),
                layout: .compact
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
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsLiquidGlassCard(cornerRadius: 18, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.08, shadowRadius: 8, shadowY: 4)
    }

    private var uploadButton: some View {
        Button(action: onUpload) {
            Label(uploadButtonText, systemImage: uploadButtonIcon)
                .font(RokuricsTypography.caption(size: 12, weight: .bold))
                .foregroundStyle(uploadButtonTint)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 92)
                .padding(.vertical, 9)
                .rokuricsGlassCapsule(fillOpacity: isUploadEnabled ? 0.38 : 0.24, strokeOpacity: 0.30, shadowOpacity: 0.03, shadowRadius: 5, shadowY: 2)
        }
        .buttonStyle(RokuricsScaleButtonStyle())
        .disabled(!isUploadEnabled)
    }

    private var isUploadEnabled: Bool {
        isMacPaired && uploadStatus != .uploading && uploadStatus != .uploaded
    }

    private var uploadButtonText: String {
        switch uploadStatus {
        case .uploading:
            return "上传中"
        case .uploaded:
            return "已上传"
        case .failed:
            return "重试"
        default:
            return "上传"
        }
    }

    private var uploadButtonIcon: String {
        switch uploadStatus {
        case .uploading:
            return "arrow.triangle.2.circlepath"
        case .uploaded:
            return "checkmark.circle.fill"
        case .failed:
            return "arrow.clockwise"
        default:
            return "arrow.up.circle"
        }
    }

    private var uploadButtonTint: Color {
        switch uploadStatus {
        case .localOnly:
            return isMacPaired ? RokuricsColors.deepText : RokuricsColors.softText
        case .uploading:
            return RokuricsColors.softTeal
        case .uploaded:
            return RokuricsColors.mint
        case .failed:
            return RokuricsColors.coral
        }
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

private enum RecordingRowLayout {
    case compact
}

private struct RecordingRowContent<Trailing: View>: View {
    let title: String
    let dateTimeText: String
    let durationText: String
    let layout: RecordingRowLayout
    private let trailing: Trailing

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
                .foregroundStyle(RokuricsColors.aqua, .white.opacity(0.88))
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 7) {
                RokuricsMixedFontText(
                    text: title,
                    chineseFont: RokuricsTypography.chineseBody(size: 16, weight: .semibold),
                    englishFont: RokuricsTypography.englishBody(size: 16, weight: .semibold),
                    numberFont: RokuricsTypography.numberBody(size: 16, weight: .semibold)
                )
                .foregroundStyle(RokuricsColors.deepText)
                .lineLimit(1)

                HStack(spacing: 6) {
                    Text(dateTimeText)
                    Text("·")
                    Text(durationText)
                }
                .font(rowMetaFont)
                .foregroundStyle(RokuricsColors.softText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
    }

    private var rowMetaFont: Font {
        switch layout {
        case .compact:
            return RokuricsTypography.numberBody(size: 12, weight: .semibold)
        }
    }
}
