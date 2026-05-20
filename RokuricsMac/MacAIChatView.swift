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
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                messageList

                composer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ChatTopControlGroup(
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
            MacAIChatStudyLibraryPicker(
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

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if shouldShowGreeting {
                        MacAIChatGreetingView(text: MacAIChatGreeting.current(displayName: userProfileStore.profile.displayName).text)
                            .frame(maxWidth: 780, alignment: .center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 30)
                            .padding(.top, 140)
                    }

                    ForEach(chatCoordinator.visibleMessages) { message in
                        MacAIChatMessageRow(
                            message: message,
                            attachments: chatCoordinator.attachments(for: message)
                        )
                            .id(message.id)
                    }

                    if chatCoordinator.isGenerating {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: 780, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 30)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(.top, 20)
                .padding(.bottom, 18)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: chatCoordinator.visibleMessages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: chatCoordinator.isGenerating) {
                scrollToBottom(proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shouldShowGreeting: Bool {
        chatCoordinator.visibleMessages.isEmpty && !chatCoordinator.isGenerating
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = chatCoordinator.errorMessage {
                Text(errorMessage)
                    .font(MacTypography.secondary(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 780, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if !chatCoordinator.pendingAttachments.isEmpty {
                MacAIChatAttachmentChipRow(
                    attachments: chatCoordinator.pendingAttachments,
                    onRemove: { attachment in
                        chatCoordinator.removePendingAttachment(id: attachment.id)
                    }
                )
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(alignment: .center, spacing: 12) {
                RokuricsCircleIconButton(
                    systemImage: "plus",
                    accessibilityTitle: "添加附件",
                    tint: MacTheme.softText(for: colorScheme),
                    isEnabled: !chatCoordinator.isGenerating,
                    action: {
                        isAttachmentMenuPresented = true
                    }
                )
                .popover(isPresented: $isAttachmentMenuPresented, arrowEdge: .top) {
                    MacAIChatAttachmentMenu(
                        onSelect: { action in
                            handleAttachmentMenuAction(action)
                        }
                    )
                    .frame(width: 190)
                }

                TextField("消息", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(MacTypography.chatInput())
                    .lineLimit(1...6)
                    .focused($isComposerFocused)
                    .onSubmit(send)
                    .disabled(chatCoordinator.isGenerating)
                    .frame(minHeight: 38, alignment: .center)

                RokuricsCircleIconButton(
                    systemImage: chatCoordinator.isGenerating ? "ellipsis" : "arrow.up",
                    accessibilityTitle: "发送",
                    tint: canSend ? MacTheme.aqua : nil,
                    isEnabled: canSend,
                    action: send
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 780, alignment: .center)
            .frame(minHeight: 64, alignment: .center)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.30 : 0.62))
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(MacTheme.glassStroke(for: colorScheme).opacity(0.30), lineWidth: 1)
            }
            .shadow(color: MacTheme.shadow(for: colorScheme).opacity(colorScheme == .dark ? 0.14 : 0.08), radius: 14, x: 0, y: 6)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 30)
        .padding(.top, 12)
        .padding(.bottom, 20)
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

    private func importStudyLibrarySelection(_ selection: MacAIChatStudyLibrarySelection) {
        let exporter = StudyLibraryContextExporter(rootURL: studyLibraryStore.libraryRootURL)
        let context: ChatContext
        switch selection {
        case .folder(let path):
            context = exporter.export(items: studyLibraryStore.allStudyItems, path: path)
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }
}

struct MacAIChatGreeting: Equatable {
    let userName: String
    let periodText: String

    var text: String {
        "\(userName)，\(periodText)！"
    }

    static func current(displayName: String, date: Date = Date(), calendar: Calendar = .current) -> MacAIChatGreeting {
        MacAIChatGreeting(
            userName: normalizedUserName(displayName) ?? MacUserProfile.defaultDisplayName,
            periodText: periodText(for: date, calendar: calendar)
        )
    }

    static func make(userName: String?, date: Date, calendar: Calendar) -> MacAIChatGreeting {
        MacAIChatGreeting(
            userName: normalizedUserName(userName) ?? MacUserProfile.defaultDisplayName,
            periodText: periodText(for: date, calendar: calendar)
        )
    }

    static func periodText(for date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return "早上好"
        case 12..<18:
            return "下午好"
        default:
            return "晚上好"
        }
    }

    private static func normalizedUserName(_ rawName: String?) -> String? {
        guard let rawName else {
            return nil
        }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let firstToken = trimmed.components(separatedBy: .whitespacesAndNewlines).first ?? trimmed
        return firstToken.prefix(1).uppercased() + firstToken.dropFirst()
    }
}

struct MacAIChatToolbarLayout: Equatable {
    static let usesWindowOverlay = false
    static let placement = "navigation"
}

enum ChatTopControl: CaseIterable, Equatable {
    case recentConversations
    case newConversation

    var systemImage: String {
        switch self {
        case .recentConversations:
            return "sidebar.left"
        case .newConversation:
            return "square.and.pencil"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .recentConversations:
            return "最近对话"
        case .newConversation:
            return "新建对话"
        }
    }
}

enum ChatTopControlGroupConfiguration {
    static let itemWidth: CGFloat = 34
    static let itemHeight: CGFloat = 32
    static let iconSize: CGFloat = 14
    static let borderWidth: CGFloat = 1
    static let separatorWidth: CGFloat = 1
    static let usesSharedGlassCapsule = true
    static let usesIndependentCircularButtons = false
    static let usesSystemSymbols = true
}

enum MacAIChatAttachmentMenuAction: CaseIterable, Equatable {
    case importStudyLibrary
    case uploadFile
    case uploadImage

    var title: String {
        switch self {
        case .importStudyLibrary:
            return "导入学习库内容"
        case .uploadFile:
            return "上传文件"
        case .uploadImage:
            return "上传图片"
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

enum MacAIChatStudyLibrarySelection: Equatable {
    case folder(StudyBrowsePath)
    case item(StudyItemMetadata)
}

private struct MacAIChatGreetingView: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RokuricsMixedText(text, textStyle: .chatGreeting)
            .foregroundStyle(MacTheme.deepText(for: colorScheme))
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .accessibilityLabel(text)
    }
}

private struct ChatTopControlGroup: View {
    let recentAction: () -> Void
    let newConversationAction: () -> Void

    @State private var hoveredControl: ChatTopControl?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            topButton(.recentConversations, action: recentAction)

            Rectangle()
                .fill(MacTheme.glassStroke(for: colorScheme).opacity(0.28))
                .frame(
                    width: ChatTopControlGroupConfiguration.separatorWidth,
                    height: ChatTopControlGroupConfiguration.itemHeight - 12
                )

            topButton(.newConversation, action: newConversationAction)
        }
        .padding(2)
        .background {
            Capsule(style: .continuous)
                .fill(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.30 : 0.62))
                .background(.thinMaterial, in: Capsule(style: .continuous))
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    MacTheme.glassStroke(for: colorScheme).opacity(colorScheme == .dark ? 0.34 : 0.42),
                    lineWidth: ChatTopControlGroupConfiguration.borderWidth
                )
        }
        .clipShape(Capsule(style: .continuous))
        .shadow(color: MacTheme.shadow(for: colorScheme).opacity(colorScheme == .dark ? 0.12 : 0.07), radius: 10, x: 0, y: 4)
    }

    private func topButton(_ control: ChatTopControl, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: control.systemImage)
                .font(.system(size: ChatTopControlGroupConfiguration.iconSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .frame(
                    width: ChatTopControlGroupConfiguration.itemWidth,
                    height: ChatTopControlGroupConfiguration.itemHeight
                )
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            hoveredControl == control
                                ? MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.24 : 0.44)
                                : .clear
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(control.accessibilityTitle)
        .onHover { isHovering in
            hoveredControl = isHovering ? control : nil
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

private struct MacAIChatStudyLibraryPicker: View {
    @ObservedObject var studyLibraryStore: StudyLibraryStore
    let onCancel: () -> Void
    let onImport: (MacAIChatStudyLibrarySelection) -> Void

    @State private var browsePath = StudyBrowsePath()
    @Environment(\.colorScheme) private var colorScheme

    private var browseContent: StudyBrowseContent {
        StudyLibraryBrowser.content(
            items: studyLibraryStore.allStudyItems,
            folders: studyLibraryStore.allStudyFolders,
            path: browsePath
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()
                .opacity(0.28)

            browser
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .background(MacTheme.pageGradient(for: colorScheme))
        .onAppear {
            studyLibraryStore.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            RokuricsCircleIconButton(
                systemImage: "chevron.left",
                accessibilityTitle: "返回上一级",
                isEnabled: !browsePath.isRoot,
                action: {
                    browsePath = browsePath.parent
                }
            )

            pickerBreadcrumb
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Button("取消", action: onCancel)
                .font(MacTypography.secondary(size: 13, weight: .medium))

            Button("导入当前文件夹") {
                onImport(.folder(browsePath))
            }
            .font(MacTypography.secondary(size: 13, weight: .semibold))
            .disabled(studyLibraryStore.allStudyItems.isEmpty)
        }
    }

    private var pickerBreadcrumb: some View {
        HStack(spacing: 5) {
            ForEach(Array(StudyLibraryBrowser.breadcrumbs(for: browsePath).enumerated()), id: \.offset) { index, breadcrumb in
                if index > 0 {
                    Text("/")
                        .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                        .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                }

                Button {
                    browsePath = breadcrumb.path
                } label: {
                    Text(breadcrumb.title)
                        .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                        .foregroundStyle(index == StudyLibraryBrowser.breadcrumbs(for: browsePath).count - 1 ? MacTheme.deepText(for: colorScheme) : MacTheme.softText(for: colorScheme))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(index == StudyLibraryBrowser.breadcrumbs(for: browsePath).count - 1)
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
    }

    private var browser: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(browseContent.folders) { folder in
                    MacAIChatStudyLibraryPickerRow(
                        systemImage: "folder",
                        title: folder.title,
                        detail: "\(folder.itemCount) 项",
                        actionSystemImage: "chevron.right",
                        action: {
                            browsePath = folder.path
                        }
                    )
                }

                ForEach(browseContent.items) { item in
                    MacAIChatStudyLibraryPickerRow(
                        systemImage: item.kind == .recordingBundle ? "waveform" : "doc.text",
                        title: item.title,
                        detail: item.filingPath.displaySummary,
                        actionSystemImage: "plus.bubble",
                        action: {
                            onImport(.item(item))
                        }
                    )
                }

                if browseContent.folders.isEmpty && browseContent.items.isEmpty {
                    Text("暂无内容")
                        .font(MacTypography.secondary(size: 13, weight: .medium))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                        .padding(.vertical, 16)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct MacAIChatStudyLibraryPickerRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let actionSystemImage: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    RokuricsMixedText(title, style: MacMixedTypographyStyle(size: 13, weight: .semibold))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .lineLimit(1)

                    RokuricsMixedText(detail, style: MacMixedTypographyStyle(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Image(systemName: actionSystemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.36))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MacAIChatMessageRow: View {
    let message: ChatMessage
    let attachments: [ChatAttachment]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            content
                .frame(maxWidth: 680, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 80)
            }
        }
        .frame(maxWidth: 780, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 30)
    }

    @ViewBuilder
    private var content: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 7) {
                RokuricsMixedText(message.content, textStyle: .chatMessage)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(MacTheme.accentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if !attachments.isEmpty {
                    MacAIChatAttachmentChipRow(attachments: attachments, onRemove: nil)
                }
            }
        case .assistant:
            MacMarkdownMessageText(markdown: message.content)
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .system:
            EmptyView()
        }
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
                Text("暂无对话")
                    .font(MacTypography.chineseBody(size: 13, weight: .medium))
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
                accessibilityTitle: "删除对话",
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

private struct MacAIChatAttachmentChipRow: View {
    let attachments: [ChatAttachment]
    let onRemove: ((ChatAttachment) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(attachments) { attachment in
                    MacAIChatAttachmentChip(attachment: attachment, onRemove: onRemove)
                }
            }
        }
    }
}

private struct MacAIChatAttachmentChip: View {
    let attachment: ChatAttachment
    let onRemove: ((ChatAttachment) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MacTheme.softText(for: colorScheme))

            RokuricsMixedText(attachment.fileName, style: MacMixedTypographyStyle(size: 11, weight: .semibold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160)

            if let onRemove {
                Button {
                    onRemove(attachment)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("移除附件")
                .accessibilityLabel("移除附件")
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, onRemove == nil ? 9 : 5)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.24 : 0.48))
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(MacTheme.glassStroke(for: colorScheme).opacity(0.28), lineWidth: 1)
        }
    }

    private var systemImage: String {
        switch attachment.kind {
        case .image:
            return "photo"
        case .document:
            return "doc.text"
        case .audio:
            return "waveform"
        case .other:
            return "paperclip"
        }
    }
}

private struct MacMarkdownMessageText: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(markdown: markdown) {
            Text(scriptAwareAttributedString(attributed))
                .lineSpacing(4)
        } else {
            RokuricsMixedText(markdown, textStyle: .chatMessage)
                .lineSpacing(4)
        }
    }

    private func scriptAwareAttributedString(_ attributed: AttributedString) -> AttributedString {
        var copy = attributed
        MacTypography.applyMixedScriptFonts(
            to: &copy,
            style: MacTypography.mixedStyle(for: .chatMessage)
        )
        return copy
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
