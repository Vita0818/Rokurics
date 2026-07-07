//
//  RecordingStatusView.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import SwiftUI

struct RecordingStatusView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        RokuricsDashboardCard(title: RokuricsCopy.text("录音状态", "Recording"), systemImage: "waveform") {
            LazyVGrid(columns: columns, spacing: 10) {
                RokuricsMetricTile(title: RokuricsCopy.text("今日录音", "Today"), value: "0", unit: "min", tint: RokuricsColors.aqua)
                RokuricsMetricTile(title: RokuricsCopy.text("当前状态", "Status"), value: RokuricsCopy.text("空闲", "Idle"), tint: RokuricsColors.softTeal)

                HStack {
                    Text(RokuricsCopy.text("本地保存", "Local Save"))
                        .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                        .foregroundStyle(RokuricsColors.softText)

                    Spacer()

                    RokuricsStatusPill(text: RokuricsCopy.text("开启", "On"), systemImage: "lock.fill", tint: RokuricsColors.aqua)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 58)
                .rokuricsLiquidGlassCard(cornerRadius: 20, material: .ultraThinMaterial, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.05, shadowRadius: 8, shadowY: 4)

                HStack {
                    Text(RokuricsCopy.text("云端上传", "Cloud Upload"))
                        .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                        .foregroundStyle(RokuricsColors.softText)

                    Spacer()

                    RokuricsStatusPill(text: RokuricsCopy.text("关闭", "Off"), systemImage: "icloud.slash", tint: RokuricsColors.tertiaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 58)
                .rokuricsLiquidGlassCard(cornerRadius: 20, material: .ultraThinMaterial, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.05, shadowRadius: 8, shadowY: 4)
            }
        }
    }
}

#Preview {
    ZStack {
        RokuricsColors.pageGradient
            .ignoresSafeArea()

        RecordingStatusView()
            .padding(24)
    }
}
