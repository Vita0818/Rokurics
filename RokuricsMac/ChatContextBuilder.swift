//
//  ChatContextBuilder.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/20.
//

import Foundation

struct ChatContextBuildOptions: Equatable {
    var maxContextCharacters: Int = 20_000
    var maxCharactersPerItem: Int = 2_000
    var maxNoteCharacters: Int = 1_600
    var maxTranscriptCharacters: Int = 1_200
}

struct StudyLibraryContextExporter {
    private let rootURL: URL
    private let fileManager: FileManager
    private let options: ChatContextBuildOptions

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        options: ChatContextBuildOptions = ChatContextBuildOptions()
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        self.options = options
    }

    func export(items: [StudyItemMetadata], path: StudyBrowsePath) -> ChatContext {
        let matchingItems = items
            .filter { StudyLibraryBrowser.itemMatches($0, path: path) }
            .sorted { left, right in
                if left.createdAt == right.createdAt {
                    return left.title.localizedStandardCompare(right.title) == .orderedAscending
                }
                return left.createdAt > right.createdAt
            }

        return ChatContextBuilder(rootURL: rootURL, fileManager: fileManager, options: options)
            .build(title: Self.contextTitle(for: path), browsePath: path, items: matchingItems)
    }

    func export(item: StudyItemMetadata) -> ChatContext {
        ChatContextBuilder(rootURL: rootURL, fileManager: fileManager, options: options)
            .build(item: item)
    }

    static func contextTitle(for path: StudyBrowsePath) -> String {
        path.components.last ?? "学习库"
    }
}

struct ChatContextBuilder {
    private let rootURL: URL
    private let fileManager: FileManager
    private let noteStore: NoteStore
    private let options: ChatContextBuildOptions

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        options: ChatContextBuildOptions = ChatContextBuildOptions()
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        self.noteStore = NoteStore(fileManager: fileManager, rootURL: rootURL)
        self.options = options
    }

    func build(title: String, browsePath: StudyBrowsePath, items: [StudyItemMetadata]) -> ChatContext {
        var contextItems: [ChatContextItem] = []
        var remainingCharacters = max(0, options.maxContextCharacters)
        var totalCharacters = 0
        var contextWasTruncated = false

        for item in items {
            guard remainingCharacters > 0 else {
                contextWasTruncated = true
                break
            }

            let draft = contentDraft(for: item)
            let itemLimit = min(options.maxCharactersPerItem, remainingCharacters)
            let limitedContent = Self.limited(draft.content, to: itemLimit)
            let wasTruncated = draft.content.count > limitedContent.count
            let trimmedContent = limitedContent.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedContent.isEmpty else {
                continue
            }

            contextItems.append(
                ChatContextItem(
                    id: item.itemID,
                    title: item.title,
                    filingPath: item.filingPath,
                    content: trimmedContent,
                    sourcePath: draft.sourceLabel,
                    contentCharacterCount: trimmedContent.count,
                    isTruncated: wasTruncated
                )
            )
            remainingCharacters -= trimmedContent.count
            totalCharacters += trimmedContent.count
            contextWasTruncated = contextWasTruncated || wasTruncated
        }

        if contextItems.count < items.count {
            contextWasTruncated = true
        }

        return ChatContext(
            title: title,
            browsePathComponents: browsePath.components,
            itemCount: items.count,
            items: contextItems,
            sourceKind: .studyLibrary,
            contextPathDisplay: Self.pathDisplay(components: browsePath.components),
            maxContextCharacters: options.maxContextCharacters,
            totalCharacterCount: totalCharacters,
            isTruncated: contextWasTruncated
        )
    }

    func build(item: StudyItemMetadata) -> ChatContext {
        let draft = contentDraft(for: item)
        let itemLimit = min(options.maxCharactersPerItem, options.maxContextCharacters)
        let limitedContent = Self.limited(draft.content, to: itemLimit)
        let trimmedContent = limitedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasTruncated = draft.content.count > trimmedContent.count
        let browsePathComponents = Self.browsePathComponents(for: item.filingPath)
        let contextPathDisplay = Self.pathDisplay(components: browsePathComponents + [item.title])
        let contextItems = [
            ChatContextItem(
                id: item.itemID,
                title: item.title,
                filingPath: item.filingPath,
                content: trimmedContent,
                sourcePath: draft.sourceLabel,
                contentCharacterCount: trimmedContent.count,
                isTruncated: wasTruncated
            )
        ].filter { !$0.content.isEmpty }

        return ChatContext(
            title: item.title,
            browsePathComponents: browsePathComponents,
            itemCount: 1,
            items: contextItems,
            sourceKind: .studyItem,
            sourceItemID: item.itemID,
            contextPathDisplay: contextPathDisplay,
            itemTitle: item.title,
            maxContextCharacters: options.maxContextCharacters,
            totalCharacterCount: trimmedContent.count,
            isTruncated: wasTruncated
        )
    }

    private func contentDraft(for item: StudyItemMetadata) -> (content: String, sourceLabel: String?) {
        if let preview = noteStore.loadSummaryPreview(noteRelativePath: item.noteRelativePath), preview.isVisible {
            let summary = ChatContextTextSanitizer.sanitized(preview.shortSummary)
            let keyPoints = preview.keyPoints
                .map(ChatContextTextSanitizer.sanitized)
                .filter { !$0.isEmpty }
            var lines: [String] = []
            if !summary.isEmpty {
                lines.append("摘要：\(summary)")
            }
            if !keyPoints.isEmpty {
                lines.append("重点：")
                lines.append(contentsOf: keyPoints.map { "- \($0)" })
            }
            let content = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                return (content, "note summary")
            }
        }

        if let noteMarkdown = readText(relativePath: item.noteRelativePath) {
            let preview = markdownPreview(
                from: noteMarkdown,
                preferredHeadings: ["摘要", "大纲", "重点", "关键点", "复习重点"],
                maxCharacters: options.maxNoteCharacters
            )
            if !preview.isEmpty {
                return (preview, "note")
            }
        }

        if let transcriptMarkdown = readText(relativePath: item.transcriptMarkdownRelativePath ?? item.transcriptRelativePath) {
            let preview = markdownPreview(
                from: transcriptMarkdown,
                preferredHeadings: ["Transcript", "转写", "正文"],
                maxCharacters: options.maxTranscriptCharacters
            )
            if !preview.isEmpty {
                return (preview, "transcript")
            }
        }

        return ("标题：\(item.title)\n路径：\(item.filingPath.displaySummary)", "metadata")
    }

    private func markdownPreview(
        from markdown: String,
        preferredHeadings: [String],
        maxCharacters: Int
    ) -> String {
        let normalizedLines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        let preferredLines = preferredHeadings.flatMap { section(named: $0, in: normalizedLines) }
        let lines = preferredLines.isEmpty ? readableLines(from: normalizedLines) : preferredLines
        let sanitized = ChatContextTextSanitizer.sanitized(lines.joined(separator: "\n"))
        return Self.limited(sanitized, to: maxCharacters).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func section(named headingName: String, in lines: [String]) -> [String] {
        guard let startIndex = lines.firstIndex(where: { Self.headingTitle($0) == headingName }) else {
            return []
        }

        let contentStart = startIndex + 1
        let contentEnd = lines[contentStart...].firstIndex { Self.headingTitle($0) != nil } ?? lines.endIndex
        return Array(lines[contentStart..<contentEnd])
    }

    private func readableLines(from lines: [String]) -> [String] {
        lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return false
            }
            guard Self.headingTitle(trimmed) == nil else {
                return false
            }

            let lower = trimmed.lowercased()
            return !lower.hasPrefix("- provider:")
                && !lower.hasPrefix("- transcribed at:")
                && !lower.hasPrefix("- language:")
        }
    }

    private func readText(relativePath: String?) -> String? {
        guard let url = resolvedRootFileURL(relativePath: relativePath),
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func resolvedRootFileURL(relativePath: String?) -> URL? {
        guard let trimmedPath = relativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("/") else {
            return nil
        }

        let url = rootURL.appendingPathComponent(trimmedPath, isDirectory: false).standardizedFileURL
        return isInsideRoot(url) ? url : nil
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private static func headingTitle(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else {
            return nil
        }

        let title = trimmed
            .drop(while: { $0 == "#" || $0 == " " })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func limited(_ text: String, to maxCharacters: Int) -> String {
        guard maxCharacters > 0 else {
            return ""
        }
        guard text.count > maxCharacters else {
            return text
        }

        guard maxCharacters > 3 else {
            return String(text.prefix(maxCharacters))
        }

        return String(text.prefix(maxCharacters - 3)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func browsePathComponents(for filingPath: StudyFilingPath) -> [String] {
        [filingPath.type, filingPath.subject, filingPath.chapter, filingPath.topic]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func pathDisplay(components: [String]) -> String {
        (["学习库"] + components)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }
}

enum ChatContextTextSanitizer {
    nonisolated static func sanitized(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                let lower = line.lowercased()
                return !sensitiveMarkers.contains { lower.contains($0) }
            }

        return redactSecrets(in: lines.joined(separator: "\n"))
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func redactSecrets(in text: String) -> String {
        text.replacingOccurrences(
            of: #"sk-[A-Za-z0-9_\-]{6,}"#,
            with: "[redacted]",
            options: .regularExpression
        )
    }

    nonisolated private static let sensitiveMarkers = [
        "api key",
        "apikey",
        "api_key",
        "authorization",
        "bearer ",
        "x-api-key",
        "sk-",
        "sharedsecret",
        "shared secret",
        "hmac",
        "pairing",
        "response json",
        "full debug",
        "debug metadata"
    ]
}
