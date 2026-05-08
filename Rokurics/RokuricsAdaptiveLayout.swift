//
//  RokuricsAdaptiveLayout.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import SwiftUI

enum RokuricsAdaptiveLayout {
    enum WidthCategory {
        case compact
        case regularPad
        case widePad
    }

    struct Metrics {
        let size: CGSize

        var width: CGFloat {
            max(size.width, 1)
        }

        var height: CGFloat {
            max(size.height, 1)
        }

        var widthCategory: WidthCategory {
            RokuricsAdaptiveLayout.widthCategory(for: width)
        }

        var isPadWidth: Bool {
            widthCategory != .compact
        }

        var horizontalPadding: CGFloat {
            RokuricsAdaptiveLayout.horizontalPadding(for: width)
        }

        var homeMaxWidth: CGFloat {
            switch widthCategory {
            case .compact:
                return .infinity
            case .regularPad:
                return 680
            case .widePad:
                return 760
            }
        }

        var headerScale: CGFloat {
            isPadWidth ? 1.12 : 1
        }

        var orbScale: CGFloat {
            if width < 360 {
                return height < 760 ? 0.78 : 0.84
            }

            if height < 760 {
                return 0.84
            }

            if height < 820 {
                return 0.92
            }

            return isPadWidth ? 1.16 : 1
        }

        var cardSpacing: CGFloat {
            isPadWidth ? 16 : 13
        }

        var homeTopPadding: CGFloat {
            isPadWidth ? 24 : 18
        }

        var homeBottomPadding: CGFloat {
            if height < 760 {
                return 18
            }

            return isPadWidth ? 34 : 26
        }

        var dashboardScale: CGFloat {
            if width < 360 {
                return 0.90
            }

            return isPadWidth ? 1.08 : 1
        }
    }

    static func metrics(for size: CGSize) -> Metrics {
        Metrics(size: size)
    }

    static func widthCategory(for width: CGFloat) -> WidthCategory {
        if width < 600 {
            return .compact
        }

        if width < 900 {
            return .regularPad
        }

        return .widePad
    }

    static func horizontalPadding(for width: CGFloat) -> CGFloat {
        switch widthCategory(for: width) {
        case .compact:
            return width < 360 ? 20 : 24
        case .regularPad:
            return 32
        case .widePad:
            return 40
        }
    }
}

struct RokuricsAdaptivePage<Content: View>: View {
    private let content: (RokuricsAdaptiveLayout.Metrics) -> Content

    init(@ViewBuilder content: @escaping (RokuricsAdaptiveLayout.Metrics) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            content(RokuricsAdaptiveLayout.metrics(for: proxy.size))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

extension View {
    func rokuricsCenteredColumn(maxWidth: CGFloat) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
