//
//  MacTypography.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

enum RokuricsTextStyle: Equatable, CaseIterable {
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

enum MacTypographyFontDesign: Equatable {
    case defaultSystem
    case serif
    case monospaced

    var swiftUIDesign: Font.Design {
        switch self {
        case .defaultSystem:
            return .default
        case .serif:
            return .serif
        case .monospaced:
            return .monospaced
        }
    }
}

enum MacTypographyFontWeight: Equatable {
    case regular
    case medium
    case semibold
    case bold

    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        }
    }
}

struct MacTypographyTokenSpec: Equatable {
    let size: CGFloat
    let weight: MacTypographyFontWeight
    let design: MacTypographyFontDesign
    let usesMonospacedDigits: Bool

    init(
        size: CGFloat,
        weight: MacTypographyFontWeight,
        design: MacTypographyFontDesign,
        usesMonospacedDigits: Bool = false
    ) {
        self.size = size
        self.weight = weight
        self.design = design
        self.usesMonospacedDigits = usesMonospacedDigits
    }

    var font: Font {
        let font = Font.system(size: size, weight: weight.swiftUIWeight, design: design.swiftUIDesign)
        return usesMonospacedDigits ? font.monospacedDigit() : font
    }
}

struct MacMixedTypographyStyle: Equatable {
    let latin: MacTypographyTokenSpec
    let chinese: MacTypographyTokenSpec
    let number: MacTypographyTokenSpec
    let punctuation: MacTypographyTokenSpec
    let technical: MacTypographyTokenSpec

    init(size: CGFloat, weight: MacTypographyFontWeight) {
        latin = MacTypographyTokenSpec(size: size, weight: weight, design: .serif)
        chinese = MacTypographyTokenSpec(size: size, weight: weight, design: .defaultSystem)
        number = MacTypographyTokenSpec(size: size, weight: weight, design: .serif, usesMonospacedDigits: true)
        punctuation = MacTypographyTokenSpec(size: size, weight: weight, design: .defaultSystem)
        technical = MacTypographyTokenSpec(size: size, weight: weight, design: .monospaced)
    }

    func font(for kind: MacMixedTextRun.Kind) -> Font {
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

enum MacTypography {
    static let pageTitleSpec = MacTypographyTokenSpec(size: 32, weight: .bold, design: .defaultSystem)
    static let chatGreetingSpec = MacTypographyTokenSpec(size: 24, weight: .semibold, design: .defaultSystem)
    static let chatMessageSpec = MacTypographyTokenSpec(size: 15, weight: .regular, design: .defaultSystem)
    static let chatInputSpec = MacTypographyTokenSpec(size: 15, weight: .regular, design: .defaultSystem)

    static func font(for style: RokuricsTextStyle) -> Font {
        switch style {
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

    static func pageTitle(size: CGFloat = pageTitleSpec.size, weight: Font.Weight = pageTitleSpec.weight.swiftUIWeight) -> Font {
        chineseTitle(size: size, weight: weight)
    }

    static func pageSubtitle(size: CGFloat = 14, weight: Font.Weight = .medium) -> Font {
        chineseBody(size: size, weight: weight)
    }

    static func sectionTitle(size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        chineseHeadline(size: size, weight: weight)
    }

    static func cardTitle(size: CGFloat = 16, weight: Font.Weight = .semibold) -> Font {
        chineseHeadline(size: size, weight: weight)
    }

    static func body(size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        chineseBody(size: size, weight: weight)
    }

    static func secondary(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        chineseCaption(size: size, weight: weight)
    }

    static func chatGreeting(size: CGFloat = chatGreetingSpec.size, weight: Font.Weight = chatGreetingSpec.weight.swiftUIWeight) -> Font {
        .system(size: size, weight: weight, design: chatGreetingSpec.design.swiftUIDesign)
    }

    static func chatMessage(size: CGFloat = chatMessageSpec.size, weight: Font.Weight = chatMessageSpec.weight.swiftUIWeight) -> Font {
        .system(size: size, weight: weight, design: chatMessageSpec.design.swiftUIDesign)
    }

    static func chatInput(size: CGFloat = chatInputSpec.size, weight: Font.Weight = chatInputSpec.weight.swiftUIWeight) -> Font {
        .system(size: size, weight: weight, design: chatInputSpec.design.swiftUIDesign)
    }

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

    static func mixedStyle(for style: RokuricsTextStyle) -> MacMixedTypographyStyle {
        switch style {
        case .pageTitle:
            return MacMixedTypographyStyle(size: pageTitleSpec.size, weight: pageTitleSpec.weight)
        case .pageSubtitle:
            return MacMixedTypographyStyle(size: 14, weight: .medium)
        case .sectionTitle:
            return MacMixedTypographyStyle(size: 17, weight: .semibold)
        case .cardTitle:
            return MacMixedTypographyStyle(size: 16, weight: .semibold)
        case .body:
            return MacMixedTypographyStyle(size: 14, weight: .regular)
        case .secondary:
            return MacMixedTypographyStyle(size: 12, weight: .medium)
        case .chatGreeting:
            return MacMixedTypographyStyle(size: chatGreetingSpec.size, weight: chatGreetingSpec.weight)
        case .chatMessage:
            return MacMixedTypographyStyle(size: chatMessageSpec.size, weight: chatMessageSpec.weight)
        case .chatInput:
            return MacMixedTypographyStyle(size: chatInputSpec.size, weight: chatInputSpec.weight)
        case .technical:
            return MacMixedTypographyStyle(size: 13, weight: .semibold)
        }
    }

    static func attributedString(
        for text: String,
        style: MacMixedTypographyStyle,
        forceTechnical: Bool = false
    ) -> AttributedString {
        var result = AttributedString()

        for run in MacMixedTextRun.runs(in: text, forceTechnical: forceTechnical) {
            var segment = AttributedString(run.value)
            segment.font = style.font(for: run.kind)
            result += segment
        }

        return result
    }

    static func applyMixedScriptFonts(
        to attributedString: inout AttributedString,
        style: MacMixedTypographyStyle
    ) {
        var cursor = attributedString.startIndex
        for run in MacMixedTextRun.runs(in: String(attributedString.characters)) {
            let next = attributedString.characters.index(cursor, offsetBy: run.value.count)
            attributedString[cursor..<next].font = style.font(for: run.kind)
            cursor = next
        }
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
    var technicalFont: Font = MacTypography.technical(size: 13, weight: .semibold)

    var body: some View {
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()

        for run in MacMixedTextRun.runs(in: text) {
            var segment = AttributedString(run.value)
            segment.font = font(for: run.kind)
            result += segment
        }

        return result
    }

    private func font(for kind: MacMixedTextRun.Kind) -> Font {
        switch kind {
        case .chinese:
            return chineseFont
        case .latin:
            return englishFont
        case .number:
            return numberFont
        case .punctuation:
            return chineseFont
        case .technical:
            return technicalFont
        }
    }
}

struct RokuricsMixedText: View {
    let text: String
    var style: MacMixedTypographyStyle
    var forceTechnical = false

    init(
        _ text: String,
        style: MacMixedTypographyStyle,
        forceTechnical: Bool = false
    ) {
        self.text = text
        self.style = style
        self.forceTechnical = forceTechnical
    }

    init(
        _ text: String,
        textStyle: RokuricsTextStyle,
        forceTechnical: Bool = false
    ) {
        self.init(text, style: MacTypography.mixedStyle(for: textStyle), forceTechnical: forceTechnical)
    }

    var body: some View {
        Text(MacTypography.attributedString(for: text, style: style, forceTechnical: forceTechnical))
    }
}

struct MacMixedTextRun: Equatable {
    enum Kind: Equatable {
        case latin
        case chinese
        case number
        case punctuation
        case technical
    }

    let kind: Kind
    let value: String

    static func runs(in text: String, forceTechnical: Bool = false) -> [MacMixedTextRun] {
        guard !text.isEmpty else {
            return []
        }
        if forceTechnical {
            return [MacMixedTextRun(kind: .technical, value: text)]
        }

        var runs: [MacMixedTextRun] = []
        var token = ""

        func flushToken() {
            guard !token.isEmpty else {
                return
            }
            appendRuns(for: token, to: &runs)
            token = ""
        }

        for character in text {
            if character.macIsWhitespace {
                flushToken()
                appendRun(kind: .punctuation, value: String(character), to: &runs)
            } else {
                token.append(character)
            }
        }

        flushToken()
        return runs
    }

    private static func appendRuns(for token: String, to runs: inout [MacMixedTextRun]) {
        if token.macLooksTechnicalToken {
            appendRun(kind: .technical, value: token, to: &runs)
            return
        }

        if token.macLooksNumericToken {
            appendRun(kind: .number, value: token, to: &runs)
            return
        }

        if token.macLooksLatinWordToken {
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
            let kind = character.macPreferredMixedTextKind
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

    private static func appendRun(kind: Kind, value: String, to runs: inout [MacMixedTextRun]) {
        guard !value.isEmpty else {
            return
        }

        if let last = runs.last, last.kind == kind {
            runs[runs.count - 1] = MacMixedTextRun(kind: kind, value: last.value + value)
        } else {
            runs.append(MacMixedTextRun(kind: kind, value: value))
        }
    }
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
}

private extension Character {
    var macIsWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    var macPreferredMixedTextKind: MacMixedTextRun.Kind {
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

        if unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return .number
        }

        if unicodeScalars.allSatisfy({ $0.macIsLatinLetter }) {
            return .latin
        }

        return .punctuation
    }
}

private extension String {
    var macLooksNumericToken: Bool {
        let allowed = CharacterSet(charactersIn: "0123456789.:/-_")
        return unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) })
            && unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    var macLooksLatinWordToken: Bool {
        let connectorScalars = CharacterSet(charactersIn: "'’-")
        return unicodeScalars.contains(where: \.macIsLatinLetter)
            && unicodeScalars.allSatisfy { $0.macIsLatinLetter || CharacterSet.decimalDigits.contains($0) || connectorScalars.contains($0) }
    }

    var macLooksTechnicalToken: Bool {
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
        if lowered.range(of: #"^([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]{2,5})?$"#, options: .regularExpression) != nil {
            return true
        }
        if lowered.range(of: #"^[a-z0-9.-]+:[0-9]{2,5}$"#, options: .regularExpression) != nil,
           lowered.unicodeScalars.contains(where: \.macIsLatinLetter) {
            return true
        }
        if lowered.hasPrefix("/") || lowered.hasPrefix("~") {
            return true
        }

        let knownPathPrefixes = ["audio/", "transcripts/", "notes/", "study/", "models/", "chats/", "attachments/"]
        if knownPathPrefixes.contains(where: { lowered.hasPrefix($0) }) {
            return true
        }
        if lowered.contains("/"),
           lowered.unicodeScalars.contains(where: \.macIsLatinLetter) || lowered.contains(".") {
            return true
        }
        if lowered.range(of: #"^[a-z0-9_-]+\.[a-z0-9]{1,8}$"#, options: .regularExpression) != nil,
           lowered.unicodeScalars.contains(where: \.macIsLatinLetter) {
            return true
        }

        let technicalPrefixes = [
            "recording", "transcript", "note", "chat", "conversation", "request",
            "folder", "item", "log", "cert", "hash", "fingerprint"
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
    var macIsLatinLetter: Bool {
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
