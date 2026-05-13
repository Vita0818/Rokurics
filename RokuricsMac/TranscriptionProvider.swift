//
//  TranscriptionProvider.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

protocol TranscriptionProvider {
    var id: String { get }
    var displayName: String { get }

    func validateConfiguration() async throws
    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult
}
