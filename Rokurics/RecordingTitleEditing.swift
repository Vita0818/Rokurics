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

        let nonEmptyCandidate = candidate.isEmpty ? RokuricsCopy.text("未命名录音", "Untitled Recording") : candidate
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
    static var renameTitle: String { RokuricsCopy.text("重命名录音", "Rename Recording") }
    static var moveToTrashTitle: String { RokuricsCopy.text("移入废纸篓？", "Move to Trash?") }
    static var permanentDeleteTitle: String { RokuricsCopy.text("永久删除录音？", "Delete Recording?") }
    static var iPhoneMoveToTrashMessage: String { RokuricsCopy.text("这会将 iPhone 上的本地录音移入废纸篓，不会删除 Mac 上已接收的副本。", "Moves the local iPhone recording to Trash. Mac copies stay untouched.") }
    static var iPhonePermanentDeleteMessage: String { RokuricsCopy.text("将永久删除 iPhone 上的音频和元数据，不会删除 Mac 上已接收的副本。", "Permanently deletes iPhone audio and metadata. Mac copies stay untouched.") }
    static var renameFailure: String { RokuricsCopy.text("名称保存失败", "Could not save name") }
    static var deleteFailure: String { RokuricsCopy.text("删除失败", "Delete failed") }
    static var restoreFailure: String { RokuricsCopy.text("恢复失败", "Restore failed") }
}
