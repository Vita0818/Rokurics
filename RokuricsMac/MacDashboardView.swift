//
//  MacDashboardView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

struct MacDashboardView: View {
    @ObservedObject var secureReceiverService: SecureReceiverService
    @ObservedObject var audioInboxStore: AudioInboxStore
    @ObservedObject var noteGenerationSettingsStore: NoteGenerationSettingsStore
    let onOpenIPhoneConnection: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.flexible(minimum: 280), spacing: 20, alignment: .top),
        GridItem(.flexible(minimum: 280), spacing: 20, alignment: .top)
    ]

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            MacDetailContentContainer(maxWidth: 1180) {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(MacDashboardCardKind.visibleCards) { card in
                            dashboardCard(for: card)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dashboardCard(for card: MacDashboardCardKind) -> some View {
        switch card {
        case .iPhoneConnection:
            MacReceiverStatusCard(
                secureReceiverService: secureReceiverService,
                onOpenDetails: onOpenIPhoneConnection
            )
        case .audioInbox:
            MacAudioInboxCard(audioInboxStore: audioInboxStore, secureReceiverService: secureReceiverService)
        case .aiProcessing:
            MacAIProcessingCard(noteGenerationSettingsStore: noteGenerationSettingsStore)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rokurics")
                .font(MacTypography.englishBrand(size: 42))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            Text("Dashboard")
                .font(MacTypography.englishBody(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
        }
    }
}

enum MacDashboardCardKind: String, CaseIterable, Identifiable {
    case iPhoneConnection
    case audioInbox
    case aiProcessing

    static let visibleCards: [MacDashboardCardKind] = [
        .iPhoneConnection,
        .audioInbox,
        .aiProcessing
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iPhoneConnection:
            return "iPhone 连接"
        case .audioInbox:
            return "音频收件箱"
        case .aiProcessing:
            return "AI 整理"
        }
    }
}

#Preview {
    MacDashboardView(
        secureReceiverService: SecureReceiverService(),
        audioInboxStore: AudioInboxStore(),
        noteGenerationSettingsStore: NoteGenerationSettingsStore(),
        onOpenIPhoneConnection: {}
    )
}
