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
                                    }
                                )
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
    }

    private var header: some View {
        HStack {
            RokuricsIconCircleButton(
                systemName: "chevron.left",
                accessibilityLabel: "返回首页",
                size: 44,
                action: { dismiss() }
            )

            Spacer()

            Text("历史录音")
                .font(RokuricsTypography.headline(size: 21, weight: .semibold))
                .foregroundStyle(RokuricsColors.deepText)

            Spacer()

            Text("\(recordingManager.recordings.count)")
                .font(RokuricsTypography.largeNumber(size: 24, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(RokuricsColors.aqua)
                .frame(width: 44, height: 44)
                .rokuricsGlassCircle(fillOpacity: 0.32, strokeOpacity: 0.36, shadowOpacity: 0.08, shadowRadius: 8, shadowY: 4)
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
}

#Preview {
    NavigationStack {
        RecordingLibraryView(
            recordingManager: RecordingManager(),
            macConnectionStore: SecureMacConnectionStore()
        )
    }
}
