//
//  SharedChatComponents.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import SwiftUI

struct ChatGreeting: Equatable {
    let userName: String
    let periodText: String

    var text: String {
        RokuricsCopy.usesChinese ? "\(userName)，\(periodText)！" : "\(periodText), \(userName)"
    }

    static func current(
        displayName: String,
        defaultName: String = RokuricsCopy.text("用户", "User"),
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> ChatGreeting {
        ChatGreeting(
            userName: normalizedUserName(displayName) ?? defaultName,
            periodText: periodText(for: date, calendar: calendar)
        )
    }

    static func make(userName: String?, defaultName: String = RokuricsCopy.text("用户", "User"), date: Date, calendar: Calendar) -> ChatGreeting {
        ChatGreeting(
            userName: normalizedUserName(userName) ?? defaultName,
            periodText: periodText(for: date, calendar: calendar)
        )
    }

    static func periodText(for date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return RokuricsCopy.text("早上好", "Good morning")
        case 12..<18:
            return RokuricsCopy.text("下午好", "Good afternoon")
        default:
            return RokuricsCopy.text("晚上好", "Good evening")
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

struct ChatGreetingView: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RokuricsSharedText(text: text, token: .chatGreeting)
            .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .accessibilityLabel(text)
    }
}

struct ChatConversationLayout {
    let wrapsPageBackground: Bool
    let showsHeader: Bool
    let showsScrollIndicators: Bool
    let horizontalPadding: CGFloat
    let headerTopPadding: CGFloat
    let headerBottomPadding: CGFloat
    let messageTopPadding: CGFloat
    let messageBottomPadding: CGFloat
    let messageSpacing: CGFloat
    let greetingTopPadding: CGFloat
    let contentMaxWidth: CGFloat?
    let composerTopPadding: CGFloat
    let composerBottomPadding: CGFloat
    let inputHorizontalPadding: CGFloat

    static var mac: ChatConversationLayout {
        ChatConversationLayout(
            wrapsPageBackground: true,
            showsHeader: false,
            showsScrollIndicators: true,
            horizontalPadding: 30,
            headerTopPadding: 0,
            headerBottomPadding: 0,
            messageTopPadding: 20,
            messageBottomPadding: 18,
            messageSpacing: 22,
            greetingTopPadding: 140,
            contentMaxWidth: 780,
            composerTopPadding: 12,
            composerBottomPadding: 20,
            inputHorizontalPadding: 30
        )
    }

    static var iPhone: ChatConversationLayout {
        ChatConversationLayout(
            wrapsPageBackground: true,
            showsHeader: true,
            showsScrollIndicators: false,
            horizontalPadding: RokuricsMobilePageLayoutMetrics.horizontalPadding,
            headerTopPadding: RokuricsMobilePageLayoutMetrics.topPadding,
            headerBottomPadding: RokuricsMobilePageLayoutMetrics.headerBottomSpacing,
            messageTopPadding: 0,
            messageBottomPadding: 18,
            messageSpacing: 12,
            greetingTopPadding: 120,
            contentMaxWidth: nil,
            composerTopPadding: 0,
            composerBottomPadding: 14,
            inputHorizontalPadding: 16
        )
    }
}

struct ChatHeaderView<Leading: View, Trailing: View>: View {
    let title: String
    let contextPathDisplay: String?
    let leading: () -> Leading
    let trailing: () -> Trailing
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(iOS)
        RokuricsMobilePageHeader(
            leading: leading,
            trailing: trailing
        ) {
            RokuricsSharedText(
                text: title,
                token: .pageTitle,
                size: RokuricsMobilePageLayoutMetrics.titleSize,
                weight: .bold
            )
                .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                .multilineTextAlignment(.leading)
        } subtitle: {
            if let contextPathDisplay {
                RokuricsSharedText(text: contextPathDisplay, token: .secondary)
                    .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                    .lineLimit(1)
            }
        }
        #else
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                leading()

                Spacer(minLength: 0)

                trailing()
            }

            VStack(alignment: .leading, spacing: 5) {
                RokuricsSharedText(text: title, token: .pageTitle, size: 32, weight: .bold)
                    .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                if let contextPathDisplay {
                    RokuricsSharedText(text: contextPathDisplay, token: .secondary)
                        .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

struct ChatPageBackButton: View {
    let action: () -> Void

    var body: some View {
        StudyLibraryPageBackButton(action: action)
    }
}

struct ChatErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(errorFont)
            .foregroundStyle(RokuricsSharedStyle.coral)
            .lineLimit(2)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .rokuricsSharedGlassCapsule(fillOpacity: 0.22, strokeOpacity: 0.20)
    }

    private var errorFont: Font {
        #if os(macOS)
        MacTypography.secondary(size: 11, weight: .medium)
        #else
        RokuricsTypography.font(for: .secondary)
        #endif
    }
}

struct ChatMessageRow: View {
    let role: ChatBubbleRole
    let content: String
    var attachmentNames: [String] = []

    init(role: ChatBubbleRole, content: String, attachmentNames: [String] = []) {
        self.role = role
        self.content = content
        self.attachmentNames = attachmentNames
    }

    #if os(iOS)
    init(message: IPhoneChatMessage) {
        self.init(role: message.role.chatBubbleRole, content: message.content)
    }
    #endif

    #if os(macOS)
    init(message: ChatMessage, attachments: [ChatAttachment] = []) {
        self.init(
            role: message.role.chatBubbleRole,
            content: message.content,
            attachmentNames: attachments.map(\.fileName)
        )
    }
    #endif

    var body: some View {
        ChatMessageBubble(role: role, content: content, attachmentNames: attachmentNames)
    }
}

struct ChatConversationView<Message: Identifiable, HeaderLeading: View, HeaderTrailing: View, PendingAttachments: View, MessageRow: View>: View {
    let title: String
    let contextPathDisplay: String?
    let messages: [Message]
    let greetingText: String
    let shouldShowGreeting: Bool
    let isGenerating: Bool
    @Binding var draft: String
    let errorMessage: String?
    let layout: ChatConversationLayout
    let headerLeading: () -> HeaderLeading
    let headerTrailing: () -> HeaderTrailing
    let pendingAttachments: () -> PendingAttachments
    let messageRow: (Message) -> MessageRow
    let onImportContext: () -> Void
    let onSend: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if layout.wrapsPageBackground {
                ZStack {
                    RokuricsSharedStyle.pageGradient(for: colorScheme)
                        .ignoresSafeArea()
                    conversation
                }
            } else {
                conversation
            }
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            if layout.showsHeader {
                ChatHeaderView(
                    title: title,
                    contextPathDisplay: contextPathDisplay,
                    leading: headerLeading,
                    trailing: headerTrailing
                )
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, layout.headerTopPadding)
                .padding(.bottom, layout.headerBottomPadding)
            }

            messageList

            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: layout.showsScrollIndicators) {
                LazyVStack(alignment: .leading, spacing: layout.messageSpacing) {
                    if shouldShowGreeting {
                        constrainedContent {
                            ChatGreetingView(text: greetingText)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.top, layout.greetingTopPadding)
                    }

                    ForEach(messages) { message in
                        constrainedContent {
                            messageRow(message)
                        }
                        .id(message.id)
                    }

                    if isGenerating {
                        constrainedContent {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    if let errorMessage {
                        constrainedContent {
                            ChatErrorBanner(message: errorMessage)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(.top, layout.messageTopPadding)
                .padding(.bottom, layout.messageBottomPadding)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: messages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: isGenerating) {
                scrollToBottom(proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            pendingAttachments()
                .chatConstrained(maxWidth: layout.contentMaxWidth)

            ChatInputBar(
                text: $draft,
                isSending: isGenerating,
                onImportContext: onImportContext,
                onSend: onSend
            )
            .chatConstrained(maxWidth: layout.contentMaxWidth)
        }
        .padding(.horizontal, layout.inputHorizontalPadding)
        .padding(.top, layout.composerTopPadding)
        .padding(.bottom, layout.composerBottomPadding)
    }

    private func constrainedContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .chatConstrained(maxWidth: layout.contentMaxWidth)
            .padding(.horizontal, layout.horizontalPadding)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }
}

private extension View {
    func chatConstrained(maxWidth: CGFloat?) -> some View {
        Group {
            if let maxWidth {
                self
                    .frame(maxWidth: maxWidth, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                self
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

enum ChatBubbleRole {
    case user
    case assistant
    case system
}

struct ChatMessageBubble: View {
    let role: ChatBubbleRole
    let content: String
    var attachmentNames: [String] = []
    @Environment(\.colorScheme) private var colorScheme

    init(role: ChatBubbleRole, content: String, attachmentNames: [String] = []) {
        self.role = role
        self.content = content
        self.attachmentNames = attachmentNames
    }

    #if os(iOS)
    init(message: IPhoneChatMessage) {
        self.init(role: message.role.chatBubbleRole, content: message.content)
    }
    #endif

    #if os(macOS)
    init(message: ChatMessage, attachments: [ChatAttachment] = []) {
        self.init(
            role: message.role.chatBubbleRole,
            content: message.content,
            attachmentNames: attachments.map(\.fileName)
        )
    }
    #endif

    var body: some View {
        switch role {
        case .system:
            EmptyView()
        case .user, .assistant:
            HStack(alignment: .top, spacing: 0) {
                if role == .user {
                    Spacer(minLength: spacerLength)
                }

                bubbleContent
                    .frame(maxWidth: maxBubbleWidth, alignment: role == .user ? .trailing : .leading)

                if role == .assistant {
                    Spacer(minLength: spacerLength)
                }
            }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if role == .user {
            VStack(alignment: .trailing, spacing: 7) {
                RokuricsSharedText(text: content, token: .chatMessage)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .lineSpacing(4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RokuricsSharedStyle.actionGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                attachmentRow
            }
        } else {
            markdownText
                .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                .textSelection(.enabled)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var attachmentRow: some View {
        if !attachmentNames.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(attachmentNames, id: \.self) { name in
                        Label(name, systemImage: "paperclip")
                            .font(attachmentFont)
                            .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .rokuricsSharedGlassCapsule(fillOpacity: 0.26, strokeOpacity: 0.24)
                    }
                }
            }
        }
    }

    private var markdownText: some View {
        Group {
            if let attributed = try? AttributedString(markdown: content) {
                Text(scriptAwareAttributedString(attributed))
            } else {
                RokuricsSharedText(text: content, token: .chatMessage)
            }
        }
    }

    private func scriptAwareAttributedString(_ attributed: AttributedString) -> AttributedString {
        var result = attributed
        #if os(macOS)
        MacTypography.applyMixedScriptFonts(to: &result, style: MacTypography.mixedStyle(for: .chatMessage))
        #else
        let plainText = String(result.characters)
        result = RokuricsTypography.attributedString(for: plainText, token: .chatMessage)
        #endif
        return result
    }

    private var spacerLength: CGFloat {
        #if os(macOS)
        80
        #else
        46
        #endif
    }

    private var maxBubbleWidth: CGFloat {
        #if os(macOS)
        680
        #else
        .infinity
        #endif
    }

    private var attachmentFont: Font {
        #if os(macOS)
        MacTypography.chineseCaption(size: 11, weight: .semibold)
        #else
        RokuricsTypography.secondary(size: 11, weight: .semibold)
        #endif
    }
}

#if os(iOS)
private extension IPhoneChatRole {
    var chatBubbleRole: ChatBubbleRole {
        switch self {
        case .system: return .system
        case .user: return .user
        case .assistant: return .assistant
        }
    }
}
#endif

#if os(macOS)
private extension ChatMessageRole {
    var chatBubbleRole: ChatBubbleRole {
        switch self {
        case .system: return .system
        case .user: return .user
        case .assistant: return .assistant
        }
    }
}
#endif

struct ChatAttachmentButton: View {
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        RokuricsGlassIconButton(
            systemImage: "paperclip",
            accessibilityTitle: RokuricsCopy.text("添加附件", "Add Attachment"),
            tint: nil,
            isEnabled: isEnabled,
            role: nil,
            action: action
        )
    }
}

struct ChatInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let onImportContext: () -> Void
    let onSend: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ChatAttachmentButton(isEnabled: !isSending, action: onImportContext)

            TextField(RokuricsCopy.text("消息", "Message"), text: $text, axis: .vertical)
                .font(inputFont)
                .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                .lineLimit(1...4)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .disabled(isSending)

            RokuricsGlassIconButton(
                systemImage: isSending ? "arrow.triangle.2.circlepath" : "arrow.up",
                accessibilityTitle: RokuricsCopy.text("发送", "Send"),
                tint: RokuricsSharedStyle.aqua,
                isEnabled: canSend,
                role: nil,
                action: onSend
            )
            .opacity(canSend ? 1 : 0.48)
        }
        .padding(10)
        .rokuricsSharedGlassCard(cornerRadius: 24, fillOpacity: 0.38, strokeOpacity: 0.34, shadowOpacity: 0.08, shadowRadius: 12, shadowY: 5)
    }

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputFont: Font {
        #if os(macOS)
        MacTypography.chatInput()
        #else
        RokuricsTypography.font(for: .chatInput)
        #endif
    }
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
            return RokuricsCopy.text("最近对话", "Recent Chats")
        case .newConversation:
            return RokuricsCopy.text("新建对话", "New Chat")
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

struct ChatConversationButtonGroup: View {
    let recentAction: () -> Void
    let newConversationAction: () -> Void
    @State private var hoveredControl: ChatTopControl?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(iOS)
        RokuricsIconButtonGroup {
            RokuricsIconButtonGroupItem(
                systemName: ChatTopControl.recentConversations.systemImage,
                accessibilityLabel: ChatTopControl.recentConversations.accessibilityTitle,
                action: recentAction
            )

            RokuricsIconButtonGroupSeparator()

            RokuricsIconButtonGroupItem(
                systemName: ChatTopControl.newConversation.systemImage,
                accessibilityLabel: ChatTopControl.newConversation.accessibilityTitle,
                action: newConversationAction
            )
        }
        #else
        HStack(spacing: 0) {
            topButton(.recentConversations, action: recentAction)

            Rectangle()
                .fill(RokuricsSharedStyle.tertiaryText(for: colorScheme).opacity(0.28))
                .frame(
                    width: ChatTopControlGroupConfiguration.separatorWidth,
                    height: ChatTopControlGroupConfiguration.itemHeight - 12
                )

            topButton(.newConversation, action: newConversationAction)
        }
        .padding(2)
        .rokuricsSharedGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.34)
        .clipShape(Capsule(style: .continuous))
        #endif
    }

    private func topButton(_ control: ChatTopControl, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: control.systemImage)
                .font(.system(size: ChatTopControlGroupConfiguration.iconSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                .frame(
                    width: ChatTopControlGroupConfiguration.itemWidth,
                    height: ChatTopControlGroupConfiguration.itemHeight
                )
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(hoveredControl == control ? RokuricsSharedStyle.tertiaryText(for: colorScheme).opacity(0.14) : .clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        #if os(macOS)
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredControl = isHovering ? control : nil
        }
        #else
        .buttonStyle(RokuricsScaleButtonStyle())
        #endif
        .accessibilityLabel(control.accessibilityTitle)
    }
}

struct ChatRecentConversationListView: View {
    let conversations: [ChatConversation]
    let activeConversationID: String
    let onSelect: (ChatConversation) -> Void
    let onDelete: (ChatConversation) -> Void
    var limit = 12
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if conversations.isEmpty {
                RokuricsSharedText(text: RokuricsCopy.text("暂无对话", "No chats"), token: .body, size: 13, weight: .medium)
                    .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let displayedConversations = Array(conversations.prefix(limit))
                ForEach(displayedConversations) { conversation in
                    ChatRecentConversationRow(
                        conversation: conversation,
                        isActive: conversation.id == activeConversationID,
                        onSelect: {
                            onSelect(conversation)
                        },
                        onDelete: {
                            onDelete(conversation)
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
        .rokuricsSharedGlassCard(cornerRadius: 18, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.06, shadowRadius: 10, shadowY: 5)
    }
}

private struct ChatRecentConversationRow: View {
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
            #if os(macOS)
            .buttonStyle(.plain)
            #else
            .buttonStyle(RokuricsScaleButtonStyle())
            #endif

            #if os(iOS)
            RokuricsGlassIconButton(
                systemImage: "trash",
                accessibilityTitle: RokuricsCopy.text("删除对话", "Delete Chat"),
                tint: RokuricsSharedStyle.coral,
                role: .destructive,
                action: onDelete
            )
            #else
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RokuricsSharedStyle.coral)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(RokuricsCopy.text("删除对话", "Delete Chat"))
            #endif
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 9)
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "text.bubble")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? RokuricsSharedStyle.leaf : RokuricsSharedStyle.softText(for: colorScheme))
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    RokuricsSharedText(text: conversation.title, token: .secondary, size: 13, weight: .semibold)
                        .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(conversation.updatedAt.formatted(date: .omitted, time: .shortened))
                        .font(timestampFont)
                        .foregroundStyle(RokuricsSharedStyle.tertiaryText(for: colorScheme))
                        .lineLimit(1)
                }

                if let contextPath = conversation.contextPathDisplay {
                    RokuricsSharedText(text: contextPath, token: .secondary, size: 11, weight: .medium)
                        .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let preview = conversation.lastMessagePreview {
                    RokuricsSharedText(text: preview, token: .secondary, size: 11, weight: .medium)
                        .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var timestampFont: Font {
        #if os(macOS)
        MacTypography.numberBody(size: 11, weight: .medium)
        #else
        RokuricsTypography.numberBody(size: 11, weight: .medium)
        #endif
    }
}

struct ChatAttachmentChipRow: View {
    let attachments: [ChatAttachment]
    let onRemove: ((ChatAttachment) -> Void)?

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(attachments) { attachment in
                        ChatAttachmentChip(attachment: attachment, onRemove: onRemove)
                    }
                }
            }
        }
    }
}

private struct ChatAttachmentChip: View {
    let attachment: ChatAttachment
    let onRemove: ((ChatAttachment) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))

            RokuricsSharedText(text: attachment.fileName, token: .secondary, size: 11, weight: .semibold)
                .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160)

            if let onRemove {
                Button {
                    onRemove(attachment)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(RokuricsSharedStyle.tertiaryText(for: colorScheme))
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #else
                .buttonStyle(RokuricsScaleButtonStyle())
                #endif
                .accessibilityLabel(RokuricsCopy.text("移除附件", "Remove Attachment"))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .rokuricsSharedGlassCapsule(fillOpacity: 0.26, strokeOpacity: 0.24)
    }

    private var systemImage: String {
        switch attachment.kind {
        case .image:
            return "photo"
        case .document:
            return "doc"
        case .audio:
            return "waveform"
        case .other:
            return "paperclip"
        }
    }
}

enum ChatStudyLibraryPickerSelection: Equatable {
    case folder(StudyBrowsePath)
    case item(StudyItemMetadata)
}

struct ChatStudyLibraryPickerView: View {
    @ObservedObject var studyLibraryStore: StudyLibraryStore
    let onCancel: () -> Void
    let onImport: (ChatStudyLibraryPickerSelection) -> Void
    @State private var browsePath = StudyBrowsePath()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()
                .opacity(0.28)

            browser
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .background(RokuricsSharedStyle.pageGradient(for: colorScheme))
        .onAppear {
            studyLibraryStore.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            StudyLibraryFolderBackButton(isEnabled: !browsePath.isRoot) {
                browsePath = browsePath.parent
            }

            StudyBreadcrumb(path: browsePath) { path in
                browsePath = path
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Button(RokuricsCopy.text("取消", "Cancel"), action: onCancel)
                .font(buttonFont)

            Button(RokuricsCopy.text("导入当前文件夹", "Import Folder")) {
                onImport(.folder(browsePath))
            }
            .font(buttonEmphasisFont)
            .disabled(studyLibraryStore.allStudyItems.isEmpty)
        }
    }

    private var browser: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(browseContent.folders) { folder in
                    ChatStudyLibraryPickerRow(
                        systemImage: "folder",
                        title: folder.title,
                        detail: RokuricsCopy.itemCount(folder.itemCount),
                        actionSystemImage: "chevron.right",
                        action: {
                            browsePath = folder.path
                        }
                    )
                }

                ForEach(browseContent.items) { item in
                    ChatStudyLibraryPickerRow(
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
                    Text(RokuricsCopy.text("暂无内容", "No content"))
                        .font(buttonFont)
                        .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                        .padding(.vertical, 16)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var browseContent: StudyBrowseContent {
        StudyLibraryBrowser.content(
            items: studyLibraryStore.allStudyItems,
            folders: studyLibraryStore.allStudyFolders,
            path: browsePath
        )
    }

    private var buttonFont: Font {
        #if os(macOS)
        MacTypography.secondary(size: 13, weight: .medium)
        #else
        RokuricsTypography.font(for: .secondary)
        #endif
    }

    private var buttonEmphasisFont: Font {
        #if os(macOS)
        MacTypography.secondary(size: 13, weight: .semibold)
        #else
        RokuricsTypography.secondary(size: 12, weight: .bold)
        #endif
    }
}

private struct ChatStudyLibraryPickerRow: View {
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
                    .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    RokuricsSharedText(text: title, token: .cardTitle, size: 13, weight: .semibold)
                        .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                        .lineLimit(1)

                    RokuricsSharedText(text: detail, token: .secondary, size: 11, weight: .medium)
                        .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Image(systemName: actionSystemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RokuricsSharedStyle.tertiaryText(for: colorScheme))
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(RokuricsSharedStyle.tertiaryText(for: colorScheme).opacity(0.12))
            }
            .contentShape(Rectangle())
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .buttonStyle(RokuricsScaleButtonStyle())
        #endif
    }
}
