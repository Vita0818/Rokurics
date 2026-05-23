//
//  SharedRokuricsUI.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import SwiftUI

enum RokuricsSharedTypographyToken {
    case pageTitle
    case pageSubtitle
    case sectionTitle
    case cardTitle
    case body
    case secondary
    case chatGreeting
    case chatMessage
    case chatInput
    case technical
}

enum RokuricsIconButtonMetrics {
    static let size: CGFloat = 44
    static let iconSize: CGFloat = 18
    static let groupItemSize: CGFloat = 44
    static let groupPadding: CGFloat = 2
    static let groupSpacing: CGFloat = 0
    static let groupSeparatorWidth: CGFloat = 1
    static let groupSeparatorHeight: CGFloat = 24
    static let disabledOpacity: Double = 0.48
}

enum RokuricsMobilePageLayoutMetrics {
    static let horizontalPadding: CGFloat = 24
    static let topPadding: CGFloat = 12
    static let bottomPadding: CGFloat = 34
    static let titleTopSpacing: CGFloat = 18
    static let titleSubtitleSpacing: CGFloat = 8
    static let headerBottomSpacing: CGFloat = 18
    static let contentSpacing: CGFloat = 18
    static let maxContentWidth: CGFloat = 520
    static let titleSize: CGFloat = 32
}

struct RokuricsMobilePageHeader<Leading: View, Trailing: View, TitleContent: View, SubtitleContent: View>: View {
    let leading: () -> Leading
    let trailing: () -> Trailing
    let titleContent: () -> TitleContent
    let subtitleContent: () -> SubtitleContent

    init(
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder title: @escaping () -> TitleContent,
        @ViewBuilder subtitle: @escaping () -> SubtitleContent
    ) {
        self.leading = leading
        self.trailing = trailing
        self.titleContent = title
        self.subtitleContent = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                leading()
                    .frame(width: RokuricsIconButtonMetrics.size, height: RokuricsIconButtonMetrics.size)

                Spacer(minLength: 8)

                trailing()
            }
            .frame(height: RokuricsIconButtonMetrics.size)
            .frame(maxWidth: .infinity)

            titleContent()
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, RokuricsMobilePageLayoutMetrics.titleTopSpacing)
                .accessibilityAddTraits(.isHeader)

            subtitleContent()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, RokuricsMobilePageLayoutMetrics.titleSubtitleSpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension RokuricsMobilePageHeader where SubtitleContent == EmptyView {
    init(
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder title: @escaping () -> TitleContent
    ) {
        self.init(
            leading: leading,
            trailing: trailing,
            title: title,
            subtitle: { EmptyView() }
        )
    }
}

struct RokuricsMobileBackButton: View {
    var tint: Color?
    var isEnabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RokuricsGlassIconButton(
            systemImage: "chevron.left",
            accessibilityTitle: "返回",
            tint: tint ?? RokuricsSharedStyle.deepText(for: colorScheme),
            isEnabled: isEnabled,
            action: action
        )
    }
}

struct RokuricsSharedText: View {
    let text: String
    let token: RokuricsSharedTypographyToken
    var size: CGFloat?
    var weight: Font.Weight?
    var forceTechnical = false

    var body: some View {
        #if os(macOS)
        RokuricsMixedText(
            text,
            style: MacTypography.mixedStyle(for: token.macStyle),
            forceTechnical: forceTechnical || token == .technical
        )
        #else
        RokuricsText(
            text,
            token: token.iOSToken,
            size: size,
            weight: weight,
            forceTechnical: forceTechnical || token == .technical
        )
        #endif
    }
}

extension RokuricsSharedTypographyToken {
    #if os(macOS)
    var macStyle: RokuricsTextStyle {
        switch self {
        case .pageTitle: return .pageTitle
        case .pageSubtitle: return .pageSubtitle
        case .sectionTitle: return .sectionTitle
        case .cardTitle: return .cardTitle
        case .body: return .body
        case .secondary: return .secondary
        case .chatGreeting: return .chatGreeting
        case .chatMessage: return .chatMessage
        case .chatInput: return .chatInput
        case .technical: return .technical
        }
    }
    #else
    var iOSToken: RokuricsTypographyToken {
        switch self {
        case .pageTitle: return .pageTitle
        case .pageSubtitle: return .pageSubtitle
        case .sectionTitle: return .sectionTitle
        case .cardTitle: return .cardTitle
        case .body: return .body
        case .secondary: return .secondary
        case .chatGreeting: return .chatGreeting
        case .chatMessage: return .chatMessage
        case .chatInput: return .chatInput
        case .technical: return .technical
        }
    }
    #endif
}

enum RokuricsSharedStyle {
    static func deepText(for colorScheme: ColorScheme) -> Color {
        #if os(macOS)
        MacTheme.deepText(for: colorScheme)
        #else
        RokuricsColors.deepText
        #endif
    }

    static func softText(for colorScheme: ColorScheme) -> Color {
        #if os(macOS)
        MacTheme.softText(for: colorScheme)
        #else
        RokuricsColors.softText
        #endif
    }

    static func tertiaryText(for colorScheme: ColorScheme) -> Color {
        #if os(macOS)
        MacTheme.tertiaryText(for: colorScheme)
        #else
        RokuricsColors.tertiaryText
        #endif
    }

    static var aqua: Color {
        #if os(macOS)
        MacTheme.aqua
        #else
        RokuricsColors.aqua
        #endif
    }

    static var mint: Color {
        #if os(macOS)
        MacTheme.mint
        #else
        RokuricsColors.mint
        #endif
    }

    static var leaf: Color {
        #if os(macOS)
        MacTheme.leaf
        #else
        RokuricsColors.softTeal
        #endif
    }

    static var coral: Color {
        #if os(macOS)
        MacTheme.coral
        #else
        RokuricsColors.coral
        #endif
    }

    static var actionGradient: LinearGradient {
        #if os(macOS)
        MacTheme.accentGradient
        #else
        RokuricsColors.actionGradient
        #endif
    }

    static func pageGradient(for colorScheme: ColorScheme) -> LinearGradient {
        #if os(macOS)
        MacTheme.pageGradient(for: colorScheme)
        #else
        RokuricsColors.pageGradient
        #endif
    }
}

extension View {
    @ViewBuilder
    func rokuricsSharedGlassCard(
        cornerRadius: CGFloat = 22,
        material: Material = .thinMaterial,
        fillOpacity: Double = 0.32,
        strokeOpacity: Double = 0.30,
        shadowOpacity: Double = 0.05,
        shadowRadius: CGFloat = 9,
        shadowY: CGFloat = 4
    ) -> some View {
        #if os(macOS)
        macLiquidGlassCard(
            cornerRadius: cornerRadius,
            material: material,
            fillOpacity: fillOpacity,
            strokeOpacity: strokeOpacity,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        )
        #else
        rokuricsLiquidGlassCard(
            cornerRadius: cornerRadius,
            material: material,
            fillOpacity: fillOpacity,
            strokeOpacity: strokeOpacity,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        )
        #endif
    }

    @ViewBuilder
    func rokuricsSharedGlassCapsule(
        material: Material = .ultraThinMaterial,
        fillOpacity: Double = 0.26,
        strokeOpacity: Double = 0.24
    ) -> some View {
        #if os(macOS)
        macGlassCapsule(material: material, fillOpacity: fillOpacity, strokeOpacity: strokeOpacity)
        #else
        rokuricsGlassCapsule(material: material, fillOpacity: fillOpacity, strokeOpacity: strokeOpacity)
        #endif
    }

    @ViewBuilder
    func rokuricsSharedGlassCircle(
        material: Material = .ultraThinMaterial,
        fillOpacity: Double = 0.34,
        strokeOpacity: Double = 0.30,
        shadowOpacity: Double = 0.08,
        shadowRadius: CGFloat = 10,
        shadowY: CGFloat = 5
    ) -> some View {
        #if os(macOS)
        macGlassCircle(
            material: material,
            fillOpacity: fillOpacity,
            strokeOpacity: strokeOpacity,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        )
        #else
        rokuricsGlassCircle(
            material: material,
            fillOpacity: fillOpacity,
            strokeOpacity: strokeOpacity,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        )
        #endif
    }
}

enum RokuricsSharedIconButtonConfiguration {
    #if os(macOS)
    static let size = RokuricsCircleIconButtonConfiguration.size
    static let iconSize = RokuricsCircleIconButtonConfiguration.iconSize
    static let disabledOpacity = RokuricsCircleIconButtonConfiguration.disabledOpacity
    static let groupItemSize = RokuricsCircleIconButtonConfiguration.size - 8
    static let groupPadding: CGFloat = 4
    static let groupSpacing: CGFloat = 2
    static let groupSeparatorWidth: CGFloat = 1
    static let groupSeparatorHeight = RokuricsCircleIconButtonConfiguration.size - 20
    #else
    static let size = RokuricsIconButtonMetrics.size
    static let iconSize = RokuricsIconButtonMetrics.iconSize
    static let disabledOpacity = RokuricsIconButtonMetrics.disabledOpacity
    static let groupItemSize = RokuricsIconButtonMetrics.groupItemSize
    static let groupPadding = RokuricsIconButtonMetrics.groupPadding
    static let groupSpacing = RokuricsIconButtonMetrics.groupSpacing
    static let groupSeparatorWidth = RokuricsIconButtonMetrics.groupSeparatorWidth
    static let groupSeparatorHeight = RokuricsIconButtonMetrics.groupSeparatorHeight
    #endif
}

struct RokuricsGlassIconButton: View {
    let systemImage: String
    let accessibilityTitle: String
    var tint: Color?
    var isEnabled = true
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        #if os(macOS)
        RokuricsCircleIconButton(
            systemImage: systemImage,
            accessibilityTitle: accessibilityTitle,
            tint: tint,
            isEnabled: isEnabled,
            role: role,
            action: action
        )
        #else
        RokuricsIconCircleButton(
            systemName: systemImage,
            accessibilityLabel: accessibilityTitle,
            tint: tint ?? RokuricsColors.deepText,
            isEnabled: isEnabled,
            action: action
        )
        #endif
    }
}

struct RokuricsIconButtonGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: RokuricsSharedIconButtonConfiguration.groupSpacing) {
            content
        }
        .padding(RokuricsSharedIconButtonConfiguration.groupPadding)
        .rokuricsSharedGlassCapsule(
            fillOpacity: 0.34,
            strokeOpacity: 0.34
        )
    }
}

struct RokuricsIconButtonGroupSeparator: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(RokuricsSharedStyle.tertiaryText(for: colorScheme).opacity(0.28))
            .frame(
                width: RokuricsSharedIconButtonConfiguration.groupSeparatorWidth,
                height: RokuricsSharedIconButtonConfiguration.groupSeparatorHeight
            )
    }
}

struct RokuricsIconButtonGroupItem: View {
    let systemName: String
    let accessibilityLabel: String
    var tint: Color?
    var isEnabled = true
    var role: ButtonRole?
    var action: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: RokuricsSharedIconButtonConfiguration.iconSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isEnabled ? (tint ?? RokuricsSharedStyle.deepText(for: colorScheme)) : RokuricsSharedStyle.tertiaryText(for: colorScheme))
                .frame(
                    width: RokuricsSharedIconButtonConfiguration.groupItemSize,
                    height: RokuricsSharedIconButtonConfiguration.groupItemSize
                )
                .contentShape(Circle())
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .buttonStyle(RokuricsScaleButtonStyle())
        #endif
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : RokuricsSharedIconButtonConfiguration.disabledOpacity)
        .accessibilityLabel(accessibilityLabel)
        #if os(macOS)
        .help(accessibilityLabel)
        #endif
    }
}
