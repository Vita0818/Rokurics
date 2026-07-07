//
//  RokuricsStudyDocumentViews.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import Foundation
import SwiftUI

struct RokuricsDocumentMetadataRow: Identifiable, Equatable {
    var id: String { "\(label)-\(value)" }
    let label: String
    let value: String
    var isTechnical: Bool = false

    init(_ label: String, _ value: String?, isTechnical: Bool = false) {
        self.label = label
        self.value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.isTechnical = isTechnical
    }

    var isVisible: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum RokuricsDocumentFormatting {
    static func dateTime(_ date: Date?) -> String? {
        guard let date else { return nil }
        return dateFormatter.string(from: date)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func mode(_ mode: ProcessingMode?) -> String? {
        mode?.rawValue
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = RokuricsCopy.displayLocale
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

enum RokuricsProviderDisplayName {
    static func transcription(_ rawValue: String?) -> String? {
        guard let normalized = normalized(rawValue) else { return nil }
        let lower = normalized.lowercased()
        if lower.contains("whisper") {
            return "whisper.cpp"
        }
        if lower.contains("mock") {
            return "Mock"
        }
        return normalized
    }

    static func note(_ rawValue: String?) -> String? {
        guard let normalized = normalized(rawValue) else { return nil }
        let lower = normalized.lowercased()
        if lower.contains("openai") || lower.contains("openai-compatible") {
            return "OpenAI-compatible"
        }
        if lower.contains("anthropic") || lower.contains("claude") {
            return "Claude / Anthropic"
        }
        if lower.contains("mock") {
            return "Mock"
        }
        return normalized
    }

    private static func normalized(_ rawValue: String?) -> String? {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

enum RokuricsModelDisplayName {
    static func friendly(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if looksLikePath(value) {
            return URL(fileURLWithPath: value).lastPathComponent
        }

        return value
    }

    private static func looksLikePath(_ value: String) -> Bool {
        value.hasPrefix("/")
            || value.contains("/models/")
            || value.contains("/Models/")
            || value.contains("\\")
            || (value.contains("/") && (value.hasSuffix(".bin") || value.hasSuffix(".gguf") || value.hasSuffix(".mlmodel")))
    }
}

struct RokuricsDocumentContentCard<Content: View>: View {
    var title: String? = nil
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: title == nil ? 0 : 14) {
            if let title {
                RokuricsText(title, token: .sectionTitle)
                    .foregroundStyle(RokuricsColors.deepText)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsLiquidGlassCard(cornerRadius: 22, fillOpacity: 0.32, strokeOpacity: 0.26, shadowOpacity: 0.04, shadowRadius: 9, shadowY: 4)
    }
}

struct RokuricsDocumentInfoSheet: View {
    let primaryRows: [RokuricsDocumentMetadataRow]
    let advancedRows: [RokuricsDocumentMetadataRow]
    @State private var isAdvancedExpanded = false

    var body: some View {
        NavigationStack {
            ZStack {
                RokuricsColors.pageGradient
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        infoGroup(title: RokuricsCopy.text("基础信息", "Info"), rows: primaryRows.filter(\.isVisible))

                        if !advancedRows.filter(\.isVisible).isEmpty {
                            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                                documentRows(advancedRows.filter(\.isVisible))
                                    .padding(.top, 10)
                            } label: {
                                RokuricsText(RokuricsCopy.text("高级信息", "Details"), token: .sectionTitle)
                                    .foregroundStyle(RokuricsColors.deepText)
                            }
                            .tint(RokuricsColors.softText)
                            .padding(18)
                            .rokuricsLiquidGlassCard(cornerRadius: 20, fillOpacity: 0.24, strokeOpacity: 0.20, shadowOpacity: 0.03, shadowRadius: 7, shadowY: 3)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(RokuricsCopy.text("信息", "Info"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func infoGroup(title: String, rows: [RokuricsDocumentMetadataRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                RokuricsText(title, token: .sectionTitle)
                    .foregroundStyle(RokuricsColors.deepText)
                documentRows(rows)
            }
            .padding(18)
            .rokuricsLiquidGlassCard(cornerRadius: 20, fillOpacity: 0.32, strokeOpacity: 0.26, shadowOpacity: 0.04, shadowRadius: 9, shadowY: 4)
        }
    }

    private func documentRows(_ rows: [RokuricsDocumentMetadataRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(RokuricsColors.glassStroke.opacity(0.30))
                        .frame(height: 1)
                        .padding(.leading, 18)
                }

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(row.label)
                        .font(RokuricsTypography.font(for: .secondary))
                        .foregroundStyle(RokuricsColors.softText)
                        .frame(width: 92, alignment: .leading)

                    RokuricsText(row.value, token: row.isTechnical ? .technical : .body, forceTechnical: row.isTechnical)
                        .foregroundStyle(RokuricsColors.deepText)
                        .lineLimit(row.isTechnical ? 2 : 1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.vertical, 11)
            }
        }
    }
}

enum RokuricsMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(String)
    case paragraph(String)
}

enum RokuricsMarkdownRenderer {
    static func blocks(from markdown: String) -> [RokuricsMarkdownBlock] {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .compactMap { line -> RokuricsMarkdownBlock? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return nil
                }

                if trimmed.hasPrefix("### ") {
                    return .heading(level: 3, text: String(trimmed.dropFirst(4)).trimmedDocumentText)
                }
                if trimmed.hasPrefix("## ") {
                    return .heading(level: 2, text: String(trimmed.dropFirst(3)).trimmedDocumentText)
                }
                if trimmed.hasPrefix("# ") {
                    return .heading(level: 1, text: String(trimmed.dropFirst(2)).trimmedDocumentText)
                }
                if trimmed.hasPrefix("- ") {
                    return .bullet(String(trimmed.dropFirst(2)).trimmedDocumentText)
                }
                if trimmed.hasPrefix("* ") {
                    return .bullet(String(trimmed.dropFirst(2)).trimmedDocumentText)
                }

                return .paragraph(trimmed.trimmedDocumentText)
            }
            .filter { block in
                switch block {
                case .heading(_, let text), .bullet(let text), .paragraph(let text):
                    return !text.isEmpty
                }
            }
    }
}

struct RokuricsMarkdownContentView: View {
    let markdown: String

    var body: some View {
        let blocks = RokuricsMarkdownRenderer.blocks(from: markdown)

        if blocks.isEmpty {
            Text(RokuricsCopy.text("暂无内容", "No content"))
                .font(RokuricsTypography.font(for: .body))
                .foregroundStyle(RokuricsColors.softText)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func blockView(_ block: RokuricsMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            RokuricsText(text, token: .sectionTitle, size: level == 1 ? 20 : 17, weight: .semibold)
                .foregroundStyle(RokuricsColors.deepText)
                .padding(.top, level == 1 ? 2 : 8)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("•")
                    .font(RokuricsTypography.body(size: 15, weight: .semibold))
                    .foregroundStyle(RokuricsColors.aqua)
                RokuricsText(text, token: .body)
                    .foregroundStyle(RokuricsColors.deepText)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .paragraph(let text):
            RokuricsText(text, token: .body)
                .foregroundStyle(RokuricsColors.deepText)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum RokuricsTranscriptMarkdownCleaner {
    static func cleanedBody(from markdown: String) -> String {
        let lines = normalizedLines(markdown)
        if let transcriptIndex = headingIndex(named: "Transcript", in: lines) {
            let start = transcriptIndex + 1
            let end = lines[start...].firstIndex { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("## ")
            } ?? lines.endIndex
            let body = lines[start..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                return body
            }
        }

        return lines
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return true }
                if trimmed.hasPrefix("# ") { return false }
                if trimmed == "## Transcript" || trimmed == "## Segments" { return false }
                if isTranscriptMetadataLine(trimmed) { return false }
                if trimmed.range(of: #"^- \[\d{2}:\d{2}.*\]"#, options: .regularExpression) != nil { return false }
                return true
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func metadata(from markdown: String) -> [String: String] {
        var metadata: [String: String] = [:]
        for line in normalizedLines(markdown) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = value(after: "- Provider:", in: trimmed) {
                metadata["provider"] = value
            } else if let value = value(after: "- Transcribed At:", in: trimmed) {
                metadata["transcribedAt"] = value
            } else if let value = value(after: "- Language:", in: trimmed) {
                metadata["language"] = value
            }
        }
        return metadata
    }

    private static func headingIndex(named name: String, in lines: [String]) -> Int? {
        lines.firstIndex { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "## \(name.lowercased())"
        }
    }

    private static func isTranscriptMetadataLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.hasPrefix("- provider:")
            || lower.hasPrefix("- transcribed at:")
            || lower.hasPrefix("- language:")
            || lower.hasPrefix("- model:")
    }
}

enum RokuricsNoteMarkdownCleaner {
    static func cleanedBody(from markdown: String) -> String {
        var lines = normalizedLines(markdown)
        dropLeadingTitleAndMetadata(from: &lines)
        dropLeadingBasicInfoSection(from: &lines)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func metadata(from markdown: String) -> [String: String] {
        var metadata: [String: String] = [:]
        for line in normalizedLines(markdown) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = value(after: "> Provider:", in: trimmed) {
                metadata["provider"] = value
            } else if let value = value(after: "> Model:", in: trimmed) {
                metadata["model"] = value
            } else if let value = value(after: "- Provider:", in: trimmed) {
                metadata["provider"] = value
            } else if let value = value(after: "- Model:", in: trimmed) {
                metadata["model"] = value
            } else if let value = value(after: "- 笔记 Provider：", in: trimmed) {
                metadata["provider"] = value
            } else if let value = value(after: "- 生成时间：", in: trimmed) {
                metadata["generatedAt"] = value
            } else if let value = value(after: "- Mode:", in: trimmed) {
                metadata["mode"] = value
            } else if let value = value(after: "- Sections:", in: trimmed) {
                metadata["sections"] = value
            } else if let value = value(after: "- 转写来源：", in: trimmed) {
                metadata["sourceTranscript"] = value
            }
        }
        return metadata
    }

    private static func dropLeadingTitleAndMetadata(from lines: inout [String]) {
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "# 录音笔记" {
            lines.removeFirst()
        }
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        while let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines), first.hasPrefix(">") {
            lines.removeFirst()
        }
        while let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              first.hasPrefix("- "),
              first.contains(":") {
            lines.removeFirst()
        }
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
    }

    private static func dropLeadingBasicInfoSection(from lines: inout [String]) {
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "## 基本信息" else {
            return
        }
        lines.removeFirst()
        while let first = lines.first {
            let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                break
            }
            lines.removeFirst()
        }
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
    }
}

struct TranscriptionResult: Codable, Equatable {
    var providerID: String?
    var providerName: String?
    var modelName: String?
    var language: String?
    var completedAt: Date?
}

enum StudyDocumentLoadResult: Equatable {
    case loading
    case loaded(String)
    case failed(String)
}

struct StudyDocumentLoader {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default, rootURL: URL) {
        self.fileManager = fileManager
        self.rootURL = rootURL.standardizedFileURL
    }

    func loadTranscriptMarkdown(item: StudyItemMetadata) -> StudyDocumentLoadResult {
        let paths = candidateTranscriptMarkdownRelativePaths(for: item)
        guard !paths.isEmpty else {
            return .failed(RokuricsCopy.text("未找到转写文档", "Transcript not found"))
        }

        return loadFirstMarkdown(
            paths: paths,
            missingMessage: RokuricsCopy.text("未找到转写文档", "Transcript not found"),
            failureMessage: RokuricsCopy.text("无法读取转写文档", "Could not read transcript")
        )
    }

    func loadNoteMarkdown(item: StudyItemMetadata) -> StudyDocumentLoadResult {
        guard let path = item.noteRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return .failed(RokuricsCopy.text("未找到笔记文档", "Note not found"))
        }

        return loadFirstMarkdown(
            paths: [path],
            missingMessage: RokuricsCopy.text("未找到笔记文档", "Note not found"),
            failureMessage: RokuricsCopy.text("无法读取笔记文档", "Could not read note")
        )
    }

    func loadTranscriptResult(item: StudyItemMetadata) -> TranscriptionResult? {
        for path in candidateTranscriptJSONRelativePaths(for: item) {
            guard let url = resolvedURL(relativePath: path),
                  fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else {
                continue
            }
            if let result = try? Self.decoder.decode(TranscriptionResult.self, from: data) {
                return result
            }
        }
        return nil
    }

    func loadReceiveRecord(item: StudyItemMetadata) -> RecordingReceiveRecord? {
        guard let receiveRelativePath = item.receiveRelativePath,
              let url = resolvedURL(relativePath: receiveRelativePath),
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? Self.decoder.decode(RecordingReceiveRecord.self, from: data)
    }

    func loadNoteSummaryPreview(item: StudyItemMetadata) -> NoteSummaryPreview? {
        guard let noteRelativePath = item.noteRelativePath,
              let noteURL = resolvedURL(relativePath: noteRelativePath) else {
            return nil
        }

        let summaryURL = noteURL.deletingLastPathComponent().appendingPathComponent("summary.json", isDirectory: false)
        if fileManager.fileExists(atPath: summaryURL.path),
           let data = try? Data(contentsOf: summaryURL),
           let preview = try? Self.decoder.decode(NoteSummaryPreview.self, from: data) {
            return preview
        }

        guard fileManager.fileExists(atPath: noteURL.path),
              let markdown = try? String(contentsOf: noteURL, encoding: .utf8) else {
            return nil
        }

        return NoteSummaryPreview(
            recordingID: item.recordingID ?? item.itemID,
            noteRelativePath: noteRelativePath,
            shortSummary: NoteSummaryPreview.shortSummary(from: markdown) ?? NoteSummaryPreview.fallbackSummary(from: markdown),
            keyPoints: NoteSummaryPreview.keyPoints(from: markdown),
            generatedAt: nil,
            providerDisplayName: nil,
            modelName: nil
        )
    }

    private func loadFirstMarkdown(paths: [String], missingMessage: String, failureMessage: String) -> StudyDocumentLoadResult {
        for path in paths {
            guard let url = resolvedURL(relativePath: path),
                  fileManager.fileExists(atPath: url.path) else {
                continue
            }

            do {
                return .loaded(try String(contentsOf: url, encoding: .utf8))
            } catch {
                return .failed(failureMessage)
            }
        }

        return .failed(missingMessage)
    }

    private func candidateTranscriptMarkdownRelativePaths(for item: StudyItemMetadata) -> [String] {
        var paths: [String] = []
        if let transcriptMarkdownRelativePath = item.transcriptMarkdownRelativePath,
           !transcriptMarkdownRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paths.append(transcriptMarkdownRelativePath)
        }

        if let transcriptRelativePath = item.transcriptRelativePath,
           !transcriptRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let directory = (transcriptRelativePath as NSString).deletingLastPathComponent
            if !directory.isEmpty {
                paths.append((directory as NSString).appendingPathComponent("transcript.md"))
            }
        }

        return unique(paths)
    }

    private func candidateTranscriptJSONRelativePaths(for item: StudyItemMetadata) -> [String] {
        var paths: [String] = []
        if let transcriptRelativePath = item.transcriptRelativePath,
           !transcriptRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paths.append(transcriptRelativePath)
        }

        if let transcriptMarkdownRelativePath = item.transcriptMarkdownRelativePath,
           !transcriptMarkdownRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let directory = (transcriptMarkdownRelativePath as NSString).deletingLastPathComponent
            if !directory.isEmpty {
                paths.append((directory as NSString).appendingPathComponent("transcript.json"))
            }
        }

        return unique(paths)
    }

    private func unique(_ paths: [String]) -> [String] {
        var uniquePaths: [String] = []
        for path in paths where !uniquePaths.contains(path) {
            uniquePaths.append(path)
        }
        return uniquePaths
    }

    func resolvedURL(relativePath: String) -> URL? {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty, !trimmedPath.hasPrefix("/") else {
            return nil
        }

        let url = rootURL.appendingPathComponent(trimmedPath, isDirectory: false).standardizedFileURL
        return isInsideRoot(url) ? url : nil
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = rootURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct NoteSummaryPreview: Codable, Equatable {
    let recordingID: String
    let noteRelativePath: String
    let shortSummary: String
    let keyPoints: [String]
    let generatedAt: Date?
    let providerDisplayName: String?
    let modelName: String?

    var isVisible: Bool {
        !shortSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !keyPoints.isEmpty
    }

    nonisolated static func shortSummary(from markdown: String) -> String? {
        let summaryLines = section(named: "摘要", in: markdown)
        let text = previewText(from: summaryLines, maxCharacters: 220)
        return text.isEmpty ? nil : text
    }

    nonisolated static func fallbackSummary(from markdown: String) -> String {
        let text = previewText(from: readableBodyLines(from: markdown), maxCharacters: 220)
        return text.isEmpty ? RokuricsCopy.text("暂无摘要", "No summary") : text
    }

    nonisolated static func keyPoints(from markdown: String, maxCount: Int = 4) -> [String] {
        let focusLines = section(named: "重点", in: markdown)
        let bullets = bulletTexts(from: focusLines)
        if !bullets.isEmpty {
            return Array(bullets.prefix(maxCount))
        }

        return Array(bulletTexts(from: readableBodyLines(from: markdown)).prefix(maxCount))
    }

    private nonisolated static func section(named name: String, in markdown: String) -> [String] {
        let lines = markdownLines(markdown)
        guard let startIndex = lines.firstIndex(where: { headingTitle($0) == name }) else {
            return []
        }

        let contentStart = startIndex + 1
        let contentEnd = lines[contentStart...].firstIndex { line in
            headingTitle(line) != nil
        } ?? lines.endIndex
        return Array(lines[contentStart..<contentEnd])
    }

    private nonisolated static func headingTitle(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else {
            return nil
        }

        let title = trimmed
            .drop(while: { $0 == "#" || $0 == " " })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private nonisolated static func previewText(from lines: [String], maxCharacters: Int) -> String {
        let joined = lines
            .compactMap(cleanReadableLine)
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard joined.count > maxCharacters else {
            return joined
        }

        return String(joined.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private nonisolated static func bulletTexts(from lines: [String]) -> [String] {
        lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("- ") {
                return cleanReadableLine(String(trimmed.dropFirst(2)))
            }
            if trimmed.hasPrefix("* ") {
                return cleanReadableLine(String(trimmed.dropFirst(2)))
            }
            return nil
        }
    }

    private nonisolated static func cleanReadableLine(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        if text.hasPrefix(">") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("- ") || text.hasPrefix("* ") {
            text = String(text.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.hasPrefix("#") else {
            return nil
        }

        let lower = text.lowercased()
        let sensitiveMarkers = ["api key", "apikey", "prompt", "response json", "sk-"]
        guard !sensitiveMarkers.contains(where: { lower.contains($0) }) else {
            return nil
        }

        text = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private nonisolated static func readableBodyLines(from markdown: String) -> [String] {
        var lines = markdownLines(markdown)
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# ") == true {
            lines.removeFirst()
        }
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        while let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              first.hasPrefix(">") || (first.hasPrefix("- ") && first.contains(":")) {
            lines.removeFirst()
        }
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        if headingTitle(lines.first ?? "") == "基本信息" {
            lines.removeFirst()
            while let first = lines.first {
                if headingTitle(first) != nil {
                    break
                }
                lines.removeFirst()
            }
        }
        return lines
    }

    private nonisolated static func markdownLines(_ markdown: String) -> [String] {
        normalizedLines(markdown)
    }
}

private nonisolated func normalizedLines(_ markdown: String) -> [String] {
    markdown
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: "\n")
}

private func value(after prefix: String, in line: String) -> String? {
    guard line.hasPrefix(prefix) else {
        return nil
    }
    let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

private extension String {
    var trimmedDocumentText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
    }
}
