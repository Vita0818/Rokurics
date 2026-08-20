//
//  RokuricsLaTeXFontBoundary.swift
//  Rokurics
//

import Foundation

/// Identifies existing LaTeX-delimited spans so typography changes can leave
/// the formula renderer's current font untouched. This does not parse or render
/// LaTeX; it only preserves the established font boundary.
enum RokuricsLaTeXFontBoundary {
    struct Segment: Equatable {
        let text: String
        let preservesCurrentFont: Bool
    }

    private struct Delimiter {
        let opening: [Character]
        let closing: [Character]
    }

    private static let delimiters = [
        Delimiter(opening: ["$", "$"], closing: ["$", "$"]),
        Delimiter(opening: ["\\", "["], closing: ["\\", "]"]),
        Delimiter(opening: ["\\", "("], closing: ["\\", ")"]),
        Delimiter(opening: ["$"], closing: ["$"])
    ]

    static func segments(in text: String) -> [Segment] {
        let characters = Array(text)
        guard !characters.isEmpty else {
            return []
        }

        var segments: [Segment] = []
        var normalStart = 0
        var cursor = 0

        while cursor < characters.count {
            guard let match = matchingFormula(in: characters, at: cursor) else {
                cursor += 1
                continue
            }

            append(
                characters[normalStart..<cursor],
                preservesCurrentFont: false,
                to: &segments
            )
            append(
                characters[cursor..<match.endIndex],
                preservesCurrentFont: true,
                to: &segments
            )

            cursor = match.endIndex
            normalStart = cursor
        }

        append(
            characters[normalStart..<characters.count],
            preservesCurrentFont: false,
            to: &segments
        )

        return segments
    }

    /// CommonMark consumes a single backslash before `(`, `)`, `[` and `]`.
    /// Doubling only the established LaTeX delimiters keeps those characters
    /// present after `AttributedString(markdown:)` without changing formula
    /// contents or introducing a renderer.
    static func preservingBackslashDelimitersForMarkdown(in text: String) -> String {
        text
            .replacingOccurrences(of: "\\(", with: "\\\\(")
            .replacingOccurrences(of: "\\)", with: "\\\\)")
            .replacingOccurrences(of: "\\[", with: "\\\\[")
            .replacingOccurrences(of: "\\]", with: "\\\\]")
    }

    private static func matchingFormula(
        in characters: [Character],
        at index: Int
    ) -> (endIndex: Int, delimiter: Delimiter)? {
        for delimiter in delimiters {
            guard matches(delimiter.opening, in: characters, at: index) else {
                continue
            }
            if delimiter.opening == ["$"],
               (isEscaped(in: characters, at: index)
                    || matches(["$", "$"], in: characters, at: index)) {
                continue
            }

            var searchIndex = index + delimiter.opening.count
            while searchIndex < characters.count {
                if matches(delimiter.closing, in: characters, at: searchIndex),
                   !isEscapedDollarDelimiter(delimiter.closing, in: characters, at: searchIndex) {
                    return (searchIndex + delimiter.closing.count, delimiter)
                }
                searchIndex += 1
            }
        }

        return nil
    }

    private static func matches(
        _ candidate: [Character],
        in characters: [Character],
        at index: Int
    ) -> Bool {
        guard index >= 0, index + candidate.count <= characters.count else {
            return false
        }

        for offset in candidate.indices where characters[index + offset] != candidate[offset] {
            return false
        }
        return true
    }

    private static func isEscapedDollarDelimiter(
        _ delimiter: [Character],
        in characters: [Character],
        at index: Int
    ) -> Bool {
        delimiter.first == "$" && isEscaped(in: characters, at: index)
    }

    private static func isEscaped(in characters: [Character], at index: Int) -> Bool {
        guard index > 0 else {
            return false
        }

        var slashCount = 0
        var cursor = index - 1
        while cursor >= 0, characters[cursor] == "\\" {
            slashCount += 1
            cursor -= 1
        }
        return slashCount.isMultiple(of: 2) == false
    }

    private static func append(
        _ characters: ArraySlice<Character>,
        preservesCurrentFont: Bool,
        to segments: inout [Segment]
    ) {
        guard !characters.isEmpty else {
            return
        }

        let value = String(characters)
        if let last = segments.last,
           last.preservesCurrentFont == preservesCurrentFont {
            segments[segments.count - 1] = Segment(
                text: last.text + value,
                preservesCurrentFont: preservesCurrentFont
            )
        } else {
            segments.append(
                Segment(text: value, preservesCurrentFont: preservesCurrentFont)
            )
        }
    }
}
