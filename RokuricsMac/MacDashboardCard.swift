//
//  MacDashboardCard.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

struct MacDashboardCard<Title: View, Content: View>: View {
    let systemImage: String
    var tint: Color = MacTheme.aqua
    let title: Title
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        systemImage: String,
        tint: Color = MacTheme.aqua,
        @ViewBuilder title: () -> Title,
        @ViewBuilder content: () -> Content
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                title
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))
                    .lineLimit(1)

                Spacer(minLength: 8)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 264, maxHeight: 264, alignment: .topLeading)
        .macLiquidGlassCard(cornerRadius: 26, material: .thinMaterial, fillOpacity: 0.46, strokeOpacity: 0.44, shadowOpacity: 0.10, shadowRadius: 17, shadowY: 9)
    }
}

struct MacStatusPill: View {
    let text: String
    var systemImage: String?
    var tint: Color = MacTheme.aqua

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            }

            Text(text)
                .font(MacTypography.pillFont(for: text, size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .macGlassCapsule(fillOpacity: 0.38, strokeOpacity: 0.34)
    }
}
