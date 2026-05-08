//
//  DeviceConnectionCard.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import SwiftUI

struct DeviceConnectionCard: View {
    var body: some View {
        RokuricsDashboardCard(title: "Mac 连接", systemImage: "desktopcomputer") {
            HStack(alignment: .center, spacing: 15) {
                ZStack {
                    Circle()
                        .fill(RokuricsColors.quietGradient)
                        .frame(width: 58, height: 58)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.44), lineWidth: 1)
                        }

                    Image(systemName: "network")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(RokuricsColors.softTeal)
                }
                .rokuricsSoftShadow(opacity: 0.08, radius: 12, y: 7)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Mac 未连接")
                        .font(RokuricsTypography.headline(size: 18))
                        .foregroundStyle(RokuricsColors.deepText)

                    Text("本地传输待配置")
                        .font(RokuricsTypography.body(size: 14, weight: .medium))
                        .foregroundStyle(RokuricsColors.softText)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("8787")
                        .font(RokuricsTypography.largeNumber(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(RokuricsColors.softTeal)

                    Text("端口")
                        .font(RokuricsTypography.caption(size: 11, weight: .semibold))
                        .foregroundStyle(RokuricsColors.tertiaryText)
                }
            }

            HStack {
                RokuricsStatusPill(text: "局域网 HTTP", systemImage: "wifi", tint: RokuricsColors.softTeal)
                Spacer()
                RokuricsStatusPill(text: "Mock", systemImage: "sparkle.magnifyingglass", tint: RokuricsColors.tertiaryText)
            }
        }
    }
}

#Preview {
    ZStack {
        RokuricsColors.pageGradient
            .ignoresSafeArea()

        DeviceConnectionCard()
            .padding(24)
    }
}
