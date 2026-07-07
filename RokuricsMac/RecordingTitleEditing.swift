//
//  RecordingTitleEditing.swift
//  RokuricsMac
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
    static var macMoveToTrashMessage: String { RokuricsCopy.text("这会将 Mac 上的音频和转写移入废纸篓，可稍后恢复或永久删除。", "Moves Mac audio and transcript files to Trash for later restore or delete.") }
    static var macPermanentDeleteMessage: String { RokuricsCopy.text("将永久删除 Mac 上的音频和转写文件，不会删除 iPhone 上的原始录音。", "Permanently deletes Mac audio and transcript files. iPhone originals stay untouched.") }
    static var renameFailure: String { RokuricsCopy.text("名称保存失败", "Could not save name") }
    static var deleteFailure: String { RokuricsCopy.text("删除失败", "Delete failed") }
    static var restoreFailure: String { RokuricsCopy.text("恢复失败", "Restore failed") }
}
