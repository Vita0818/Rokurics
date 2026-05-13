//
//  MacTypography.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

enum MacTypography {
    // English-only product language uses a serif voice.
    static func englishBrand(size: CGFloat = 42, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func englishLargeTitle(size: CGFloat = 40, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func englishTitle(size: CGFloat = 34, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func englishHeadline(size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func englishBody(size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func englishCaption(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    // Chinese copy stays on the native system Chinese font. Do not route Chinese
    // labels through serif tokens.
    static func chineseLargeTitle(size: CGFloat = 38, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    static func chineseTitle(size: CGFloat = 28, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    static func chineseHeadline(size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func chineseBody(size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func chineseCaption(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    // Numbers use the serif display voice with stable digit spacing.
    static func numberLarge(size: CGFloat = 46, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif).monospacedDigit()
    }

    static func numberTitle(size: CGFloat = 38, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif).monospacedDigit()
    }

    static func numberBody(size: CGFloat = 13, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif).monospacedDigit()
    }

    static func fingerprint(size: CGFloat = 15, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func technical(size: CGFloat = 13, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func number(size: CGFloat = 38, weight: Font.Weight = .bold) -> Font {
        numberTitle(size: size, weight: weight)
    }

    static func brandTitle(size: CGFloat = 42, weight: Font.Weight = .semibold) -> Font {
        englishBrand(size: size, weight: weight)
    }

    static func statusDisplay(for text: String, size: CGFloat = 34, weight: Font.Weight = .bold) -> Font {
        if text.macContainsCJK {
            return chineseTitle(size: size, weight: weight)
        }

        if text.macLooksNumeric {
            return numberTitle(size: size, weight: weight)
        }

        return englishTitle(size: size, weight: weight)
    }

    static func pillFont(for text: String, size: CGFloat = 12, weight: Font.Weight = .semibold) -> Font {
        if text.macContainsCJK {
            return chineseCaption(size: size, weight: weight)
        }

        if text.macLooksNumeric {
            return numberBody(size: size, weight: weight)
        }

        return englishCaption(size: size, weight: weight)
    }

    static func rowPrimaryFont(for text: String, size: CGFloat = 13, weight: Font.Weight = .semibold) -> Font {
        text.macContainsCJK
            ? chineseBody(size: size, weight: weight)
            : englishBody(size: size, weight: weight)
    }
}

struct MacMixedLanguageTitle: View {
    let english: String
    let chinese: String
    var englishSize: CGFloat = 40
    var chineseSize: CGFloat = 38
    var weight: Font.Weight = .semibold

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(english)
                .font(MacTypography.englishLargeTitle(size: englishSize, weight: weight))

            Text(chinese)
                .font(MacTypography.chineseLargeTitle(size: chineseSize, weight: weight))
        }
    }
}

struct MacMixedFontText: View {
    let text: String
    var chineseFont: Font = MacTypography.chineseBody(size: 14, weight: .semibold)
    var englishFont: Font = MacTypography.englishBody(size: 14, weight: .semibold)
    var numberFont: Font = MacTypography.numberBody(size: 14, weight: .semibold)

    var body: some View {
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()

        for run in text.macMixedFontRuns {
            var segment = AttributedString(run.value)
            segment.font = font(for: run.kind)
            result += segment
        }

        return result
    }

    private func font(for kind: MacMixedFontRun.Kind) -> Font {
        switch kind {
        case .chinese:
            return chineseFont
        case .english:
            return englishFont
        case .number:
            return numberFont
        }
    }
}

struct MacMixedFontRun {
    enum Kind {
        case chinese
        case english
        case number
    }

    let kind: Kind
    let value: String
}

extension String {
    var macContainsCJK: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x20000...0x2A6DF,
                 0x2A700...0x2B73F,
                 0x2B740...0x2B81F,
                 0x2B820...0x2CEAF:
                return true
            default:
                return false
            }
        }
    }

    var macLooksNumeric: Bool {
        let allowed = CharacterSet(charactersIn: "0123456789.:/-_ ")
        return !isEmpty && unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    var macMixedFontRuns: [MacMixedFontRun] {
        var runs: [MacMixedFontRun] = []
        var currentKind: MacMixedFontRun.Kind?
        var currentValue = ""

        for character in self {
            let kind = character.macPreferredFontRunKind(fallback: currentKind)
            if let currentKind, currentKind == kind {
                currentValue.append(character)
            } else {
                if let currentKind, !currentValue.isEmpty {
                    runs.append(MacMixedFontRun(kind: currentKind, value: currentValue))
                }
                currentKind = kind
                currentValue = String(character)
            }
        }

        if let currentKind, !currentValue.isEmpty {
            runs.append(MacMixedFontRun(kind: currentKind, value: currentValue))
        }

        return runs
    }
}

private extension Character {
    func macPreferredFontRunKind(fallback: MacMixedFontRun.Kind?) -> MacMixedFontRun.Kind {
        let scalarValues = unicodeScalars.map(\.value)

        if scalarValues.contains(where: { value in
            switch value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x20000...0x2A6DF,
                 0x2A700...0x2B73F,
                 0x2B740...0x2B81F,
                 0x2B820...0x2CEAF:
                return true
            default:
                return false
            }
        }) {
            return .chinese
        }

        if unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
            return .english
        }

        if unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789.:/-_ '\"").contains($0) }) {
            return .number
        }

        return fallback ?? .chinese
    }
}
