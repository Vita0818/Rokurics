//
//  MacHomeView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/7/7.
//

import SwiftUI

struct MacHomeView: View {
    @ObservedObject var recordingManager: MacRecordingManager
    let onOpenStudyLibrary: () -> Void
    let onOpenAIChat: () -> Void
    let onOpenIPhoneConnection: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isRecordingSessionPresented = false

    var body: some View {
        ZStack {
            if isRecordingSessionPresented {
                MacRecordingSessionView(recordingManager: recordingManager) {
                    isRecordingSessionPresented = false
                }
            } else {
                homeContent
            }
        }
    }

    private var homeContent: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            MacDetailContentContainer(maxWidth: 1120, topPadding: 34) {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    recordingHub
                        .frame(maxWidth: .infinity)

                    MacHomeNavigationCard(
                        onOpenStudyLibrary: onOpenStudyLibrary,
                        onOpenAIChat: onOpenAIChat,
                        onOpenIPhoneConnection: onOpenIPhoneConnection
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Text("Rokurics")
                .font(MacTypography.brandTitle(size: 44))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
            
            Spacer(minLength: 16)
        }
    }

    private var recordingHub: some View {
        VStack(spacing: 12) {
            RokuricsSharedRecordingOrb(
                visualScale: 1.05,
                phase: recordingManager.phase,
                elapsedSeconds: recordingManager.elapsedSeconds,
                action: openRecordingSession
            )
            
            if let lastErrorMessage = recordingManager.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(MacTypography.technical(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.coral)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func openRecordingSession() {
        isRecordingSessionPresented = true
    }
}

private struct MacHomeNavigationCard: View {
    let onOpenStudyLibrary: () -> Void
    let onOpenAIChat: () -> Void
    let onOpenIPhoneConnection: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            MacHomeNavigationButton(
                title: RokuricsCopy.text("学习库", "Library"),
                systemImage: "books.vertical",
                tint: MacTheme.aqua,
                action: onOpenStudyLibrary
            )

            MacHomeNavigationDivider()

            MacHomeNavigationButton(
                title: RokuricsCopy.text("AI 对话", "AI Chat"),
                systemImage: "bubble.left.and.bubble.right",
                tint: MacTheme.mint,
                action: onOpenAIChat
            )

            MacHomeNavigationDivider()

            MacHomeNavigationButton(
                title: RokuricsCopy.text("iPhone 连接", "iPhone Link"),
                systemImage: "iphone",
                tint: MacTheme.leaf,
                action: onOpenIPhoneConnection
            )
        }
        .frame(maxWidth: .infinity, minHeight: 116)
        .macLiquidGlassCard(cornerRadius: 26, material: .thinMaterial, fillOpacity: 0.36, strokeOpacity: 0.40, shadowOpacity: 0.08, shadowRadius: 18, shadowY: 10)
    }
}

private struct MacHomeNavigationButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(height: 34)

                MacMixedFontText(
                    text: title,
                    chineseFont: MacTypography.chineseBody(size: 15, weight: .semibold),
                    englishFont: MacTypography.englishBody(size: 15, weight: .semibold),
                    numberFont: MacTypography.numberBody(size: 15, weight: .semibold)
                )
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 104)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(tint.opacity(isHovering ? 0.10 : 0))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct MacHomeNavigationDivider: View {
    var body: some View {
        Rectangle()
            .fill(MacTheme.aqua.opacity(0.14))
            .frame(width: 1, height: 62)
    }
}

#Preview {
    MacHomeView(
        recordingManager: MacRecordingManager(),
        onOpenStudyLibrary: {},
        onOpenAIChat: {},
        onOpenIPhoneConnection: {}
    )
}
