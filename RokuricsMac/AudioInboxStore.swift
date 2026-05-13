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
    @Published private(set) var recordingItems: [MacRecordingInboxItem] = []

    static let localRootDisplayPath = "~/Library/Application Support/Rokurics"

    private let recordingFileStore: MacRecordingFileStore
    private var cancellable: AnyCancellable?

    init(recordingFileStore: MacRecordingFileStore? = nil) {
        self.recordingFileStore = recordingFileStore ?? MacRecordingFileStore()
        refreshRecordingInbox()
        cancellable = NotificationCenter.default
            .publisher(for: MacRecordingFileStore.inboxDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshRecordingInbox()
            }
    }

    var latestRecordingItem: MacRecordingInboxItem? {
        recordingItems.first
    }

    var libraryRootDisplayPath: String {
        recordingFileStore.libraryRootDisplayPath
    }

    func refreshRecordingInbox() {
        let items = recordingFileStore.loadInboxItems()
        recordingItems = items
        pendingCount = items.filter(\.hasAudio).count
        processedCount = 0
    }

    // Future local data layout:
    // ~/Library/Application Support/Rokurics/audio/inbox/
    // ~/Library/Application Support/Rokurics/audio/processing/
    // ~/Library/Application Support/Rokurics/audio/processed/
    // ~/Library/Application Support/Rokurics/audio/archived/
    // ~/Library/Application Support/Rokurics/transcripts/
    // ~/Library/Application Support/Rokurics/notes/
    // ~/Library/Application Support/Rokurics/exports/
    // ~/Library/Application Support/Rokurics/metadata/
    // ~/Library/Application Support/Rokurics/system/
}
