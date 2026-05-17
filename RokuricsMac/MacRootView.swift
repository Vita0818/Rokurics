//
//  MacRootView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

struct MacRootView: View {
    @State private var selection: MacSidebarItem? = .dashboard
    @State private var isSettingsSelected = false
    @StateObject private var secureReceiverService = SecureReceiverService()
    @StateObject private var audioInboxStore = AudioInboxStore()
    @StateObject private var transcriptionQueue = TranscriptionQueue()
    @StateObject private var transcriptionCoordinator = TranscriptionCoordinator()
    @StateObject private var noteGenerationCoordinator = NoteGenerationCoordinator()
    @StateObject private var transcriptionSettingsStore = TranscriptionSettingsStore.shared
    @StateObject private var noteGenerationSettingsStore = NoteGenerationSettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationSplitView {
            MacSidebarView(selection: $selection, isSettingsSelected: $isSettingsSelected)
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 280)
        } detail: {
            if isSettingsSelected {
                MacSettingsView(
                    secureReceiverService: secureReceiverService,
                    audioInboxStore: audioInboxStore,
                    transcriptionQueue: transcriptionQueue,
                    transcriptionSettingsStore: transcriptionSettingsStore,
                    noteGenerationSettingsStore: noteGenerationSettingsStore
                )
            } else {
                detailView(for: selection ?? .dashboard)
            }
        }
        .navigationTitle("")
        .toolbar(removing: .title)
        .background(MacTheme.pageGradient(for: colorScheme))
        .frame(minWidth: 1040, minHeight: 690)
    }

    @ViewBuilder
    private func detailView(for item: MacSidebarItem) -> some View {
        switch item {
        case .dashboard:
            MacDashboardView(
                secureReceiverService: secureReceiverService,
                audioInboxStore: audioInboxStore,
                noteGenerationSettingsStore: noteGenerationSettingsStore,
                onOpenIPhoneConnection: {
                    isSettingsSelected = false
                    selection = .iPhoneConnection
                }
            )
        case .iPhoneConnection:
            MacIPhoneConnectionView(secureReceiverService: secureReceiverService)
        case .audioInbox:
            MacAudioInboxView(
                audioInboxStore: audioInboxStore,
                transcriptionCoordinator: transcriptionCoordinator,
                noteGenerationCoordinator: noteGenerationCoordinator
            )
        case .notes:
            MacPlaceholderWorkspace(
                title: "Notes",
                systemImage: "doc.text",
                status: "Markdown",
                caption: "课堂笔记与知识点卡片稍后支持",
                details: ["Kikaria preset: planned", "Review cards: planned"]
            )
        }
    }
}

private struct MacPlaceholderWorkspace: View {
    let title: String
    let systemImage: String
    let status: String
    let caption: String
    let details: [String]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            MacDetailContentContainer(maxWidth: 940) {
                VStack(alignment: .leading, spacing: 26) {
                    MacPageHeader(
                        systemImage: systemImage,
                        title: .english(title),
                        subtitle: caption
                    )

                    VStack(alignment: .leading, spacing: 18) {
                        Text(status)
                            .font(MacTypography.statusDisplay(for: status, size: 44))
                            .foregroundStyle(MacTheme.aqua)

                        HStack(spacing: 10) {
                            ForEach(details, id: \.self) { detail in
                                MacDetailPillText(text: detail)
                            }
                        }
                    }
                    .padding(26)
                    .frame(maxWidth: 560, alignment: .leading)
                    .macLiquidGlassCard(cornerRadius: 28, material: .thinMaterial)

                    Spacer()
                }
            }
        }
    }
}

struct MacDetailContentContainer<Content: View>: View {
    var maxWidth: CGFloat = 1180
    var horizontalPadding: CGFloat = 34
    var topPadding: CGFloat = 30
    var bottomPadding: CGFloat = 34
    let content: Content

    init(
        maxWidth: CGFloat = 1180,
        horizontalPadding: CGFloat = 34,
        topPadding: CGFloat = 30,
        bottomPadding: CGFloat = 34,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, topPadding)
                    .padding(.bottom, bottomPadding)
                    .frame(maxWidth: maxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollContentBackground(.hidden)
        }
    }
}

struct MacPageHeader: View {
    enum Title {
        case english(String)
        case brand(String)
        case mixed(english: String, chinese: String)
    }

    let systemImage: String
    let title: Title
    let subtitle: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(MacTheme.accentGradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                titleView

                if let subtitle {
                    MacMixedCaptionText(text: subtitle)
                }
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        switch title {
        case .english(let value):
            Text(value)
                .font(MacTypography.englishLargeTitle(size: 40))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
        case .brand(let value):
            Text(value)
                .font(MacTypography.englishBrand(size: 42))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
        case .mixed(let english, let chinese):
            MacMixedLanguageTitle(english: english, chinese: chinese, englishSize: 40, chineseSize: 38)
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
        }
    }
}

private struct MacMixedCaptionText: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let supportRange = text.range(of: "稍后支持") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(text[..<supportRange.lowerBound]).trimmingCharacters(in: .whitespaces))
                    .font(MacTypography.englishBody(size: 14, weight: .medium))

                Text("稍后支持")
                    .font(MacTypography.chineseBody(size: 14, weight: .medium))
            }
            .foregroundStyle(MacTheme.softText(for: colorScheme))
        } else {
            Text(text)
                .font(text.macContainsCJK ? MacTypography.chineseBody(size: 14) : MacTypography.englishBody(size: 14))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
        }
    }
}

private struct MacDetailPillText: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let colonIndex = text.firstIndex(of: ":") {
                let label = String(text[...colonIndex])
                let value = String(text[text.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                Text(label)
                    .font(MacTypography.englishCaption(size: 12, weight: .semibold))

                Text(value)
                    .font(value.macContainsCJK ? MacTypography.chineseCaption(size: 12, weight: .semibold) : MacTypography.numberBody(size: 12, weight: .semibold))
            } else {
                Text(text)
                    .font(MacTypography.pillFont(for: text, size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(MacTheme.softText(for: colorScheme))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .macGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.32)
    }
}

#Preview {
    MacRootView()
}
