//
//  AudioConversionResult.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/15.
//

import Foundation

struct AudioConversionResult: Equatable {
    let originalAudioFileURL: URL
    let preparedAudioFileURL: URL
    let didConvert: Bool
    let workingDirectoryURL: URL?
}
