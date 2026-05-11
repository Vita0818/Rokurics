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
    case transcripts
    case notes
    case iPhoneConnection

    static var allCases: [MacSidebarItem] {
        [.dashboard, .audioInbox, .transcripts, .notes]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .audioInbox: return "Audio Inbox"
        case .transcripts: return "Transcripts"
        case .notes: return "Notes"
        case .iPhoneConnection: return "iPhone Connection"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "rectangle.3.group"
        case .audioInbox: return "tray.and.arrow.down"
        case .transcripts: return "waveform.and.magnifyingglass"
        case .notes: return "doc.text"
        case .iPhoneConnection: return "iphone.gen3"
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

            List(selection: $selection) {
                ForEach(MacSidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .font(MacTypography.englishBody(size: 13, weight: .medium))
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

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
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MacTheme.glassSurface(for: colorScheme).opacity(isSettingsSelected ? 0.46 : 0.18))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(MacTheme.glassStroke(for: colorScheme).opacity(isSettingsSelected ? 0.42 : 0.18), lineWidth: 1)
                    }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .onChange(of: selection) { _, newValue in
            if newValue != nil {
                isSettingsSelected = false
            }
        }
        .background {
            Rectangle()
                .fill(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.22 : 0.30))
                .background(.thinMaterial)
        }
    }
}

#Preview {
    MacSidebarView(selection: .constant(.dashboard), isSettingsSelected: .constant(false))
}
