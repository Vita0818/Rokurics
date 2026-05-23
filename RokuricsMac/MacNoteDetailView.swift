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
    var metadataLoader = RecordingDocumentMetadataLoader()

    @State private var loadResult: NoteMarkdownLoadResult = .loading
    @State private var isInfoPresented = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                header

                noteContent

                Spacer(minLength: 0)
            }
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: loadMarkdown)
        .onChange(of: item.id) {
            loadMarkdown()
        }
    }

    @ViewBuilder
    private var header: some View {
        switch loadResult {
        case .loaded(let markdown):
            let receiveRecord = metadataLoader.loadReceiveRecord(item: item)
            RokuricsDocumentPageHeader(title: item.title, subtitle: "AI 总结 / note", onBack: onBack) {
                RokuricsInfoButton {
                    isInfoPresented = true
                }
                .popover(isPresented: $isInfoPresented, arrowEdge: .bottom) {
                    RokuricsDocumentInfoPopover(
                        primaryRows: RokuricsDocumentDisplayRows.noteInfoRows(
                            item: item,
                            markdown: markdown,
                            receiveRecord: receiveRecord
                        ),
                        advancedRows: RokuricsDocumentDisplayRows.noteAdvancedRows(
                            item: item,
                            markdown: markdown,
                            receiveRecord: receiveRecord
                        )
                    )
                }
            }
        default:
            RokuricsDocumentPageHeader(title: item.title, subtitle: "AI 总结 / note", onBack: onBack)
        }
    }

    @ViewBuilder
    private var noteContent: some View {
        switch loadResult {
        case .loading:
            RokuricsDocumentContentCard {
                Text("正在读取笔记")
                    .font(RokuricsDetailTypography.metadataValue)
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
            }
        case .loaded(let markdown):
            RokuricsDocumentContentCard(title: "总结正文") {
                RokuricsMarkdownContentView(markdown: RokuricsNoteMarkdownCleaner.cleanedBody(from: markdown))
            }
        case .failed(let message):
            RokuricsDocumentContentCard {
                Text(message)
                    .font(RokuricsDetailTypography.metadataValue)
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
            }
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
            self.rootURL = MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
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
