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
        RokuricsDashboardCard(title: "录音状态", systemImage: "waveform") {
            LazyVGrid(columns: columns, spacing: 10) {
                RokuricsMetricTile(title: "今日录音", value: "0", unit: "min", tint: RokuricsColors.aqua)
                RokuricsMetricTile(title: "当前状态", value: "空闲", tint: RokuricsColors.softTeal)

                HStack {
                    Text("本地保存")
                        .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                        .foregroundStyle(RokuricsColors.softText)

                    Spacer()

                    RokuricsStatusPill(text: "开启", systemImage: "lock.fill", tint: RokuricsColors.aqua)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 58)
                .rokuricsLiquidGlassCard(cornerRadius: 20, material: .ultraThinMaterial, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.05, shadowRadius: 8, shadowY: 4)

                HStack {
                    Text("云端上传")
                        .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                        .foregroundStyle(RokuricsColors.softText)

                    Spacer()

                    RokuricsStatusPill(text: "关闭", systemImage: "icloud.slash", tint: RokuricsColors.tertiaryText)
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
