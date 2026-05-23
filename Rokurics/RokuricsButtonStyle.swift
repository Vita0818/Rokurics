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

enum RokuricsIconCircleButtonConfiguration {
    static let size: CGFloat = RokuricsIconButtonMetrics.size
    static let iconSize: CGFloat = RokuricsIconButtonMetrics.iconSize
    static let borderWidth: CGFloat = 1
    static let fillOpacity: Double = 0.40
    static let strokeOpacity: Double = 0.44
    static let disabledOpacity: Double = RokuricsIconButtonMetrics.disabledOpacity
    static let usesGlassBackground = true
    static let usesSystemSymbols = true
}

struct RokuricsIconCircleButton: View {
    let systemName: String
    let accessibilityLabel: String
    var size: CGFloat = RokuricsIconCircleButtonConfiguration.size
    var tint: Color = RokuricsColors.deepText
    var isEnabled = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: min(RokuricsIconCircleButtonConfiguration.iconSize, size * 0.42), weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isEnabled ? tint : RokuricsColors.tertiaryText)
                .frame(width: size, height: size)
                .rokuricsGlassCircle(
                    fillOpacity: isEnabled ? RokuricsIconCircleButtonConfiguration.fillOpacity : 0.22,
                    strokeOpacity: RokuricsIconCircleButtonConfiguration.strokeOpacity,
                    shadowOpacity: isEnabled ? 0.10 : 0.04,
                    shadowRadius: 12,
                    shadowY: 6
                )
        }
        .buttonStyle(RokuricsScaleButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : RokuricsIconCircleButtonConfiguration.disabledOpacity)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct RokuricsBackButton: View {
    var tint: Color = RokuricsColors.deepText
    let action: () -> Void

    var body: some View {
        RokuricsIconCircleButton(
            systemName: "chevron.left",
            accessibilityLabel: "返回",
            tint: tint,
            action: action
        )
    }
}

struct RokuricsInfoButton: View {
    let action: () -> Void

    var body: some View {
        RokuricsIconCircleButton(
            systemName: "info",
            accessibilityLabel: "信息",
            action: action
        )
    }
}

extension ButtonStyle where Self == RokuricsPrimaryButtonStyle {
    static var rokuricsPrimary: RokuricsPrimaryButtonStyle {
        RokuricsPrimaryButtonStyle()
    }
}
