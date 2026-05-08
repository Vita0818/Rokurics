//
//  RokuricsTypography.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import SwiftUI

enum RokuricsTypography {
    static func appTitle(size: CGFloat = 39, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func largeNumber(size: CGFloat = 42, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func title(size: CGFloat = 30, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    static func headline(size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func body(size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func caption(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    static func button(size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
}
