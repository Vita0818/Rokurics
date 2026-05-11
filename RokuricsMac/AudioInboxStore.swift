//
//  AudioInboxStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Combine
import Foundation

final class AudioInboxStore: ObservableObject {
    @Published private(set) var pendingCount = 0
    @Published private(set) var processedCount = 0

    static let localRootDisplayPath = "~/Rokurics"

    // Future local data layout:
    // ~/Rokurics/audio/inbox/
    // ~/Rokurics/audio/processed/
    // ~/Rokurics/audio/archived/
    // ~/Rokurics/transcripts/
    // ~/Rokurics/notes/
    // ~/Rokurics/exports/
    // ~/Rokurics/metadata/
}
