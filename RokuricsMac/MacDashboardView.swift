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
    @ObservedObject var transcriptionQueue: TranscriptionQueue
    @ObservedObject var transcriptionCoordinator: TranscriptionCoordinator
    @ObservedObject var llmServiceConfig: LLMServiceConfig
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
                        MacReceiverStatusCard(
                            secureReceiverService: secureReceiverService,
                            onOpenDetails: onOpenIPhoneConnection
                        )
                        MacAudioInboxCard(audioInboxStore: audioInboxStore, secureReceiverService: secureReceiverService)
                        MacTranscriptionCard(
                            audioInboxStore: audioInboxStore,
                            transcriptionCoordinator: transcriptionCoordinator
                        )
                        MacAIProcessingCard(llmServiceConfig: llmServiceConfig)
                    }
                }
            }
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

#Preview {
    MacDashboardView(
        secureReceiverService: SecureReceiverService(),
        audioInboxStore: AudioInboxStore(),
        transcriptionQueue: TranscriptionQueue(),
        transcriptionCoordinator: TranscriptionCoordinator(),
        llmServiceConfig: LLMServiceConfig(),
        onOpenIPhoneConnection: {}
    )
}
