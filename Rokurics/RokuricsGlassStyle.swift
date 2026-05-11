//
//  RokuricsGlassStyle.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import SwiftUI

private struct RokuricsLiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let material: Material
    let fillOpacity: Double
    let strokeOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let adjustedFillOpacity = colorScheme == .dark ? min(fillOpacity * 0.78, 0.36) : fillOpacity
        let adjustedStrokeOpacity = colorScheme == .dark ? min(strokeOpacity * 0.82, 0.34) : strokeOpacity
        let accentOpacity = colorScheme == .dark ? 0.24 : 0.16
        let baseShadowOpacity = colorScheme == .dark ? max(shadowOpacity * 0.52, 0.08) : shadowOpacity

        content
            .background {
                shape
                    .fill(RokuricsColors.glassSurface.opacity(adjustedFillOpacity))
            }
            .background(material, in: shape)
            .overlay {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(adjustedStrokeOpacity),
                                RokuricsColors.glassStroke.opacity(adjustedStrokeOpacity * 0.44),
                                RokuricsColors.glassStrokeAccent.opacity(accentOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .overlay {
                shape
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.22), lineWidth: 0.5)
                    .blur(radius: 0.4)
                    .offset(y: 0.5)
                    .mask(shape)
            }
            .shadow(color: RokuricsColors.shadow.opacity(baseShadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.025), radius: shadowRadius * 0.50, x: 0, y: shadowY * 0.50)
    }
}

private struct RokuricsGlassCapsuleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let material: Material
    let fillOpacity: Double
    let strokeOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    func body(content: Content) -> some View {
        let adjustedFillOpacity = colorScheme == .dark ? min(fillOpacity * 0.78, 0.36) : fillOpacity
        let adjustedStrokeOpacity = colorScheme == .dark ? min(strokeOpacity * 0.82, 0.34) : strokeOpacity
        let accentOpacity = colorScheme == .dark ? 0.24 : 0.16

        content
            .background {
                Capsule(style: .continuous)
                    .fill(RokuricsColors.glassSurface.opacity(adjustedFillOpacity))
            }
            .background(material, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(adjustedStrokeOpacity),
                                RokuricsColors.glassStroke.opacity(adjustedStrokeOpacity * 0.35),
                                RokuricsColors.aqua.opacity(accentOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: RokuricsColors.shadow.opacity(colorScheme == .dark ? max(shadowOpacity * 0.52, 0.08) : shadowOpacity), radius: shadowRadius, y: shadowY)
    }
}

private struct RokuricsGlassCircleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let material: Material
    let fillOpacity: Double
    let strokeOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    func body(content: Content) -> some View {
        let adjustedFillOpacity = colorScheme == .dark ? min(fillOpacity * 0.78, 0.36) : fillOpacity
        let adjustedStrokeOpacity = colorScheme == .dark ? min(strokeOpacity * 0.82, 0.34) : strokeOpacity
        let accentOpacity = colorScheme == .dark ? 0.24 : 0.14

        content
            .background {
                Circle()
                    .fill(RokuricsColors.glassSurface.opacity(adjustedFillOpacity))
            }
            .background(material, in: Circle())
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(adjustedStrokeOpacity),
                                RokuricsColors.glassStroke.opacity(adjustedStrokeOpacity * 0.32),
                                RokuricsColors.aqua.opacity(accentOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: RokuricsColors.shadow.opacity(colorScheme == .dark ? max(shadowOpacity * 0.52, 0.08) : shadowOpacity), radius: shadowRadius, y: shadowY)
    }
}

private struct RokuricsPausedBlinkModifier: ViewModifier {
    let isPaused: Bool
    let lowOpacity: Double
    let duration: TimeInterval
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(isPaused ? (isDimmed ? lowOpacity : 1.0) : 1.0)
            .onAppear {
                updateBlinking(isPaused)
            }
            .onChange(of: isPaused) { _, newValue in
                updateBlinking(newValue)
            }
    }

    private func updateBlinking(_ shouldBlink: Bool) {
        if shouldBlink {
            isDimmed = false

            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                isDimmed = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.14)) {
                isDimmed = false
            }
        }
    }
}

extension View {
    func rokuricsLiquidGlassCard(
        cornerRadius: CGFloat = 28,
        material: Material = .ultraThinMaterial,
        fillOpacity: Double = 0.46,
        strokeOpacity: Double = 0.42,
        shadowOpacity: Double = 0.11,
        shadowRadius: CGFloat = 18,
        shadowY: CGFloat = 10
    ) -> some View {
        modifier(
            RokuricsLiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                material: material,
                fillOpacity: fillOpacity,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }

    func rokuricsGlassCapsule(
        material: Material = .ultraThinMaterial,
        fillOpacity: Double = 0.46,
        strokeOpacity: Double = 0.40,
        shadowOpacity: Double = 0.08,
        shadowRadius: CGFloat = 12,
        shadowY: CGFloat = 6
    ) -> some View {
        modifier(
            RokuricsGlassCapsuleModifier(
                material: material,
                fillOpacity: fillOpacity,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }

    func rokuricsGlassCircle(
        material: Material = .ultraThinMaterial,
        fillOpacity: Double = 0.42,
        strokeOpacity: Double = 0.42,
        shadowOpacity: Double = 0.12,
        shadowRadius: CGFloat = 14,
        shadowY: CGFloat = 7
    ) -> some View {
        modifier(
            RokuricsGlassCircleModifier(
                material: material,
                fillOpacity: fillOpacity,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }

    func rokuricsSoftShadow(opacity: Double = 0.12, radius: CGFloat = 18, y: CGFloat = 10) -> some View {
        shadow(color: RokuricsColors.shadow.opacity(opacity), radius: radius, x: 0, y: y)
    }

    func rokuricsPausedBlinking(
        _ isPaused: Bool,
        lowOpacity: Double = 0.35,
        duration: TimeInterval = 0.9
    ) -> some View {
        modifier(
            RokuricsPausedBlinkModifier(
                isPaused: isPaused,
                lowOpacity: lowOpacity,
                duration: duration
            )
        )
    }
}
