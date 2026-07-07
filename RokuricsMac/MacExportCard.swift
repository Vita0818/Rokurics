//
//  MacExportCard.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

struct MacExportCard: View {
    @ObservedObject var exportManager: ExportManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MacDashboardCard(systemImage: "square.and.arrow.up", tint: MacTheme.coral) {
            Text(RokuricsCopy.text("导出", "Export"))
                .font(RokuricsCopy.usesChinese ? MacTypography.chineseHeadline(size: 17) : MacTypography.englishHeadline(size: 17))
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Text(exportManager.primaryFormat)
                    .font(MacTypography.englishTitle(size: 34))
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("Kikaria / Anki")
                        .font(MacTypography.englishBody(size: 14, weight: .medium))

                    Text(RokuricsCopy.text("稍后支持", "Coming Soon"))
                        .font(RokuricsCopy.usesChinese ? MacTypography.chineseBody(size: 14, weight: .medium) : MacTypography.englishBody(size: 14, weight: .medium))
                }
                    .foregroundStyle(MacTheme.softText(for: colorScheme))

                HStack(spacing: 8) {
                    ForEach(exportManager.supportedFormats, id: \.self) { format in
                        Text(format)
                            .font(MacTypography.englishCaption(size: 11, weight: .semibold))
                            .foregroundStyle(MacTheme.softText(for: colorScheme))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .macGlassCapsule(fillOpacity: 0.32, strokeOpacity: 0.28)
                    }
                }
            }
        }
    }
}
