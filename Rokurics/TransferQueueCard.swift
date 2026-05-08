//
//  TransferQueueCard.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import SwiftUI

struct TransferQueueCard: View {
    var body: some View {
        RokuricsDashboardCard(title: "本地传输队列", systemImage: "arrow.triangle.2.circlepath") {
            HStack(spacing: 10) {
                RokuricsMetricTile(title: "待传输", value: "0", tint: RokuricsColors.aqua)
                RokuricsMetricTile(title: "已完成", value: "0", tint: RokuricsColors.mint)
            }

            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RokuricsColors.softTeal)

                Text("最近同步")
                    .font(RokuricsTypography.body(size: 14, weight: .medium))
                    .foregroundStyle(RokuricsColors.softText)

                Spacer()

                Text("暂无")
                    .font(RokuricsTypography.body(size: 14, weight: .semibold))
                    .foregroundStyle(RokuricsColors.deepText.opacity(0.78))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46)
            .rokuricsGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.04, shadowRadius: 7, shadowY: 3)
        }
    }
}

#Preview {
    ZStack {
        RokuricsColors.pageGradient
            .ignoresSafeArea()

        TransferQueueCard()
            .padding(24)
    }
}
