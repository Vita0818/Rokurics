//
//  MacTypography.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

enum MacTypography {
    // Chinese typography follows the app's single local system Chinese family.
    static func chineseTitle(size: CGFloat = 28, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    static func chineseHeadline(size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func chineseBody(size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func chineseCaption(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    static func englishTitle(size: CGFloat = 34, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func englishHeadline(size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func englishBody(size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func englishCaption(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func number(size: CGFloat = 38, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif).monospacedDigit()
    }

    static func brandTitle(size: CGFloat = 42, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
