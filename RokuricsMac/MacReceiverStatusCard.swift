//
//  MacReceiverStatusCard.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

struct MacReceiverStatusCard: View {
    @ObservedObject var secureReceiverService: SecureReceiverService
    let onOpenDetails: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpenDetails) {
            MacDashboardCard(systemImage: "antenna.radiowaves.left.and.right", tint: MacTheme.aqua) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("iPhone")
                        .font(MacTypography.englishHeadline(size: 17))

                    Text("连接")
                        .font(MacTypography.chineseHeadline(size: 17))
                }
            } content: {
                VStack(alignment: .leading, spacing: 14) {
                    Text(summaryStatus)
                        .font(MacTypography.chineseTitle(size: 31))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        MacStatusPill(text: "Port \(secureReceiverService.port)", systemImage: "number", tint: MacTheme.leaf)
                        MacStatusPill(text: ipSummary, systemImage: "wifi", tint: MacTheme.aqua)
                    }

                    MacStatusPill(
                        text: "\(secureReceiverService.pairedDeviceCount) 台已配对",
                        systemImage: "checkmark.shield",
                        tint: secureReceiverService.pairedDeviceCount > 0 ? MacTheme.mint : MacTheme.tertiaryText(for: colorScheme)
                    )

                    Spacer(minLength: 0)

                    HStack(spacing: 7) {
                        Text("查看详情")
                            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(MacTheme.aqua)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var summaryStatus: String {
        if !secureReceiverService.canStartHTTPS {
            return "HTTPS 未就绪"
        }

        if secureReceiverService.pairedDeviceCount > 0 {
            return "已配对"
        }

        if secureReceiverService.isHTTPSRunning {
            return "HTTPS 运行中"
        }

        return "未配对"
    }

    private var ipSummary: String {
        secureReceiverService.localIPAddress == "未知" ? "IP 未知" : secureReceiverService.localIPAddress
    }
}

private struct MacReceiverControlButtonStyle: ButtonStyle {
    let isRunning: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
            .foregroundStyle(isRunning ? MacTheme.coral : .white)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background {
                Capsule(style: .continuous)
                    .fill(isRunning ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(MacTheme.accentGradient))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(isRunning ? MacTheme.coral.opacity(0.42) : Color.white.opacity(0.42), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct MacPairingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
            .foregroundStyle(MacTheme.aqua)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(MacTheme.aqua.opacity(0.36), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}
