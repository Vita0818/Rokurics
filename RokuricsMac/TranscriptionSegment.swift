//
//  TranscriptionSegment.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct TranscriptionSegment: Codable, Equatable, Identifiable {
    let id: String
    let startTime: Double
    let endTime: Double
    let text: String
    let confidence: Double?
}
