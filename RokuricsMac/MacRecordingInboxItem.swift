//
//  MacRecordingInboxItem.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/12.
//

import Foundation

struct MacRecordingInboxItem: Identifiable, Equatable {
    let id: String
    let title: String
    let receivedAt: Date
    let duration: TimeInterval
    let fileSize: Int64
    let sourceDeviceName: String
    let transcriptionStatus: String
    let noteStatus: String
    let receiveStatus: String
    let hasAudio: Bool

    var statusText: String {
        transcriptionStatus == "notStarted" ? "待转写" : transcriptionStatus
    }
}
