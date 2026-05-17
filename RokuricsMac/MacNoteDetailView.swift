//
//  MacNoteDetailView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import SwiftUI

struct MacNoteDetailView: View {
    let item: MacRecordingInboxItem
    let onBack: () -> Void
    var loader = NoteMarkdownDocumentLoader()

    @State private var loadResult: NoteMarkdownLoadResult = .loading
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button(action: onBack) {
                Label("返回", systemImage: "chevron.left")
                    .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .macGlassCapsule(fillOpacity: 0.32, strokeOpacity: 0.30)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                MacMixedFontText(
                    text: item.title,
                    chineseFont: MacTypography.chineseHeadline(size: 24),
                    englishFont: MacTypography.englishLargeTitle(size: 26),
                    numberFont: MacTypography.number(size: 25)
                )
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(2)

                Text("note.md")
                    .font(MacTypography.englishCaption(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
            }

            noteContent
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .macLiquidGlassCard(cornerRadius: 20, material: .ultraThinMaterial, fillOpacity: 0.32, strokeOpacity: 0.28, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)

            Spacer(minLength: 0)
        }
        .onAppear(perform: loadMarkdown)
        .onChange(of: item.id) {
            loadMarkdown()
        }
    }

    @ViewBuilder
    private var noteContent: some View {
        switch loadResult {
        case .loading:
            Text("正在读取笔记文档")
                .font(MacTypography.chineseBody(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
        case .loaded(let markdown):
            Text(markdown)
                .font(MacTypography.chineseBody(size: 14, weight: .regular))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            Text(message)
                .font(MacTypography.chineseBody(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
        }
    }

    private func loadMarkdown() {
        loadResult = loader.load(item: item)
    }
}

enum NoteMarkdownLoadResult: Equatable {
    case loading
    case loaded(String)
    case failed(String)
}

struct NoteMarkdownDocumentLoader {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.rootURL = applicationSupportURL
                .appendingPathComponent("Rokurics", isDirectory: true)
                .standardizedFileURL
        }
    }

    func load(item: MacRecordingInboxItem) -> NoteMarkdownLoadResult {
        guard let path = item.noteRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              let url = resolvedURL(relativePath: path) else {
            return .failed("未找到笔记文档")
        }

        guard fileManager.fileExists(atPath: url.path) else {
            return .failed("未找到笔记文档")
        }

        do {
            return .loaded(try String(contentsOf: url, encoding: .utf8))
        } catch {
            return .failed("无法读取笔记文档")
        }
    }

    private func resolvedURL(relativePath: String) -> URL? {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("/") else {
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
}
