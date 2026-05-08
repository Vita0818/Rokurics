//
//  RokuricsButtonStyle.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import SwiftUI

struct RokuricsPrimaryButtonStyle: ButtonStyle {
    var verticalPadding: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RokuricsTypography.button())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(RokuricsColors.actionGradient, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.46),
                                Color.white.opacity(0.12),
                                RokuricsColors.mint.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: RokuricsColors.shadow.opacity(configuration.isPressed ? 0.10 : 0.18), radius: 16, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct RokuricsScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct RokuricsIconCircleButton: View {
    let systemName: String
    let accessibilityLabel: String
    var size: CGFloat = 44
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(RokuricsColors.deepText)
                .frame(width: size, height: size)
                .rokuricsGlassCircle(fillOpacity: 0.40, strokeOpacity: 0.44, shadowOpacity: 0.10, shadowRadius: 12, shadowY: 6)
        }
        .buttonStyle(RokuricsScaleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

extension ButtonStyle where Self == RokuricsPrimaryButtonStyle {
    static var rokuricsPrimary: RokuricsPrimaryButtonStyle {
        RokuricsPrimaryButtonStyle()
    }
}
