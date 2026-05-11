//
//  MacTheme.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

enum MacTheme {
    static let aqua = Color(red: 0.31, green: 0.74, blue: 0.73)
    static let mint = Color(red: 0.58, green: 0.90, blue: 0.76)
    static let mist = Color(red: 0.90, green: 0.98, blue: 0.95)
    static let paleCyan = Color(red: 0.78, green: 0.95, blue: 0.94)
    static let leaf = Color(red: 0.36, green: 0.66, blue: 0.54)
    static let coral = Color(red: 0.89, green: 0.45, blue: 0.43)
    static let amber = Color(red: 0.88, green: 0.66, blue: 0.32)

    static func deepText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.88, green: 0.97, blue: 0.96)
            : Color(red: 0.09, green: 0.24, blue: 0.27)
    }

    static func softText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.64, green: 0.80, blue: 0.80)
            : Color(red: 0.38, green: 0.55, blue: 0.57)
    }

    static func tertiaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.42, green: 0.58, blue: 0.59)
            : Color(red: 0.56, green: 0.68, blue: 0.70)
    }

    static func glassSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.04, green: 0.13, blue: 0.13)
            : Color.white
    }

    static func glassStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.38, green: 0.76, blue: 0.73)
            : Color(red: 0.88, green: 1.00, blue: 0.96)
    }

    static func shadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.black
            : Color(red: 0.28, green: 0.68, blue: 0.64)
    }

    static let pageGradient = LinearGradient(
        colors: [
            Color(red: 0.95, green: 1.00, blue: 0.98),
            Color(red: 0.88, green: 0.97, blue: 0.96),
            Color(red: 0.96, green: 0.99, blue: 1.00)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.30, green: 0.74, blue: 0.73),
            Color(red: 0.58, green: 0.89, blue: 0.75)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
