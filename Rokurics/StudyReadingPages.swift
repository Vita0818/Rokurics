//
//  StudyReadingPages.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import SwiftUI

struct StudyTranscriptReadingPage: View {
    let item: StudyItemMetadata
    let rootURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var loadResult: StudyDocumentLoadResult = .loading

    private var loader: StudyDocumentLoader {
        StudyDocumentLoader(rootURL: rootURL)
    }

    var body: some View {
        StudyReadingPageContainer(
            title: item.title,
            subtitle: "转写文本 / transcript",
            primaryRows: transcriptInfoRows,
            advancedRows: transcriptAdvancedRows,
            layout: .iPhone,
            onBack: { dismiss() }
        ) {
            switch loadResult {
            case .loading:
                StudyReadingLoadingCard(text: "正在读取转写文本")
            case .loaded(let markdown):
                StudyReadingContentView(
                    title: "转写正文",
                    markdown: RokuricsTranscriptMarkdownCleaner.cleanedBody(from: markdown)
                )
            case .failed(let message):
                StudyReadingLoadingCard(text: message)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: loadMarkdown)
    }

    private var transcriptInfoRows: [RokuricsDocumentMetadataRow] {
        guard case .loaded(let markdown) = loadResult else {
            return []
        }
        let transcriptResult = loader.loadTranscriptResult(item: item)
        let receiveRecord = loader.loadReceiveRecord(item: item)
        return StudyReadingMetadataRows.transcriptInfoRows(
            item: item,
            markdown: markdown,
            transcriptResult: transcriptResult,
            receiveRecord: receiveRecord
        )
    }

    private var transcriptAdvancedRows: [RokuricsDocumentMetadataRow] {
        guard case .loaded(let markdown) = loadResult else {
            return []
        }
        let transcriptResult = loader.loadTranscriptResult(item: item)
        let receiveRecord = loader.loadReceiveRecord(item: item)
        return StudyReadingMetadataRows.transcriptAdvancedRows(
            item: item,
            markdown: markdown,
            transcriptResult: transcriptResult,
            receiveRecord: receiveRecord
        )
    }

    private func loadMarkdown() {
        loadResult = loader.loadTranscriptMarkdown(item: item)
    }
}

struct StudyNoteReadingPage: View {
    let item: StudyItemMetadata
    let rootURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var loadResult: StudyDocumentLoadResult = .loading

    private var loader: StudyDocumentLoader {
        StudyDocumentLoader(rootURL: rootURL)
    }

    var body: some View {
        StudyReadingPageContainer(
            title: item.title,
            subtitle: "AI 总结 / note",
            primaryRows: noteInfoRows,
            advancedRows: noteAdvancedRows,
            layout: .iPhone,
            onBack: { dismiss() }
        ) {
            switch loadResult {
            case .loading:
                StudyReadingLoadingCard(text: "正在读取笔记")
            case .loaded(let markdown):
                StudyReadingContentView(
                    title: "总结正文",
                    markdown: RokuricsNoteMarkdownCleaner.cleanedBody(from: markdown)
                )
            case .failed(let message):
                StudyReadingLoadingCard(text: message)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: loadMarkdown)
    }

    private var noteInfoRows: [RokuricsDocumentMetadataRow] {
        guard case .loaded(let markdown) = loadResult else {
            return []
        }
        let receiveRecord = loader.loadReceiveRecord(item: item)
        return StudyReadingMetadataRows.noteInfoRows(
            item: item,
            markdown: markdown,
            receiveRecord: receiveRecord
        )
    }

    private var noteAdvancedRows: [RokuricsDocumentMetadataRow] {
        guard case .loaded(let markdown) = loadResult else {
            return []
        }
        let receiveRecord = loader.loadReceiveRecord(item: item)
        return StudyReadingMetadataRows.noteAdvancedRows(
            item: item,
            markdown: markdown,
            receiveRecord: receiveRecord
        )
    }

    private func loadMarkdown() {
        loadResult = loader.loadNoteMarkdown(item: item)
    }
}
