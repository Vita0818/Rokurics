//
//  RokuricsCardStyle.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import SwiftUI

struct RokuricsDashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RokuricsColors.aqua)
                    .frame(width: 30, height: 30)
                    .rokuricsGlassCircle(fillOpacity: 0.34, strokeOpacity: 0.34, shadowOpacity: 0.05, shadowRadius: 7, shadowY: 4)

                Text(title)
                    .font(RokuricsTypography.headline(size: 18))
                    .foregroundStyle(RokuricsColors.deepText)

                Spacer()
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsLiquidGlassCard(cornerRadius: 28, material: .thinMaterial, fillOpacity: 0.43, strokeOpacity: 0.42, shadowOpacity: 0.11, shadowRadius: 18, shadowY: 10)
    }
}

struct RokuricsMetricTile: View {
    let title: String
    let value: String
    var unit: String?
    var tint: Color = RokuricsColors.aqua

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                .foregroundStyle(RokuricsColors.softText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(RokuricsTypography.largeNumber(size: 26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let unit {
                    Text(unit)
                        .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                        .foregroundStyle(RokuricsColors.tertiaryText)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsLiquidGlassCard(cornerRadius: 20, material: .ultraThinMaterial, fillOpacity: 0.35, strokeOpacity: 0.30, shadowOpacity: 0.05, shadowRadius: 8, shadowY: 4)
    }
}

struct RokuricsStatusPill: View {
    let text: String
    var systemImage: String?
    var tint: Color = RokuricsColors.aqua

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            }

            Text(text)
                .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .rokuricsGlassCapsule(fillOpacity: 0.36, strokeOpacity: 0.34, shadowOpacity: 0.04, shadowRadius: 7, shadowY: 3)
    }
}
