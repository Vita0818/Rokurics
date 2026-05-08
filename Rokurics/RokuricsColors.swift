//
//  RokuricsColors.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import SwiftUI
import UIKit

enum RokuricsColors {
    private struct RGBA {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> RGBA {
        RGBA(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    private static func adaptive(light: RGBA, dark: RGBA) -> Color {
        Color(
            UIColor { traits in
                let color = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: color.red,
                    green: color.green,
                    blue: color.blue,
                    alpha: color.alpha
                )
            }
        )
    }

    static let aqua = adaptive(light: rgb(0.35, 0.78, 0.76), dark: rgb(0.34, 0.84, 0.82))
    static let mint = adaptive(light: rgb(0.62, 0.91, 0.78), dark: rgb(0.32, 0.74, 0.58))
    static let mistGreen = adaptive(light: rgb(0.89, 0.98, 0.94), dark: rgb(0.06, 0.17, 0.15))
    static let softTeal = adaptive(light: rgb(0.46, 0.70, 0.71), dark: rgb(0.52, 0.80, 0.80))
    static let skyCyan = adaptive(light: rgb(0.45, 0.78, 0.94), dark: rgb(0.30, 0.70, 0.92))
    static let paleAqua = adaptive(light: rgb(0.77, 0.96, 0.91), dark: rgb(0.15, 0.42, 0.38))
    static let coral = adaptive(light: rgb(0.88, 0.42, 0.43), dark: rgb(0.96, 0.46, 0.48))

    static let deepText = adaptive(light: rgb(0.10, 0.26, 0.29), dark: rgb(0.90, 0.98, 0.97))
    static let softText = adaptive(light: rgb(0.39, 0.56, 0.58), dark: rgb(0.66, 0.82, 0.82))
    static let tertiaryText = adaptive(light: rgb(0.58, 0.70, 0.72), dark: rgb(0.46, 0.62, 0.63))

    static let glassSurface = adaptive(light: rgb(1, 1, 1), dark: rgb(0.05, 0.14, 0.14))
    static let glassStroke = adaptive(light: rgb(0.94, 1.0, 0.98), dark: rgb(0.54, 0.86, 0.82))
    static let glassStrokeAccent = adaptive(light: rgb(0.57, 0.91, 0.84), dark: rgb(0.38, 0.83, 0.76))
    static let shadow = adaptive(light: rgb(0.29, 0.72, 0.66), dark: rgb(0.00, 0.03, 0.03))

    static let pageGradient = LinearGradient(
        colors: [
            adaptive(light: rgb(0.94, 1.0, 0.97), dark: rgb(0.02, 0.08, 0.08)),
            adaptive(light: rgb(0.86, 0.97, 0.96), dark: rgb(0.04, 0.17, 0.16)),
            adaptive(light: rgb(0.95, 0.98, 1.0), dark: rgb(0.01, 0.05, 0.07))
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let actionGradient = LinearGradient(
        colors: [
            adaptive(light: rgb(0.31, 0.76, 0.75), dark: rgb(0.07, 0.50, 0.50)),
            adaptive(light: rgb(0.60, 0.90, 0.76), dark: rgb(0.17, 0.67, 0.51))
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let quietGradient = LinearGradient(
        colors: [
            adaptive(light: rgb(0.85, 0.98, 0.94), dark: rgb(0.08, 0.22, 0.20)),
            adaptive(light: rgb(0.91, 0.98, 1.0), dark: rgb(0.05, 0.16, 0.20))
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let recordingAccentGradient = LinearGradient(
        colors: [
            adaptive(light: rgb(0.86, 0.42, 0.45), dark: rgb(0.82, 0.26, 0.34)),
            adaptive(light: rgb(0.96, 0.68, 0.58), dark: rgb(0.88, 0.44, 0.42))
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
