//
//  RecordingLiveActivityAttributes.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import ActivityKit
import Foundation

struct RecordingLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var elapsedMinutes: Int
        var isPaused: Bool
        var isSavingLocally: Bool

        var elapsedMinuteText: String {
            String(format: "%02d", max(0, elapsedMinutes))
        }

        var statusText: String {
            if isSavingLocally {
                return "本地保存中"
            }

            return isPaused ? "已暂停" : "录音中"
        }
    }

    var recordingName: String
}
