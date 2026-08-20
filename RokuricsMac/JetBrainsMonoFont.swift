//
//  JetBrainsMonoFont.swift
//  RokuricsMac
//

import AppKit
import SwiftUI

/// Thin, target-local wiring for the bundled JetBrains Mono files.
///
/// The font has no CJK glyphs, so mixed strings continue through the system
/// fallback cascade (PingFang for Chinese). LaTeX renderers intentionally do
/// not use this entry point.
enum JetBrainsMonoFont {
    private static let regularPostScriptName = "JetBrainsMono-Regular"
    private static let mediumPostScriptName = "JetBrainsMono-Medium"
    private static let semiboldPostScriptName = "JetBrainsMono-SemiBold"
    private static let boldPostScriptName = "JetBrainsMono-Bold"

    private static let requiredPostScriptNames = [
        regularPostScriptName,
        mediumPostScriptName,
        semiboldPostScriptName,
        boldPostScriptName
    ]

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        ensureAvailable()
        return .custom(postScriptName(for: weight), fixedSize: size)
    }

    static func ensureAvailable() {
        _ = availabilityCheck
    }

    private static let availabilityCheck: Void = {
        for postScriptName in requiredPostScriptNames {
            guard NSFont(name: postScriptName, size: 12) != nil else {
                fatalError(
                    "Required JetBrains Mono font \(postScriptName) is unavailable. "
                        + "Verify the Fonts target membership and ATSApplicationFontsPath."
                )
            }
        }
    }()

    private static func postScriptName(for weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black {
            return boldPostScriptName
        }
        if weight == .semibold {
            return semiboldPostScriptName
        }
        if weight == .medium {
            return mediumPostScriptName
        }
        return regularPostScriptName
    }
}
