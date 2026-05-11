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
    @ObservedObject var llmServiceConfig: LLMServiceConfig
    let onOpenIPhoneConnection: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.flexible(minimum: 280), spacing: 20, alignment: .top),
        GridItem(.flexible(minimum: 280), spacing: 20, alignment: .top)
    ]

    var body: some View {
        ZStack {
            MacTheme.pageGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        MacReceiverStatusCard(
                            secureReceiverService: secureReceiverService,
                            onOpenDetails: onOpenIPhoneConnection
                        )
                        MacAudioInboxCard(audioInboxStore: audioInboxStore, secureReceiverService: secureReceiverService)
                        MacTranscriptionCard(transcriptionQueue: transcriptionQueue)
                        MacAIProcessingCard(llmServiceConfig: llmServiceConfig)
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 30)
                .padding(.bottom, 34)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var header: some View {
        Text("Rokurics")
            .font(MacTypography.brandTitle(size: 42))
            .foregroundStyle(MacTheme.deepText(for: colorScheme))
    }
}

#Preview {
    MacDashboardView(
        secureReceiverService: SecureReceiverService(),
        audioInboxStore: AudioInboxStore(),
        transcriptionQueue: TranscriptionQueue(),
        llmServiceConfig: LLMServiceConfig(),
        onOpenIPhoneConnection: {}
    )
}
