//
//  MacSidebarView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

enum MacSidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case audioInbox
    case studyLibrary
    case iPhoneConnection
    case aiChat

    static var allCases: [MacSidebarItem] {
        [.studyLibrary, .aiChat, .iPhoneConnection]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return RokuricsCopy.text("仪表盘", "Dashboard")
        case .audioInbox: return RokuricsCopy.text("音频收件箱", "Inbox")
        case .studyLibrary: return RokuricsCopy.text("学习库", "Library")
        case .iPhoneConnection: return RokuricsCopy.text("iPhone 连接", "iPhone")
        case .aiChat: return RokuricsCopy.text("AI 对话", "AI Chat")
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "rectangle.3.group"
        case .audioInbox: return "tray.and.arrow.down"
        case .studyLibrary: return "books.vertical"
        case .iPhoneConnection: return "iphone"
        case .aiChat: return "bubble.left.and.bubble.right"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .dashboard: return "mac-sidebar-dashboard"
        case .audioInbox: return "mac-sidebar-audio-inbox"
        case .studyLibrary: return "mac-sidebar-study-library"
        case .iPhoneConnection: return "mac-sidebar-iphone-connection"
        case .aiChat: return "mac-sidebar-ai-chat"
        }
    }
}

struct MacSidebarView: View {
    @Binding var selection: MacSidebarItem?
    @Binding var isSettingsSelected: Bool
    @ObservedObject var userProfileStore: MacUserProfileStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rokurics")
                    .font(MacTypography.brandTitle(size: 30))
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))

                Text("Mac")
                    .font(MacTypography.englishCaption(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 18)

            VStack(spacing: 6) {
                ForEach(MacSidebarItem.allCases) { item in
                    Button {
                        selection = item
                        isSettingsSelected = false
                    } label: {
                        MacSidebarItemButton(
                            item: item,
                            isSelected: !isSettingsSelected && selection == item
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(item.accessibilityIdentifier)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Spacer(minLength: 12)

            Button {
                selection = nil
                isSettingsSelected = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSettingsSelected ? .white : MacTheme.aqua)
                        .frame(width: 30, height: 30)
                        .background {
                            Circle()
                                .fill(isSettingsSelected ? AnyShapeStyle(MacTheme.accentGradient) : AnyShapeStyle(MacTheme.glassSurface(for: colorScheme).opacity(0.48)))
                        }
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.46), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        MacMixedFontText(
                            text: userProfileStore.profile.displayName,
                            chineseFont: MacTypography.body(size: 13, weight: .semibold),
                            englishFont: MacTypography.englishBody(size: 13, weight: .semibold),
                            numberFont: MacTypography.numberBody(size: 13, weight: .semibold)
                        )
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .lineLimit(1)

                        Text(userProfileStore.profile.displayHandle)
                            .font(MacTypography.secondary(size: 10, weight: .medium))
                            .foregroundStyle(MacTheme.softText(for: colorScheme))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background {
            Rectangle()
                .fill(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.22 : 0.30))
                .background(.thinMaterial)
        }
    }
}

private struct MacSidebarItemButton: View {
    let item: MacSidebarItem
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 20, alignment: .center)

            MacSidebarTitle(item: item, isSelected: isSelected)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(backgroundFill)
                .background(isSelected ? .ultraThinMaterial : .regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .opacity(isSelected || isHovering ? 1 : 0)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
                .opacity(isSelected ? 1 : (isHovering ? 0.45 : 0))
        }
        .shadow(color: MacTheme.aqua.opacity(isSelected && colorScheme == .light ? 0.12 : 0), radius: 10, x: 0, y: 5)
        .onHover { isHovering = $0 }
    }

    private var iconColor: Color {
        isSelected ? MacTheme.leaf : MacTheme.softText(for: colorScheme)
    }

    private var backgroundFill: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        MacTheme.mint.opacity(colorScheme == .dark ? 0.30 : 0.42),
                        MacTheme.aqua.opacity(colorScheme == .dark ? 0.20 : 0.26)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.32))
    }

    private var borderColor: Color {
        isSelected
            ? MacTheme.aqua.opacity(colorScheme == .dark ? 0.38 : 0.52)
            : MacTheme.glassStroke(for: colorScheme).opacity(0.35)
    }
}

private struct MacSidebarTitle: View {
    let item: MacSidebarItem
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if item == .iPhoneConnection || item == .aiChat {
                Text(item == .iPhoneConnection ? "iPhone" : "AI")
                    .font(MacTypography.englishBody(size: 13, weight: isSelected ? .semibold : .medium))
            }

            Text(sidebarTitle)
                .font(MacTypography.chineseBody(size: 13, weight: isSelected ? .semibold : .medium))
        }
        .foregroundStyle(isSelected ? MacTheme.deepText(for: colorScheme) : MacTheme.softText(for: colorScheme))
    }

    private var sidebarTitle: String {
        switch item {
        case .iPhoneConnection:
            return RokuricsCopy.text("连接", "Link")
        case .aiChat:
            return RokuricsCopy.text("对话", "Chat")
        default:
            return item.title
        }
    }
}

#Preview {
    MacSidebarView(
        selection: .constant(.dashboard),
        isSettingsSelected: .constant(false),
        userProfileStore: MacUserProfileStore()
    )
}
