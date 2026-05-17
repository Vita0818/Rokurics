//
//  RecordingTitleEditing.swift
//  Rokurics
//
//  Created by Codex on 2026/5/17.
//

import Foundation

enum RecordingTitleEditRules {
    static let maxTitleLength = 80

    static func normalizedTitle(_ rawTitle: String, fallback: String) -> String {
        let singleLineTitle = rawTitle
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let candidate = singleLineTitle.isEmpty
            ? fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            : singleLineTitle

        let nonEmptyCandidate = candidate.isEmpty ? "未命名录音" : candidate
        guard nonEmptyCandidate.count > maxTitleLength else {
            return nonEmptyCandidate
        }

        return String(nonEmptyCandidate.prefix(maxTitleLength))
    }

    static func shouldSave(rawTitle: String, currentTitle: String) -> Bool {
        normalizedTitle(rawTitle, fallback: currentTitle) != currentTitle
    }
}

enum RecordingLocalOperationCopy {
    static let renameTitle = "重命名录音"
    static let moveToTrashTitle = "移入废纸篓？"
    static let permanentDeleteTitle = "永久删除录音？"
    static let iPhoneMoveToTrashMessage = "这会将 iPhone 上的本地录音移入废纸篓，不会删除 Mac 上已接收的副本。"
    static let iPhonePermanentDeleteMessage = "将永久删除 iPhone 上的音频和元数据，不会删除 Mac 上已接收的副本。"
    static let renameFailure = "名称保存失败"
    static let deleteFailure = "删除失败"
    static let restoreFailure = "恢复失败"
}
