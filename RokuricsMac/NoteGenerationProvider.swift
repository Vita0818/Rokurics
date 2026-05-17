//
//  NoteGenerationProvider.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

protocol NoteGenerationProvider {
    var id: String { get }
    var displayName: String { get }

    func validateConfiguration() async throws
    func generateNote(request: NoteGenerationRequest) async throws -> NoteGenerationResult
}
