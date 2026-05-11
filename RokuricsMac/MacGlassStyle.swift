//
//  MacGlassStyle.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

private struct MacLiquidGlassCardModifier: ViewModifier {
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
        let resolvedFillOpacity = colorScheme == .dark ? min(fillOpacity * 0.82, 0.40) : fillOpacity
        let resolvedStrokeOpacity = colorScheme == .dark ? min(strokeOpacity * 0.72, 0.34) : strokeOpacity

        content
            .background {
                shape
                    .fill(MacTheme.glassSurface(for: colorScheme).opacity(resolvedFillOpacity))
            }
            .background(material, in: shape)
            .overlay {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(resolvedStrokeOpacity),
                                MacTheme.glassStroke(for: colorScheme).opacity(resolvedStrokeOpacity * 0.62),
                                MacTheme.aqua.opacity(colorScheme == .dark ? 0.22 : 0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .overlay {
                shape
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.22), lineWidth: 0.5)
                    .blur(radius: 0.35)
                    .offset(y: 0.5)
                    .mask(shape)
            }
            .shadow(
                color: MacTheme.shadow(for: colorScheme).opacity(colorScheme == .dark ? max(shadowOpacity * 0.48, 0.08) : shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.025),
                radius: shadowRadius * 0.45,
                x: 0,
                y: shadowY * 0.45
            )
    }
}

private struct MacGlassCapsuleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let material: Material
    let fillOpacity: Double
    let strokeOpacity: Double

    func body(content: Content) -> some View {
        let resolvedFillOpacity = colorScheme == .dark ? min(fillOpacity * 0.82, 0.40) : fillOpacity
        let resolvedStrokeOpacity = colorScheme == .dark ? min(strokeOpacity * 0.72, 0.34) : strokeOpacity

        content
            .background {
                Capsule(style: .continuous)
                    .fill(MacTheme.glassSurface(for: colorScheme).opacity(resolvedFillOpacity))
            }
            .background(material, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(resolvedStrokeOpacity),
                                MacTheme.aqua.opacity(resolvedStrokeOpacity * 0.55)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func macLiquidGlassCard(
        cornerRadius: CGFloat = 24,
        material: Material = .ultraThinMaterial,
        fillOpacity: Double = 0.48,
        strokeOpacity: Double = 0.46,
        shadowOpacity: Double = 0.10,
        shadowRadius: CGFloat = 18,
        shadowY: CGFloat = 10
    ) -> some View {
        modifier(
            MacLiquidGlassCardModifier(
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

    func macGlassCapsule(
        material: Material = .ultraThinMaterial,
        fillOpacity: Double = 0.42,
        strokeOpacity: Double = 0.38
    ) -> some View {
        modifier(
            MacGlassCapsuleModifier(
                material: material,
                fillOpacity: fillOpacity,
                strokeOpacity: strokeOpacity
            )
        )
    }
}
