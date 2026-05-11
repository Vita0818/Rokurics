//
//  ExportManager.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Combine
import Foundation

final class ExportManager: ObservableObject {
    @Published private(set) var supportedFormats = ["Markdown", "Kikaria", "Anki CSV"]
    @Published private(set) var primaryFormat = "Markdown"

    // Future: export Markdown notes, Kikaria presets, and Anki CSV decks.
}
