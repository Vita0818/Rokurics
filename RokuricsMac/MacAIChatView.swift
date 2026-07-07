//
//  MacAIChatView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/20.
//

import SwiftUI
import UniformTypeIdentifiers

struct MacAIChatView: View {
    @ObservedObject var chatCoordinator: ChatCoordinator
    @ObservedObject var studyLibraryStore: StudyLibraryStore
    @ObservedObject var userProfileStore: MacUserProfileStore
    var isSidebarCollapsed = false

    @State private var draft = ""
    @State private var isRecentPopoverPresented = false
    @State private var isAttachmentMenuPresented = false
    @State private var isStudyLibraryPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var allowedAttachmentTypes: [UTType] = [.item]
    @FocusState private var isComposerFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ChatConversationView(
            title: RokuricsCopy.text("AI 对话", "AI Chat"),
            contextPathDisplay: chatCoordinator.conversation.contextPathDisplay,
            messages: chatCoordinator.visibleMessages,
            greetingText: ChatGreeting.current(
                displayName: userProfileStore.profile.displayName,
                defaultName: MacUserProfile.defaultDisplayName
            ).text,
            shouldShowGreeting: shouldShowGreeting,
            isGenerating: chatCoordinator.isGenerating,
            draft: $draft,
            errorMessage: chatCoordinator.errorMessage,
            layout: .mac,
            headerLeading: {
                EmptyView()
            },
            headerTrailing: {
                EmptyView()
            },
            pendingAttachments: {
                ChatAttachmentChipRow(
                    attachments: chatCoordinator.pendingAttachments,
                    onRemove: { attachment in
                        chatCoordinator.removePendingAttachment(id: attachment.id)
                    }
                )
            },
            messageRow: { message in
                ChatMessageRow(
                    message: message,
                    attachments: chatCoordinator.attachments(for: message)
                )
            },
            onImportContext: {
                isAttachmentMenuPresented = true
            },
            onSend: send
        )
        .popover(isPresented: $isAttachmentMenuPresented, arrowEdge: .top) {
            MacAIChatAttachmentMenu(
                onSelect: { action in
                    handleAttachmentMenuAction(action)
                }
            )
            .frame(width: 190)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: allowedAttachmentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                chatCoordinator.addAttachments(from: urls)
            case .failure(let error):
                chatCoordinator.errorMessage = error.localizedDescription
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ChatConversationButtonGroup(
                    recentAction: {
                        isRecentPopoverPresented = true
                    },
                    newConversationAction: {
                        chatCoordinator.createNewConversation()
                        draft = ""
                        isComposerFocused = true
                    }
                )
                .popover(isPresented: $isRecentPopoverPresented, arrowEdge: .bottom) {
                    recentConversationsPopover
                }
            }
        }
        .onAppear {
            isComposerFocused = true
            studyLibraryStore.refresh()
        }
        .sheet(isPresented: $isStudyLibraryPickerPresented) {
            ChatStudyLibraryPickerView(
                studyLibraryStore: studyLibraryStore,
                onCancel: {
                    isStudyLibraryPickerPresented = false
                    isComposerFocused = true
                },
                onImport: { selection in
                    importStudyLibrarySelection(selection)
                }
            )
            .frame(minWidth: 560, minHeight: 500)
        }
    }

    private var recentConversationsPopover: some View {
        MacRecentConversationsPopover(
            conversations: chatCoordinator.recentConversations,
            activeConversationID: chatCoordinator.conversation.id,
            onSelect: { conversationID in
                chatCoordinator.selectConversation(id: conversationID)
                draft = ""
                isRecentPopoverPresented = false
                isComposerFocused = true
            },
            onDelete: { conversationID in
                chatCoordinator.deleteConversation(id: conversationID)
                if chatCoordinator.recentConversations.isEmpty {
                    isRecentPopoverPresented = false
                }
                draft = ""
                isComposerFocused = true
            }
        )
        .frame(width: 320)
    }

    private var shouldShowGreeting: Bool {
        chatCoordinator.visibleMessages.isEmpty && !chatCoordinator.isGenerating
    }

    private func handleAttachmentMenuAction(_ action: MacAIChatAttachmentMenuAction) {
        isAttachmentMenuPresented = false
        switch action {
        case .importStudyLibrary:
            studyLibraryStore.refresh()
            isStudyLibraryPickerPresented = true
        case .uploadFile:
            allowedAttachmentTypes = [.item]
            isFileImporterPresented = true
        case .uploadImage:
            allowedAttachmentTypes = [.image]
            isFileImporterPresented = true
        }
    }

    private func importStudyLibrarySelection(_ selection: ChatStudyLibraryPickerSelection) {
        let exporter = StudyLibraryContextExporter(rootURL: studyLibraryStore.libraryRootURL)
        let context: ChatContext
        switch selection {
        case .folder(let path):
            context = exporter.export(items: studyLibraryStore.effectiveStudyItems, path: path)
        case .item(let item):
            context = exporter.export(item: item)
        }

        chatCoordinator.importContext(context)
        draft = ""
        isStudyLibraryPickerPresented = false
        isComposerFocused = true
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatCoordinator.isGenerating
    }

    private func send() {
        guard canSend else {
            return
        }

        let text = draft
        draft = ""
        Task {
            await chatCoordinator.send(text)
            isComposerFocused = true
        }
    }

}

struct MacAIChatToolbarLayout: Equatable {
    static let usesWindowOverlay = false
    static let placement = "navigation"
}

enum MacAIChatAttachmentMenuAction: CaseIterable, Equatable {
    case importStudyLibrary
    case uploadFile
    case uploadImage

    var title: String {
        switch self {
        case .importStudyLibrary:
            return RokuricsCopy.text("导入学习库内容", "Import Library")
        case .uploadFile:
            return RokuricsCopy.text("上传文件", "Upload File")
        case .uploadImage:
            return RokuricsCopy.text("上传图片", "Upload Image")
        }
    }

    var systemImage: String {
        switch self {
        case .importStudyLibrary:
            return "books.vertical"
        case .uploadFile:
            return "doc.badge.plus"
        case .uploadImage:
            return "photo.badge.plus"
        }
    }
}

private struct MacAIChatAttachmentMenu: View {
    let onSelect: (MacAIChatAttachmentMenuAction) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(MacAIChatAttachmentMenuAction.allCases, id: \.self) { action in
                Button {
                    onSelect(action)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MacTheme.softText(for: colorScheme))
                            .frame(width: 18)

                        Text(action.title)
                            .font(MacTypography.secondary(size: 13, weight: .medium))
                            .foregroundStyle(MacTheme.deepText(for: colorScheme))

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
            }
        }
        .padding(6)
        .background(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.88 : 0.96))
    }
}

private struct MacRecentConversationsPopover: View {
    let conversations: [ChatConversation]
    let activeConversationID: String
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if conversations.isEmpty {
                Text(RokuricsCopy.text("暂无对话", "No chats"))
                    .font(RokuricsCopy.usesChinese ? MacTypography.chineseBody(size: 13, weight: .medium) : MacTypography.englishBody(size: 13, weight: .medium))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
                    .padding(14)
            } else {
                let displayedConversations = Array(conversations.prefix(12))
                ForEach(displayedConversations) { conversation in
                    MacRecentConversationRow(
                        conversation: conversation,
                        isActive: conversation.id == activeConversationID,
                        onSelect: {
                            onSelect(conversation.id)
                        },
                        onDelete: {
                            onDelete(conversation.id)
                        }
                    )

                    if conversation.id != displayedConversations.last?.id {
                        Divider()
                            .opacity(0.28)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .background(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.88 : 0.96))
    }
}

private struct MacRecentConversationRow: View {
    let conversation: ChatConversation
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Button(action: onSelect) {
                rowContent
            }
            .buttonStyle(.plain)

            RokuricsCircleIconButton(
                systemImage: "trash",
                accessibilityTitle: RokuricsCopy.text("删除对话", "Delete Chat"),
                tint: MacTheme.coral,
                role: .destructive,
                action: onDelete
            )
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 9)
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "text.bubble")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? MacTheme.leaf : MacTheme.softText(for: colorScheme))
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    RokuricsMixedText(conversation.title, style: MacMixedTypographyStyle(size: 13, weight: .semibold))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(conversation.updatedAt.formatted(date: .omitted, time: .shortened))
                        .font(MacTypography.numberBody(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                        .lineLimit(1)
                }

                if let contextPath = conversation.contextPathDisplay {
                    RokuricsMixedText(contextPath, style: MacMixedTypographyStyle(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let preview = conversation.lastMessagePreview {
                    RokuricsMixedText(preview, style: MacMixedTypographyStyle(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

#Preview {
    MacAIChatView(
        chatCoordinator: ChatCoordinator(
            providerResolver: { MockChatProvider() },
            conversationStore: nil
        ),
        studyLibraryStore: StudyLibraryStore(),
        userProfileStore: MacUserProfileStore(),
        isSidebarCollapsed: false
    )
}
