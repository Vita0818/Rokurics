//
//  MacDocumentDetailComponents.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/19.
//

import AppKit
import Foundation
import SwiftUI

enum RokuricsDetailTypography {
    static let pageTitleChinese = MacTypography.pageTitle()
    static let pageTitleEnglish = MacTypography.englishTitle(size: 32, weight: .semibold)
    static let pageTitleNumber = MacTypography.numberTitle(size: 32, weight: .bold)
    static let pageSubtitle = MacTypography.englishCaption(size: 12, weight: .semibold)
    static let cardTitle = MacTypography.cardTitle()
    static let metadataLabel = MacTypography.chineseCaption(size: 12, weight: .semibold)
    static let metadataValue = MacTypography.chineseBody(size: 14, weight: .medium)
    static let metadataTechnicalValue = MacTypography.technical(size: 12, weight: .medium)
    static let body = MacTypography.body(size: 15, weight: .regular)
    static let bodyEmphasis = MacTypography.chineseBody(size: 15, weight: .semibold)

    static func contentHeading(level: Int) -> Font {
        switch level {
        case 1:
            return MacTypography.chineseTitle(size: 20, weight: .semibold)
        case 2:
            return MacTypography.chineseHeadline(size: 17)
        default:
            return MacTypography.chineseBody(size: 16, weight: .semibold)
        }
    }
}

struct RokuricsPageTitle: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MacMixedFontText(
            text: text,
            chineseFont: RokuricsDetailTypography.pageTitleChinese,
            englishFont: RokuricsDetailTypography.pageTitleEnglish,
            numberFont: RokuricsDetailTypography.pageTitleNumber
        )
        .foregroundStyle(MacTheme.deepText(for: colorScheme))
        .lineLimit(2)
    }
}

struct RokuricsPageSubtitle: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(RokuricsDetailTypography.pageSubtitle)
            .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
    }
}

struct RokuricsSectionTitle: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(RokuricsDetailTypography.cardTitle)
            .foregroundStyle(MacTheme.deepText(for: colorScheme))
    }
}

struct RokuricsMetadataLabel: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(RokuricsDetailTypography.metadataLabel)
            .foregroundStyle(MacTheme.softText(for: colorScheme))
    }
}

struct RokuricsMetadataValue: View {
    let text: String
    var isTechnical = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isTechnical && FileRevealService.looksOpenablePath(text) {
            ClickableFilePathView(path: text)
        } else {
            Group {
                if isTechnical {
                    PathTextView(path: text)
                } else {
                    Text(text)
                        .font(RokuricsDetailTypography.metadataValue)
                }
            }
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(isTechnical ? 2 : 1)
                .truncationMode(.middle)
        }
    }
}

enum FileRevealAction: Equatable {
    case open(URL)
    case reveal(URL)
    case missing(URL)
}

enum FileRevealService {
    static func open(path: String, rootURL: URL? = nil, fileManager: FileManager = .default) {
        switch action(for: path, rootURL: rootURL, fileManager: fileManager) {
        case .open(let url):
            NSWorkspace.shared.open(url)
        case .reveal(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .missing:
            NSSound.beep()
        }
    }

    static func action(
        for path: String,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> FileRevealAction {
        let resolvedURL = resolvedURL(for: path, rootURL: rootURL).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) else {
            return .missing(resolvedURL)
        }

        return isDirectory.boolValue ? .open(resolvedURL) : .reveal(resolvedURL)
    }

    static func resolvedURL(for path: String, rootURL: URL? = nil) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("~") {
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }

        let baseURL = rootURL ?? applicationSupportRootURL()
        return baseURL.appendingPathComponent(trimmed, isDirectory: false)
    }

    static func looksOpenablePath(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return true
        }

        let knownPrefixes = ["audio/", "transcripts/", "notes/", "study/", "models/"]
        if knownPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }

        return trimmed.contains("/") && URL(fileURLWithPath: trimmed).pathExtension.isEmpty == false
    }

    private static func applicationSupportRootURL() -> URL {
        MacAppStorageProfile.applicationSupportRootURL()
    }
}

struct ClickableFilePathView: View {
    let path: String
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            FileRevealService.open(path: path)
        } label: {
            Text(path)
                .font(RokuricsDetailTypography.metadataTechnicalValue)
                .foregroundStyle(isHovered ? MacTheme.aqua : MacTheme.deepText(for: colorScheme))
                .lineLimit(2)
                .truncationMode(.middle)
                .underline(isHovered, color: MacTheme.aqua.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(RokuricsCopy.text("在 Finder 中打开", "Open in Finder"))
        .accessibilityLabel(RokuricsCopy.text("在 Finder 中打开", "Open in Finder"))
    }
}

struct RokuricsTextFragment: Equatable, Identifiable {
    enum Kind: Equatable {
        case normal(RokuricsTextStyle)
        case technical
    }

    let text: String
    let kind: Kind

    var id: String {
        "\(kind.identifier):\(text)"
    }

    static func text(_ value: String, style: RokuricsTextStyle = .body) -> RokuricsTextFragment {
        RokuricsTextFragment(text: value, kind: .normal(style))
    }

    static func technical(_ value: String) -> RokuricsTextFragment {
        RokuricsTextFragment(text: value, kind: .technical)
    }
}

private extension RokuricsTextFragment.Kind {
    var identifier: String {
        switch self {
        case .normal(let style):
            return "normal-\(style)"
        case .technical:
            return "technical"
        }
    }
}

struct MixedTypographyText: View {
    let fragments: [RokuricsTextFragment]
    var foregroundColor: Color? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(attributedText)
            .foregroundStyle(foregroundColor ?? MacTheme.deepText(for: colorScheme))
    }

    private var attributedText: AttributedString {
        var result = AttributedString()

        for fragment in fragments {
            result += attributedString(for: fragment)
        }

        return result
    }

    private func attributedString(for fragment: RokuricsTextFragment) -> AttributedString {
        switch fragment.kind {
        case .normal(let style):
            return MacTypography.attributedString(
                for: fragment.text,
                style: MacTypography.mixedStyle(for: style)
            )
        case .technical:
            return MacTypography.attributedString(
                for: fragment.text,
                style: MacTypography.mixedStyle(for: .technical),
                forceTechnical: true
            )
        }
    }
}

struct TechnicalInlineText: View {
    let prefix: String
    let technical: String
    var suffix: String = ""

    var body: some View {
        MixedTypographyText(
            fragments: [
                .text(prefix),
                .technical(technical),
                .text(suffix)
            ].filter { !$0.text.isEmpty }
        )
    }
}

struct PathTextView: View {
    let path: String

    var body: some View {
        MixedTypographyText(fragments: [.technical(path)])
    }
}

struct RokuricsCircleIconButton: View {
    static let size: CGFloat = RokuricsCircleIconButtonConfiguration.size

    let systemImage: String
    let accessibilityTitle: String
    var tint: Color? = nil
    var isEnabled = true
    var role: ButtonRole? = nil
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: RokuricsCircleIconButtonConfiguration.iconSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(foregroundColor)
                .frame(width: Self.size, height: Self.size)
                .macGlassCircle(
                    fillOpacity: backgroundOpacity,
                    strokeOpacity: isHovered && isEnabled
                        ? RokuricsCircleIconButtonConfiguration.hoverStrokeOpacity
                        : RokuricsCircleIconButtonConfiguration.strokeOpacity,
                    shadowOpacity: isEnabled ? 0.08 : 0.03,
                    shadowRadius: 10,
                    shadowY: 5
                )
        }
        .buttonStyle(.plain)
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : RokuricsCircleIconButtonConfiguration.disabledOpacity)
        .scaleEffect(isHovered && isEnabled ? 1.025 : 1)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityTitle)
        .help(accessibilityTitle)
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return MacTheme.tertiaryText(for: colorScheme)
        }

        return tint ?? MacTheme.deepText(for: colorScheme)
    }

    private var backgroundOpacity: Double {
        if !isEnabled {
            return RokuricsCircleIconButtonConfiguration.disabledFillOpacity
        }
        if isHovered {
            return RokuricsCircleIconButtonConfiguration.hoverFillOpacity
        }
        return RokuricsCircleIconButtonConfiguration.fillOpacity
    }
}

struct RokuricsBackButton: View {
    static let systemImage = "chevron.left"
    static let visibleTitle = ""
    static var accessibilityTitle: String { RokuricsCopy.text("返回", "Back") }

    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        RokuricsCircleIconButton(
            systemImage: Self.systemImage,
            accessibilityTitle: Self.accessibilityTitle,
            tint: tint,
            action: action
        )
    }
}

struct RokuricsInfoButton: View {
    static let systemImage = "info"
    static let visibleTitle = ""
    static var accessibilityTitle: String { RokuricsCopy.text("信息", "Info") }

    let action: () -> Void

    var body: some View {
        RokuricsCircleIconButton(
            systemImage: Self.systemImage,
            accessibilityTitle: Self.accessibilityTitle,
            action: action
        )
    }
}

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

struct RokuricsDocumentPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void
    let trailing: Trailing

    init(
        title: String,
        subtitle: String,
        onBack: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RokuricsBackButton(action: onBack)

            VStack(alignment: .leading, spacing: 7) {
                RokuricsPageTitle(text: title)
                RokuricsPageSubtitle(text: subtitle)
            }

            Spacer(minLength: 0)

            trailing
        }
    }
}

extension RokuricsDocumentPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String, onBack: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, onBack: onBack) {
            EmptyView()
        }
    }
}

struct RokuricsDocumentInfoCard: View {
    var title = RokuricsCopy.text("基本信息", "Info")
    let rows: [RokuricsDocumentMetadataRow]

    var body: some View {
        let visibleRows = rows.filter(\.isVisible)

        if !visibleRows.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                RokuricsSectionTitle(text: title)
                RokuricsDocumentRows(rows: visibleRows)
            }
            .padding(18)
            .macLiquidGlassCard(cornerRadius: 20, material: .thinMaterial, fillOpacity: 0.32, strokeOpacity: 0.26, shadowOpacity: 0.04, shadowRadius: 9, shadowY: 4)
        }
    }
}

struct RokuricsDocumentAdvancedInfoCard: View {
    var title = RokuricsCopy.text("高级信息", "Details")
    let rows: [RokuricsDocumentMetadataRow]
    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let visibleRows = rows.filter(\.isVisible)

        if !visibleRows.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                RokuricsDocumentRows(rows: visibleRows)
                    .padding(.top, 12)
            } label: {
                HStack(spacing: 8) {
                    RokuricsSectionTitle(text: title)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .disclosureGroupStyle(.automatic)
            .tint(MacTheme.softText(for: colorScheme))
            .padding(18)
            .macLiquidGlassCard(cornerRadius: 20, material: .thinMaterial, fillOpacity: 0.24, strokeOpacity: 0.20, shadowOpacity: 0.025, shadowRadius: 7, shadowY: 3)
        }
    }
}

struct RokuricsDocumentInfoPopover: View {
    let primaryRows: [RokuricsDocumentMetadataRow]
    let advancedRows: [RokuricsDocumentMetadataRow]

    @State private var isAdvancedExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !primaryVisibleRows.isEmpty {
                infoGroup(title: RokuricsCopy.text("基础信息", "Info"), rows: primaryVisibleRows)
            }

            if !advancedVisibleRows.isEmpty {
                DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                    RokuricsDocumentRows(rows: advancedVisibleRows)
                        .padding(.top, 10)
                } label: {
                    RokuricsSectionTitle(text: RokuricsCopy.text("高级信息", "Details"))
                }
                .disclosureGroupStyle(.automatic)
                .tint(MacTheme.softText(for: colorScheme))
            }
        }
        .padding(18)
        .frame(width: 420, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(MacTheme.glassStroke(for: colorScheme).opacity(0.28), lineWidth: 1)
        }
    }

    private var primaryVisibleRows: [RokuricsDocumentMetadataRow] {
        primaryRows.filter(\.isVisible)
    }

    private var advancedVisibleRows: [RokuricsDocumentMetadataRow] {
        advancedRows.filter(\.isVisible)
    }

    private func infoGroup(title: String, rows: [RokuricsDocumentMetadataRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RokuricsSectionTitle(text: title)
            RokuricsDocumentRows(rows: rows)
        }
    }
}

enum RokuricsDocumentReadingLayout {
    static let defaultShowsMetadataCards = false
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
                RokuricsSectionTitle(text: title)
            }
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassCard(cornerRadius: 22, material: .ultraThinMaterial, fillOpacity: 0.32, strokeOpacity: 0.24, shadowOpacity: 0.035, shadowRadius: 8, shadowY: 4)
    }
}

private struct RokuricsDocumentRows: View {
    let rows: [RokuricsDocumentMetadataRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    RokuricsDocumentDivider()
                }

                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    RokuricsMetadataLabel(text: row.label)
                        .frame(width: 92, alignment: .leading)

                    RokuricsMetadataValue(text: row.value, isTechnical: row.isTechnical)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.vertical, 11)
            }
        }
    }
}

private struct RokuricsDocumentDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(MacTheme.glassStroke(for: colorScheme).opacity(colorScheme == .dark ? 0.14 : 0.30))
            .frame(height: 1)
            .padding(.leading, 18)
    }
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

enum RokuricsDocumentDisplayRows {
    static func transcriptInfoRows(
        item: MacRecordingInboxItem,
        markdown: String,
        transcriptResult: TranscriptionResult?,
        receiveRecord: RecordingReceiveRecord? = nil
    ) -> [RokuricsDocumentMetadataRow] {
        let metadata = RokuricsTranscriptMarkdownCleaner.metadata(from: markdown)
        return [
            RokuricsDocumentMetadataRow(RokuricsCopy.text("录音时间", "Recorded"), RokuricsDocumentFormatting.dateTime(item.receivedAt)),
            RokuricsDocumentMetadataRow(RokuricsCopy.text("时长", "Duration"), RokuricsDocumentFormatting.duration(item.duration)),
            RokuricsDocumentMetadataRow(RokuricsCopy.text("语言", "Language"), transcriptResult?.language ?? metadata["language"]),
            RokuricsDocumentMetadataRow(RokuricsCopy.text("转写 Provider", "Provider"), RokuricsProviderDisplayName.transcription(receiveRecord?.transcriptionProviderID ?? transcriptResult?.providerID ?? transcriptResult?.providerName ?? metadata["provider"])),
            RokuricsDocumentMetadataRow(RokuricsCopy.text("转写模型", "Model"), RokuricsModelDisplayName.friendly(receiveRecord?.transcriptionModelName ?? transcriptResult?.modelName)),
            RokuricsDocumentMetadataRow(RokuricsCopy.text("转写时间", "Transcribed"), RokuricsDocumentFormatting.dateTime(transcriptResult?.completedAt ?? receiveRecord?.transcriptionCompletedAt) ?? metadata["transcribedAt"]),
            RokuricsDocumentMetadataRow("mode", RokuricsDocumentFormatting.mode(receiveRecord?.transcriptionMode)),
            RokuricsDocumentMetadataRow("chunks", receiveRecord?.transcriptionChunks.map { "\($0.count)" })
        ]
    }

    static func transcriptAdvancedRows(
        item: MacRecordingInboxItem,
        markdown: String,
        transcriptResult: TranscriptionResult?,
        receiveRecord: RecordingReceiveRecord?
    ) -> [RokuricsDocumentMetadataRow] {
        let metadata = RokuricsTranscriptMarkdownCleaner.metadata(from: markdown)
        return [
            RokuricsDocumentMetadataRow(RokuricsCopy.text("转写 Provider", "Provider"), RokuricsProviderDisplayName.transcription(receiveRecord?.transcriptionProviderID ?? transcriptResult?.providerID ?? transcriptResult?.providerName ?? metadata["provider"])),
            RokuricsDocumentMetadataRow(RokuricsCopy.text("转写模型", "Model"), RokuricsModelDisplayName.friendly(receiveRecord?.transcriptionModelName ?? transcriptResult?.modelName)),
            RokuricsDocumentMetadataRow(RokuricsCopy.text("转写时间", "Transcribed"), RokuricsDocumentFormatting.dateTime(transcriptResult?.completedAt ?? receiveRecord?.transcriptionCompletedAt) ?? metadata["transcribedAt"]),
            RokuricsDocumentMetadataRow("mode", RokuricsDocumentFormatting.mode(receiveRecord?.transcriptionMode)),
            RokuricsDocumentMetadataRow("chunks", receiveRecord?.transcriptionChunks.map { "\($0.count)" }),
            RokuricsDocumentMetadataRow("recordingID", item.id, isTechnical: true),
            RokuricsDocumentMetadataRow("transcript.json", item.transcriptRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow("transcript.md", item.transcriptMarkdownRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow("receive", item.receiveRelativePath, isTechnical: true)
        ]
    }

    static func noteInfoRows(item: MacRecordingInboxItem, markdown: String, receiveRecord: RecordingReceiveRecord?) -> [RokuricsDocumentMetadataRow] {
        let metadata = RokuricsNoteMarkdownCleaner.metadata(from: markdown)
        return [
            RokuricsDocumentMetadataRow(
                RokuricsCopy.text("生成时间", "Generated"),
                RokuricsDocumentFormatting.dateTime(receiveRecord?.noteGeneratedAt) ?? metadata["generatedAt"]
            ),
            RokuricsDocumentMetadataRow("Note Provider", RokuricsProviderDisplayName.note(receiveRecord?.noteProviderID ?? metadata["provider"])),
            RokuricsDocumentMetadataRow(RokuricsCopy.text("模型", "Model"), RokuricsModelDisplayName.friendly(receiveRecord?.noteModelName ?? metadata["model"])),
            RokuricsDocumentMetadataRow("mode", RokuricsDocumentFormatting.mode(receiveRecord?.noteGenerationMode) ?? metadata["mode"]),
            RokuricsDocumentMetadataRow("sections", receiveRecord?.noteSections.map { "\($0.count)" } ?? metadata["sections"])
        ]
    }

    static func noteAdvancedRows(item: MacRecordingInboxItem, markdown: String, receiveRecord: RecordingReceiveRecord?) -> [RokuricsDocumentMetadataRow] {
        let metadata = RokuricsNoteMarkdownCleaner.metadata(from: markdown)
        return [
            RokuricsDocumentMetadataRow("recordingID", item.id, isTechnical: true),
            RokuricsDocumentMetadataRow("note", item.noteRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow(RokuricsCopy.text("来源 transcript", "Source transcript"), metadata["sourceTranscript"] ?? item.transcriptMarkdownRelativePath ?? item.transcriptRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow(
                "note sections",
                receiveRecord?.noteSections?
                    .compactMap(\.sectionNoteRelativePath)
                    .joined(separator: "\n"),
                isTechnical: true
            )
        ]
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let blocks = RokuricsMarkdownRenderer.blocks(from: markdown)

        if blocks.isEmpty {
            Text(RokuricsCopy.text("暂无内容", "No content"))
                .font(RokuricsDetailTypography.metadataValue)
                .foregroundStyle(MacTheme.softText(for: colorScheme))
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
            Text(text)
                .font(RokuricsDetailTypography.contentHeading(level: level))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .padding(.top, level == 1 ? 2 : 8)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("•")
                    .font(RokuricsDetailTypography.bodyEmphasis)
                    .foregroundStyle(MacTheme.aqua)
                Text(text)
                    .font(RokuricsDetailTypography.body)
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .paragraph(let text):
            Text(text)
                .font(RokuricsDetailTypography.body)
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
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
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.hasPrefix("## ")
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
            } else if let value = value(after: "- 转写模型：", in: trimmed) {
                metadata["transcriptModel"] = value
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

struct RecordingDocumentMetadataLoader {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            self.rootURL = MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
        }
    }

    func loadReceiveRecord(item: MacRecordingInboxItem) -> RecordingReceiveRecord? {
        guard let receiveRelativePath = item.receiveRelativePath,
              let url = resolvedURL(relativePath: receiveRelativePath),
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? Self.decoder.decode(RecordingReceiveRecord.self, from: data)
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
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private func normalizedLines(_ markdown: String) -> [String] {
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
