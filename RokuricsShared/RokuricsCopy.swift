//
//  RokuricsCopy.swift
//  Rokurics
//
//  Created by Codex on 2026/7/4.
//

import Foundation

enum RokuricsCopy {
    nonisolated static var usesChinese: Bool {
        if let preferred = Locale.preferredLanguages.first,
           isChineseIdentifier(preferred) {
            return true
        }

        return isChineseIdentifier(Locale.current.identifier)
    }

    nonisolated static var displayLocale: Locale {
        usesChinese ? Locale(identifier: "zh_Hans_CN") : Locale(identifier: "en_US")
    }

    nonisolated static func text(_ chinese: String, _ english: String) -> String {
        usesChinese ? chinese : english
    }

    nonisolated static func itemCount(_ count: Int) -> String {
        if usesChinese {
            return "\(count) 项"
        }

        return "\(count) \(count == 1 ? "item" : "items")"
    }

    nonisolated static func fileCount(_ count: Int) -> String {
        if usesChinese {
            return "\(count) 个文件"
        }

        return "\(count) \(count == 1 ? "file" : "files")"
    }

    nonisolated static func openLabel(_ title: String) -> String {
        usesChinese ? "打开\(title)" : "Open \(title)"
    }

    nonisolated static func chooseLabel(_ title: String) -> String {
        usesChinese ? "选择\(title)" : "Choose \(title)"
    }

    nonisolated static func newLabel(_ title: String) -> String {
        usesChinese ? "新建\(title)" : "New \(title)"
    }

    private nonisolated static func isChineseIdentifier(_ identifier: String) -> Bool {
        let normalized = identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        return normalized == "zh" || normalized.hasPrefix("zh-")
    }
}
