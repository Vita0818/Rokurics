//
//  IPhoneAIChatView.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import SwiftUI
import UIKit

struct IPhoneAIChatView: View {
    @ObservedObject var studyLibraryStore: StudyLibraryStore
    @ObservedObject var userProfileStore: UserProfileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var settingsStore = IPhoneAISettingsStore()
    @State private var messages: [IPhoneChatMessage] = []
    @State private var activeContext: IPhoneChatContext?
    @State private var draft = ""
    @State private var errorMessage: String?
    @State private var isSending = false
    @State private var isImportSheetPresented = false
    @State private var isRecentConversationsPresented = false
    @State private var activeConversationID = UUID().uuidString
    @State private var recentConversations: [IPhoneRecentConversation] = []

    var body: some View {
        ChatConversationView(
            title: "AI 对话",
            contextPathDisplay: activeContext?.pathDisplay,
            messages: messages,
            greetingText: ChatGreeting.current(displayName: userProfileStore.profile.displayName).text,
            shouldShowGreeting: messages.isEmpty && !isSending,
            isGenerating: isSending,
            draft: $draft,
            errorMessage: errorMessage,
            layout: .iPhone,
            headerLeading: {
                ChatPageBackButton(action: { dismiss() })
            },
            headerTrailing: {
                ChatConversationButtonGroup(
                    recentAction: {
                        saveCurrentConversationSnapshot()
                        isRecentConversationsPresented = true
                    },
                    newConversationAction: startNewConversation
                )
            },
            pendingAttachments: {
                ChatAttachmentChipRow(
                    attachments: activeContextAttachments,
                    onRemove: { _ in
                        removeActiveContext()
                    }
                )
            },
            messageRow: { message in
                ChatMessageRow(message: message)
            },
            onImportContext: {
                isImportSheetPresented = true
            },
            onSend: {
                Task { await sendMessage() }
            }
        )
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isImportSheetPresented) {
            NavigationStack {
                ChatStudyLibraryPickerView(
                    studyLibraryStore: studyLibraryStore,
                    onCancel: {
                        isImportSheetPresented = false
                    },
                    onImport: importStudyLibrarySelection
                )
            }
        }
        .sheet(isPresented: $isRecentConversationsPresented) {
            NavigationStack {
                ZStack {
                    RokuricsSharedStyle.pageGradient(for: colorScheme)
                        .ignoresSafeArea()

                    ChatRecentConversationListView(
                        conversations: recentConversations.map(\.conversation),
                        activeConversationID: activeConversationID,
                        onSelect: selectRecentConversation,
                        onDelete: deleteRecentConversation
                    )
                    .padding(16)
                }
                .navigationTitle("最近对话")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            isRecentConversationsPresented = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            studyLibraryStore.refresh()
        }
    }

    private func importStudyLibrarySelection(_ selection: ChatStudyLibraryPickerSelection) {
        let exporter = StudyLibraryContextExporter(rootURL: studyLibraryStore.libraryRootURL)
        let context: IPhoneChatContext
        switch selection {
        case .folder(let path):
            context = exporter.export(items: studyLibraryStore.allStudyItems, path: path)
        case .item(let item):
            context = exporter.export(item: item)
        }

        activeContext = context
        isImportSheetPresented = false
        saveCurrentConversationSnapshot()
    }

    private func startNewConversation() {
        guard !isSending else {
            return
        }

        saveCurrentConversationSnapshot()
        activeConversationID = UUID().uuidString
        messages = []
        activeContext = nil
        draft = ""
        errorMessage = nil
        isImportSheetPresented = false
    }

    private func selectRecentConversation(_ conversation: ChatConversation) {
        guard !isSending else {
            return
        }

        saveCurrentConversationSnapshot()
        guard let snapshot = recentConversations.first(where: { $0.id == conversation.id }) else {
            return
        }

        activeConversationID = snapshot.id
        messages = snapshot.conversation.messages
        activeContext = snapshot.context
        draft = ""
        errorMessage = nil
        isRecentConversationsPresented = false
    }

    private func deleteRecentConversation(_ conversation: ChatConversation) {
        recentConversations.removeAll { $0.id == conversation.id }
        if conversation.id == activeConversationID {
            activeConversationID = UUID().uuidString
            messages = []
            activeContext = nil
            draft = ""
            errorMessage = nil
        }
    }

    private func removeActiveContext() {
        activeContext = nil
        if messages.isEmpty {
            recentConversations.removeAll { $0.id == activeConversationID }
        } else {
            saveCurrentConversationSnapshot()
        }
    }

    private func sendMessage() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else {
            return
        }

        draft = ""
        errorMessage = nil
        isSending = true
        messages.append(IPhoneChatMessage(role: .user, content: text))
        saveCurrentConversationSnapshot()

        do {
            let provider = settingsStore.provider()
            let response = try await provider.send(
                request: IPhoneChatRequest(messages: messages, context: activeContext)
            )
            messages.append(response)
            saveCurrentConversationSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
        saveCurrentConversationSnapshot()
    }

    private var activeContextAttachments: [ChatAttachment] {
        guard let activeContext else {
            return []
        }

        return [
            ChatAttachment(
                id: activeContext.id,
                conversationID: activeConversationID,
                fileName: activeContext.pathDisplay,
                fileType: "study-library",
                relativePath: "study-library-context/\(activeContext.id)",
                sizeBytes: Int64(activeContext.totalCharacterCount),
                kind: .document
            )
        ]
    }

    private func saveCurrentConversationSnapshot() {
        guard let snapshot = currentConversationSnapshot() else {
            return
        }

        recentConversations.removeAll { $0.id == snapshot.id }
        recentConversations.insert(snapshot, at: 0)
        if recentConversations.count > 12 {
            recentConversations = Array(recentConversations.prefix(12))
        }
    }

    private func currentConversationSnapshot() -> IPhoneRecentConversation? {
        guard !messages.isEmpty || activeContext != nil else {
            return nil
        }

        let existing = recentConversations.first { $0.id == activeConversationID }
        let conversation = ChatConversation(
            id: activeConversationID,
            title: currentConversationTitle(),
            titleSource: .fallback,
            messages: messages,
            activeContextID: activeContext?.id,
            contextPathDisplay: activeContext?.pathDisplay,
            contextItemCount: activeContext?.itemCount,
            lastMessagePreview: currentConversationPreview(),
            attachments: activeContextAttachments,
            createdAt: existing?.conversation.createdAt ?? messages.first?.createdAt ?? Date(),
            updatedAt: Date()
        )

        return IPhoneRecentConversation(conversation: conversation, context: activeContext)
    }

    private func currentConversationTitle() -> String {
        if let activeContext {
            return activeContext.displayTitle
        }

        let title = messages.first { $0.role == .user }?.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty {
            return String(title.prefix(28))
        }

        return "新对话"
    }

    private func currentConversationPreview() -> String? {
        messages.last { $0.role != .system }?.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct IPhoneRecentConversation: Identifiable, Equatable {
    var id: String { conversation.id }
    let conversation: ChatConversation
    let context: IPhoneChatContext?
}
