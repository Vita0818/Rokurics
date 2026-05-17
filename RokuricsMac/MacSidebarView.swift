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
    case notes
    case iPhoneConnection

    static var allCases: [MacSidebarItem] {
        [.dashboard, .iPhoneConnection, .audioInbox, .notes]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "仪表盘"
        case .audioInbox: return "音频收件箱"
        case .notes: return "笔记"
        case .iPhoneConnection: return "iPhone 连接"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "rectangle.3.group"
        case .audioInbox: return "tray.and.arrow.down"
        case .notes: return "doc.text"
        case .iPhoneConnection: return "iphone"
        }
    }
}

struct MacSidebarView: View {
    @Binding var selection: MacSidebarItem?
    @Binding var isSettingsSelected: Bool
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

                    Text("Vita")
                        .font(MacTypography.englishBody(size: 13, weight: .semibold))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))

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
            if item == .iPhoneConnection {
                Text("iPhone")
                    .font(MacTypography.englishBody(size: 13, weight: isSelected ? .semibold : .medium))
            }

            Text(item == .iPhoneConnection ? "连接" : item.title)
                .font(MacTypography.chineseBody(size: 13, weight: isSelected ? .semibold : .medium))
        }
        .foregroundStyle(isSelected ? MacTheme.deepText(for: colorScheme) : MacTheme.softText(for: colorScheme))
    }
}

#Preview {
    MacSidebarView(selection: .constant(.dashboard), isSettingsSelected: .constant(false))
}
