//
//  RokuricsTypography.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import SwiftUI

enum RokuricsTypographyToken: Equatable, CaseIterable {
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

enum RokuricsTypography {
    static func font(for token: RokuricsTypographyToken) -> Font {
        switch token {
        case .pageTitle:
            return pageTitle()
        case .pageSubtitle:
            return pageSubtitle()
        case .sectionTitle:
            return sectionTitle()
        case .cardTitle:
            return cardTitle()
        case .body:
            return body()
        case .secondary:
            return secondary()
        case .chatGreeting:
            return chatGreeting()
        case .chatMessage:
            return chatMessage()
        case .chatInput:
            return chatInput()
        case .technical:
            return technical()
        }
    }

    static func pageTitle(size: CGFloat = 34, weight: Font.Weight = .bold) -> Font {
        chineseTitle(size: size, weight: weight)
    }

    static func pageSubtitle(size: CGFloat = 14, weight: Font.Weight = .medium) -> Font {
        chineseBody(size: size, weight: weight)
    }

    static func sectionTitle(size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        headline(size: size, weight: weight)
    }

    static func cardTitle(size: CGFloat = 16, weight: Font.Weight = .semibold) -> Font {
        headline(size: size, weight: weight)
    }

    static func secondary(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        caption(size: size, weight: weight)
    }

    static func chatGreeting(size: CGFloat = 24, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func chatMessage(size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        body(size: size, weight: weight)
    }

    static func chatInput(size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        body(size: size, weight: weight)
    }

    static func englishTitle(size: CGFloat = 30, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func chineseTitle(size: CGFloat = 30, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    static func englishBody(size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func englishCaption(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func chineseBody(size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func chineseCaption(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    static func numberBody(size: CGFloat = 15, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif).monospacedDigit()
    }

    static func appTitle(size: CGFloat = 39, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func largeNumber(size: CGFloat = 42, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func title(size: CGFloat = 30, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    static func headline(size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func body(size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func caption(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    static func technical(size: CGFloat = 15, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func technicalLarge(size: CGFloat = 24, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func fingerprint(size: CGFloat = 15, weight: Font.Weight = .semibold) -> Font {
        technical(size: size, weight: weight)
    }

    static func button(size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
}

struct RokuricsText: View {
    let text: String
    var token: RokuricsTypographyToken
    var size: CGFloat?
    var weight: Font.Weight?
    var forceTechnical = false

    init(
        _ text: String,
        token: RokuricsTypographyToken = .body,
        size: CGFloat? = nil,
        weight: Font.Weight? = nil,
        forceTechnical: Bool = false
    ) {
        self.text = text
        self.token = token
        self.size = size
        self.weight = weight
        self.forceTechnical = forceTechnical
    }

    var body: some View {
        Text(RokuricsTypography.attributedString(for: text, token: token, size: size, weight: weight, forceTechnical: forceTechnical))
    }
}

struct RokuricsMixedTypographyStyle: Equatable {
    let latin: RokuricsTypographyTokenSpec
    let chinese: RokuricsTypographyTokenSpec
    let number: RokuricsTypographyTokenSpec
    let punctuation: RokuricsTypographyTokenSpec
    let technical: RokuricsTypographyTokenSpec

    init(size: CGFloat, weight: Font.Weight) {
        latin = RokuricsTypographyTokenSpec(size: size, weight: weight, design: .serif)
        chinese = RokuricsTypographyTokenSpec(size: size, weight: weight, design: .default)
        number = RokuricsTypographyTokenSpec(size: size, weight: weight, design: .serif, usesMonospacedDigits: true)
        punctuation = RokuricsTypographyTokenSpec(size: size, weight: weight, design: .default)
        technical = RokuricsTypographyTokenSpec(size: size, weight: weight, design: .monospaced)
    }

    func font(for kind: RokuricsMixedTextRun.Kind) -> Font {
        switch kind {
        case .latin:
            return latin.font
        case .chinese:
            return chinese.font
        case .number:
            return number.font
        case .punctuation:
            return punctuation.font
        case .technical:
            return technical.font
        }
    }
}

struct RokuricsTypographyTokenSpec: Equatable {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    var usesMonospacedDigits = false

    var font: Font {
        let font = Font.system(size: size, weight: weight, design: design)
        return usesMonospacedDigits ? font.monospacedDigit() : font
    }
}

extension RokuricsTypography {
    static func mixedStyle(
        for token: RokuricsTypographyToken,
        size overrideSize: CGFloat? = nil,
        weight overrideWeight: Font.Weight? = nil
    ) -> RokuricsMixedTypographyStyle {
        let fallback: (CGFloat, Font.Weight)
        switch token {
        case .pageTitle:
            fallback = (34, .bold)
        case .pageSubtitle:
            fallback = (14, .medium)
        case .sectionTitle:
            fallback = (17, .semibold)
        case .cardTitle:
            fallback = (16, .semibold)
        case .body:
            fallback = (15, .regular)
        case .secondary:
            fallback = (12, .medium)
        case .chatGreeting:
            fallback = (24, .semibold)
        case .chatMessage, .chatInput:
            fallback = (15, .regular)
        case .technical:
            fallback = (15, .semibold)
        }

        return RokuricsMixedTypographyStyle(
            size: overrideSize ?? fallback.0,
            weight: overrideWeight ?? fallback.1
        )
    }

    static func attributedString(
        for text: String,
        token: RokuricsTypographyToken,
        size: CGFloat? = nil,
        weight: Font.Weight? = nil,
        forceTechnical: Bool = false
    ) -> AttributedString {
        let style = mixedStyle(for: token, size: size, weight: weight)
        var result = AttributedString()
        for run in RokuricsMixedTextRun.runs(in: text, forceTechnical: forceTechnical || token == .technical) {
            var segment = AttributedString(run.value)
            segment.font = style.font(for: run.kind)
            result += segment
        }
        return result
    }
}

struct RokuricsMixedTextRun: Equatable {
    enum Kind: Equatable {
        case latin
        case chinese
        case number
        case punctuation
        case technical
    }

    let kind: Kind
    let value: String

    static func runs(in text: String, forceTechnical: Bool = false) -> [RokuricsMixedTextRun] {
        guard !text.isEmpty else {
            return []
        }
        if forceTechnical {
            return [RokuricsMixedTextRun(kind: .technical, value: text)]
        }

        var runs: [RokuricsMixedTextRun] = []
        var token = ""

        func flushToken() {
            guard !token.isEmpty else {
                return
            }
            appendRuns(for: token, to: &runs)
            token = ""
        }

        for character in text {
            if character.rokuricsIsWhitespace {
                flushToken()
                appendRun(kind: .punctuation, value: String(character), to: &runs)
            } else {
                token.append(character)
            }
        }

        flushToken()
        return runs
    }

    private static func appendRuns(for token: String, to runs: inout [RokuricsMixedTextRun]) {
        if token.rokuricsLooksTechnicalToken {
            appendRun(kind: .technical, value: token, to: &runs)
            return
        }

        if token.rokuricsLooksNumericToken {
            appendRun(kind: .number, value: token, to: &runs)
            return
        }

        if token.rokuricsLooksLatinWordToken {
            appendRun(kind: .latin, value: token, to: &runs)
            return
        }

        var currentKind: Kind?
        var currentValue = ""

        func flushCurrent() {
            guard let currentKind, !currentValue.isEmpty else {
                return
            }
            appendRun(kind: currentKind, value: currentValue, to: &runs)
            currentValue = ""
        }

        for character in token {
            let kind = character.rokuricsPreferredMixedTextKind
            if currentKind == kind {
                currentValue.append(character)
            } else {
                flushCurrent()
                currentKind = kind
                currentValue = String(character)
            }
        }

        flushCurrent()
    }

    private static func appendRun(kind: Kind, value: String, to runs: inout [RokuricsMixedTextRun]) {
        guard !value.isEmpty else {
            return
        }

        if let last = runs.last, last.kind == kind {
            runs[runs.count - 1] = RokuricsMixedTextRun(kind: kind, value: last.value + value)
        } else {
            runs.append(RokuricsMixedTextRun(kind: kind, value: value))
        }
    }
}

struct RokuricsInlineTextFragment: Equatable, Identifiable {
    enum Kind: Equatable {
        case normal(RokuricsTypographyToken)
        case technical
    }

    let text: String
    let kind: Kind

    var id: String {
        "\(kind.identifier):\(text)"
    }

    static func text(_ value: String, token: RokuricsTypographyToken = .body) -> RokuricsInlineTextFragment {
        RokuricsInlineTextFragment(text: value, kind: .normal(token))
    }

    static func technical(_ value: String) -> RokuricsInlineTextFragment {
        RokuricsInlineTextFragment(text: value, kind: .technical)
    }
}

private extension RokuricsInlineTextFragment.Kind {
    var identifier: String {
        switch self {
        case .normal(let token):
            return "normal-\(token)"
        case .technical:
            return "technical"
        }
    }
}

struct RokuricsMixedTypographyText: View {
    let fragments: [RokuricsInlineTextFragment]

    var body: some View {
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()

        for fragment in fragments {
            var segment = AttributedString(fragment.text)
            segment.font = font(for: fragment.kind)
            result += segment
        }

        return result
    }

    private func font(for kind: RokuricsInlineTextFragment.Kind) -> Font {
        switch kind {
        case .normal(let token):
            return RokuricsTypography.font(for: token)
        case .technical:
            return RokuricsTypography.font(for: .technical)
        }
    }
}

struct RokuricsTechnicalInlineText: View {
    let prefix: String
    let technical: String
    var suffix = ""

    var body: some View {
        RokuricsMixedTypographyText(
            fragments: [
                .text(prefix),
                .technical(technical),
                .text(suffix)
            ].filter { !$0.text.isEmpty }
        )
    }
}

struct RokuricsPathTextView: View {
    let path: String

    var body: some View {
        RokuricsMixedTypographyText(fragments: [.technical(path)])
    }
}

struct RokuricsMixedLanguageTitle: View {
    let english: String
    let chinese: String
    var englishSize: CGFloat = 34
    var chineseSize: CGFloat = 34
    var weight: Font.Weight = .bold

    var body: some View {
        if RokuricsCopy.usesChinese {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(english)
                    .font(RokuricsTypography.englishTitle(size: englishSize, weight: weight))

                Text(chinese)
                    .font(RokuricsTypography.chineseTitle(size: chineseSize, weight: weight))
            }
        } else {
            Text(english)
                .font(RokuricsTypography.englishTitle(size: englishSize, weight: weight))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
    }
}

struct RokuricsMixedFontText: View {
    let text: String
    var chineseFont: Font
    var englishFont: Font
    var numberFont: Font

    init(
        text: String,
        chineseFont: Font = RokuricsTypography.chineseBody(size: 15),
        englishFont: Font = RokuricsTypography.englishBody(size: 15),
        numberFont: Font = RokuricsTypography.numberBody(size: 15, weight: .regular)
    ) {
        self.text = text
        self.chineseFont = chineseFont
        self.englishFont = englishFont
        self.numberFont = numberFont
    }

    var body: some View {
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()

        for run in text.rokuricsMixedFontRuns {
            var attributedRun = AttributedString(run.text)
            attributedRun.font = font(for: run.kind)
            result.append(attributedRun)
        }

        return result
    }

    private func font(for kind: RokuricsMixedFontRun.Kind) -> Font {
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

private struct RokuricsMixedFontRun {
    enum Kind {
        case chinese
        case english
        case number
    }

    let text: String
    let kind: Kind
}

private extension String {
    var rokuricsMixedFontRuns: [RokuricsMixedFontRun] {
        var runs: [RokuricsMixedFontRun] = []
        var currentKind: RokuricsMixedFontRun.Kind?
        var currentText = ""

        for character in self {
            let kind = character.rokuricsPreferredFontRunKind
            if let currentKind, currentKind == kind {
                currentText.append(character)
            } else {
                if let currentKind, !currentText.isEmpty {
                    runs.append(RokuricsMixedFontRun(text: currentText, kind: currentKind))
                }
                currentKind = kind
                currentText = String(character)
            }
        }

        if let currentKind, !currentText.isEmpty {
            runs.append(RokuricsMixedFontRun(text: currentText, kind: currentKind))
        }

        return runs
    }
}

private extension Character {
    var rokuricsPreferredFontRunKind: RokuricsMixedFontRun.Kind {
        if rokuricsContainsCJKScalar {
            return .chinese
        }

        if unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return .number
        }

        if unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
            return .english
        }

        if unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
            return .chinese
        }

        return .chinese
    }

    private var rokuricsContainsCJKScalar: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF,
                 0x3400...0x4DBF,
                 0x3040...0x30FF,
                 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }
}

private extension Character {
    var rokuricsIsWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    var rokuricsPreferredMixedTextKind: RokuricsMixedTextRun.Kind {
        if rokuricsContainsCJKScalar {
            return .chinese
        }

        if unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return .number
        }

        if unicodeScalars.allSatisfy({ $0.rokuricsIsLatinLetter }) {
            return .latin
        }

        return .punctuation
    }
}

private extension String {
    var rokuricsLooksNumericToken: Bool {
        let allowed = CharacterSet(charactersIn: "0123456789.:/-_")
        return unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) })
            && unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    var rokuricsLooksLatinWordToken: Bool {
        let connectorScalars = CharacterSet(charactersIn: "'’-")
        return unicodeScalars.contains(where: \.rokuricsIsLatinLetter)
            && unicodeScalars.allSatisfy { $0.rokuricsIsLatinLetter || CharacterSet.decimalDigits.contains($0) || connectorScalars.contains($0) }
    }

    var rokuricsLooksTechnicalToken: Bool {
        let trimmed = trimmingCharacters(in: CharacterSet(charactersIn: " \t\n,，.。;；)）]】}」』!！?？"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "([{（【「『"))
        guard !trimmed.isEmpty else {
            return false
        }

        let lowered = trimmed.lowercased()
        if lowered.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: .regularExpression) != nil {
            return true
        }
        if lowered.range(of: #"^[0-9a-f]{16,}$"#, options: .regularExpression) != nil {
            return true
        }
        if lowered.range(of: #"^([0-9a-f]{2}:){5,}[0-9a-f]{2}$"#, options: .regularExpression) != nil {
            return true
        }
        if lowered.hasPrefix("/") || lowered.hasPrefix("~") {
            return true
        }

        let knownPathPrefixes = ["audio/", "recordings/", "transcripts/", "notes/", "study/", "metadata/"]
        if knownPathPrefixes.contains(where: { lowered.hasPrefix($0) }) {
            return true
        }
        if lowered.contains("/"),
           lowered.unicodeScalars.contains(where: \.rokuricsIsLatinLetter) || lowered.contains(".") {
            return true
        }
        if lowered.range(of: #"^[a-z0-9_-]+\.[a-z0-9]{1,8}$"#, options: .regularExpression) != nil,
           lowered.unicodeScalars.contains(where: \.rokuricsIsLatinLetter) {
            return true
        }

        let technicalPrefixes = [
            "recording", "transcript", "note", "folder", "item",
            "hash", "fingerprint", "endpoint"
        ]
        for prefix in technicalPrefixes {
            if lowered.range(of: #"^\#(prefix)[-_][a-z0-9][a-z0-9_-]*$"#, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }
}

private extension UnicodeScalar {
    var rokuricsIsLatinLetter: Bool {
        switch value {
        case 0x0041...0x005A,
             0x0061...0x007A,
             0x00C0...0x024F:
            return true
        default:
            return false
        }
    }
}
