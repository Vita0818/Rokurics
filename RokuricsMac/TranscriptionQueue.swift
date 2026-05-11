//
//  TranscriptionQueue.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Combine
import Foundation

final class TranscriptionQueue: ObservableObject {
    @Published private(set) var status = "未配置"
    @Published private(set) var queuedCount = 0

    // Future: manage transcription jobs and call local Whisper, mlx-whisper, or whisper.cpp.
}
