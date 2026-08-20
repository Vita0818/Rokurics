//
//  ChatFeatureTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/5/20.
//

import Foundation
import Testing
@testable import RokuricsMac

struct ChatFeatureTests {
    @Test func sidebarContainsAIChatBesideCoreEntries() {
        #expect(MacSidebarItem.allCases == [.studyLibrary, .aiChat, .iPhoneConnection])
        #expect(MacSidebarItem.allCases.contains(.aiChat))
        #expect(!MacSidebarItem.allCases.contains(.audioInbox))
        #expect(!MacSidebarItem.allCases.contains(.dashboard))
        #expect(MacSidebarItem.aiChat.title == "AI 对话")
    }

    @Test func chatMessageEncodesAndDecodes() throws {
        let message = ChatMessage(
            id: "message-01",
            role: .user,
            content: "矩阵乘法怎么复习？",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        let data = try Self.encoder.encode(message)
        let decoded = try Self.decoder.decode(ChatMessage.self, from: data)

        #expect(decoded == message)
    }

    @Test func chatConversationEncodesAndDecodes() throws {
        let conversation = ChatConversation(
            id: "conversation-01",
            title: "线性代数",
            titleGeneratedAt: Date(timeIntervalSince1970: 2_002),
            titleSource: .aiGenerated,
            messages: [
                ChatMessage(id: "user-01", role: .user, content: "有哪些重点？", createdAt: Date(timeIntervalSince1970: 2_000), attachmentIDs: ["attachment-01"]),
                ChatMessage(id: "assistant-01", role: .assistant, content: "重点是矩阵乘法。", createdAt: Date(timeIntervalSince1970: 2_001))
            ],
            activeContextID: "context-01",
            contextPathDisplay: "学习库 / 数学 / 线性代数",
            contextItemCount: 2,
            lastMessagePreview: "重点是矩阵乘法。",
            attachmentIDs: ["attachment-01"],
            attachments: [
                ChatAttachment(
                    id: "attachment-01",
                    conversationID: "conversation-01",
                    fileName: "matrix.png",
                    fileType: "png",
                    mimeType: "image/png",
                    relativePath: "chats/attachments/conversation-01/attachment-01-matrix.png",
                    sizeBytes: 128,
                    createdAt: Date(timeIntervalSince1970: 1_999),
                    kind: .image
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_900),
            updatedAt: Date(timeIntervalSince1970: 2_001)
        )

        let data = try Self.encoder.encode(conversation)
        let decoded = try Self.decoder.decode(ChatConversation.self, from: data)

        #expect(decoded == conversation)
    }

    @Test func chatAttachmentEncodesAndDecodes() throws {
        let attachment = ChatAttachment(
            id: "attachment-01",
            conversationID: "conversation-01",
            fileName: "notes.pdf",
            fileType: "pdf",
            mimeType: "application/pdf",
            relativePath: "chats/attachments/conversation-01/attachment-01-notes.pdf",
            sizeBytes: 42,
            createdAt: Date(timeIntervalSince1970: 2_200),
            kind: .document
        )

        let data = try Self.encoder.encode(attachment)
        let decoded = try Self.decoder.decode(ChatAttachment.self, from: data)

        #expect(decoded == attachment)
    }

    @Test func chatContextEncodesAndDecodes() throws {
        let context = ChatContext(
            id: "context-01",
            title: "线性代数",
            browsePathComponents: ["课堂", "线性代数"],
            itemCount: 1,
            items: [
                ChatContextItem(
                    id: "item-01",
                    title: "矩阵乘法",
                    filingPath: StudyFilingPath(type: "课堂", subject: "线性代数"),
                    content: "矩阵乘法满足结合律。"
                )
            ],
            sourceKind: .studyItem,
            sourceItemID: "item-01",
            contextPathDisplay: "学习库 / 课堂 / 线性代数 / 矩阵乘法",
            itemTitle: "矩阵乘法",
            createdAt: Date(timeIntervalSince1970: 3_000),
            maxContextCharacters: 20_000
        )

        let data = try Self.encoder.encode(context)
        let decoded = try Self.decoder.decode(ChatContext.self, from: data)

        #expect(decoded == context)
        #expect(decoded.pathDisplay == "学习库 / 课堂 / 线性代数 / 矩阵乘法")
    }

    @Test func contextExporterCollectsItemsUnderCurrentFolderPath() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let items = Self.makeScopeItems()
        let exporter = StudyLibraryContextExporter(rootURL: rootURL)

        let context = exporter.export(
            items: items,
            path: StudyBrowsePath(components: ["课堂", "线性代数"])
        )

        #expect(context.itemCount == 2)
        #expect(Set(context.items.map(\.id)) == Set(["item_recording_la-matrix", "item_recording_la-determinant"]))
        #expect(context.displayTitle == "线性代数")
    }

    @Test func typeLayerImportOnlyIncludesItemsUnderThatType() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let context = StudyLibraryContextExporter(rootURL: rootURL).export(
            items: Self.makeScopeItems(),
            path: StudyBrowsePath(components: ["课堂"])
        )

        #expect(context.itemCount == 3)
        #expect(Set(context.items.map(\.id)) == Set(["item_recording_la-matrix", "item_recording_la-determinant", "item_recording_calc-green"]))
    }

    @Test func subjectLayerImportOnlyIncludesItemsUnderThatSubject() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let context = StudyLibraryContextExporter(rootURL: rootURL).export(
            items: Self.makeScopeItems(),
            path: StudyBrowsePath(components: ["课堂", "线性代数"])
        )

        #expect(context.itemCount == 2)
        #expect(Set(context.items.map(\.id)) == Set(["item_recording_la-matrix", "item_recording_la-determinant"]))
    }

    @Test func chapterLayerImportOnlyIncludesItemsUnderThatChapter() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let context = StudyLibraryContextExporter(rootURL: rootURL).export(
            items: Self.makeScopeItems(),
            path: StudyBrowsePath(components: ["课堂", "线性代数", "矩阵"])
        )

        #expect(context.itemCount == 1)
        #expect(context.items.map(\.id) == ["item_recording_la-matrix"])
    }

    @Test func topicLayerImportOnlyIncludesItemsUnderThatTopic() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let context = StudyLibraryContextExporter(rootURL: rootURL).export(
            items: Self.makeScopeItems(),
            path: StudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"])
        )

        #expect(context.itemCount == 1)
        #expect(context.items.first?.title == "矩阵乘法")
    }

    @Test func contextBuilderPrefersNoteSummaryPreview() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try writeNote(rootURL: rootURL, recordingID: "priority", summary: "安全摘要", keyPoints: ["矩阵乘法定义"])
        try writeTranscript(rootURL: rootURL, recordingID: "priority", markdown: "transcript fallback should not win")
        let item = Self.makeItem(
            id: "priority",
            title: "矩阵乘法",
            filing: StudyFilingPath(type: "课堂", subject: "线性代数"),
            noteRelativePath: "notes/1970-01-01/priority/note.md",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/priority/transcript.md"
        )

        let context = StudyLibraryContextExporter(rootURL: rootURL).export(items: [item], path: StudyBrowsePath(components: ["课堂"]))
        let content = try #require(context.items.first?.content)

        #expect(content.contains("安全摘要"))
        #expect(content.contains("矩阵乘法定义"))
        #expect(!content.contains("transcript fallback"))
    }

    @Test func contextBuilderFallsBackToTranscriptPreviewWhenNoteIsMissing() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try writeTranscript(rootURL: rootURL, recordingID: "fallback", markdown: "## Transcript\n矩阵乘法需要行列匹配。")
        let item = Self.makeItem(
            id: "fallback",
            title: "转写内容",
            filing: StudyFilingPath(type: "课堂"),
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/fallback/transcript.md"
        )

        let context = StudyLibraryContextExporter(rootURL: rootURL).export(items: [item], path: StudyBrowsePath(components: ["课堂"]))

        #expect(context.items.first?.content.contains("矩阵乘法需要行列匹配") == true)
        #expect(context.items.first?.sourcePath == "transcript")
    }

    @Test func contextBuilderTruncatesLargeContext() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try writeNoteMarkdown(rootURL: rootURL, recordingID: "long", markdown: "# 长笔记\n" + String(repeating: "矩阵乘法", count: 200))
        let item = Self.makeItem(
            id: "long",
            title: "长笔记",
            filing: StudyFilingPath(type: "课堂"),
            noteRelativePath: "notes/1970-01-01/long/note.md"
        )
        let options = ChatContextBuildOptions(maxContextCharacters: 80, maxCharactersPerItem: 80, maxNoteCharacters: 200)
        let context = StudyLibraryContextExporter(rootURL: rootURL, options: options).export(items: [item], path: StudyBrowsePath(components: ["课堂"]))

        #expect(context.isTruncated)
        #expect((context.items.first?.content.count ?? 0) <= 80)
    }

    @Test func contextBuilderFiltersSensitiveDebugMaterial() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try writeNoteMarkdown(
            rootURL: rootURL,
            recordingID: "safe",
            markdown: """
            # 安全笔记
            保留这条学习内容。
            API key: sk-secret
            sharedSecret: local-secret
            response JSON: {"debug": true}
            HMAC pairing info
            """
        )
        let item = Self.makeItem(
            id: "safe",
            title: "安全笔记",
            filing: StudyFilingPath(type: "课堂"),
            noteRelativePath: "notes/1970-01-01/safe/note.md"
        )
        let context = StudyLibraryContextExporter(rootURL: rootURL).export(items: [item], path: StudyBrowsePath(components: ["课堂"]))
        let content = try #require(context.items.first?.content)

        #expect(content.contains("保留这条学习内容"))
        #expect(!content.lowercased().contains("api key"))
        #expect(!content.contains("sk-secret"))
        #expect(!content.contains("sharedSecret"))
        #expect(!content.lowercased().contains("response json"))
        #expect(!content.lowercased().contains("hmac"))
    }

    @Test func singleStudyItemImportCreatesOneItemContextWithMetadata() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try writeNoteMarkdown(rootURL: rootURL, recordingID: "single", markdown: "## 摘要\n矩阵乘法需要行列匹配。")
        let item = Self.makeItem(
            id: "single",
            title: "矩阵乘法",
            filing: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "乘法"),
            noteRelativePath: "notes/1970-01-01/single/note.md"
        )

        let context = StudyLibraryContextExporter(rootURL: rootURL).export(item: item)

        #expect(context.sourceKind == .studyItem)
        #expect(context.sourceItemID == "item_recording_single")
        #expect(context.itemTitle == "矩阵乘法")
        #expect(context.itemCount == 1)
        #expect(context.items.map(\.id) == ["item_recording_single"])
        #expect(context.pathDisplay == "学习库 / 课堂 / 线性代数 / 矩阵 / 乘法 / 矩阵乘法")
        #expect(context.items.first?.content.contains("矩阵乘法需要行列匹配") == true)
    }

    @Test func singleStudyItemImportFiltersSensitiveMaterial() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try writeNoteMarkdown(
            rootURL: rootURL,
            recordingID: "single-safe",
            markdown: """
            # 单项笔记
            保留这条单项学习内容。
            API key: sk-secret
            sharedSecret: local-secret
            response JSON: {"debug": true}
            HMAC pairing info
            """
        )
        let item = Self.makeItem(
            id: "single-safe",
            title: "安全单项",
            filing: StudyFilingPath(type: "课堂"),
            noteRelativePath: "notes/1970-01-01/single-safe/note.md"
        )

        let context = StudyLibraryContextExporter(rootURL: rootURL).export(item: item)
        let content = try #require(context.items.first?.content)

        #expect(content.contains("保留这条单项学习内容"))
        #expect(!content.lowercased().contains("api key"))
        #expect(!content.contains("sk-secret"))
        #expect(!content.contains("sharedSecret"))
        #expect(!content.lowercased().contains("response json"))
        #expect(!content.lowercased().contains("hmac"))
    }

    @Test @MainActor func chatProviderFactoryUsesCurrentAISettings() throws {
        let defaults = try Self.makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: Self.defaultsSuiteName) }
        let settingsStore = NoteGenerationSettingsStore(userDefaults: defaults)

        settingsStore.update(
            providerKind: .mock,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration()
        )
        #expect(ChatProviderFactory.provider(for: settingsStore).id == "mockChatProvider")

        settingsStore.update(
            providerKind: .openAICompatible,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(modelName: "chat-model")
        )
        #expect(ChatProviderFactory.provider(for: settingsStore).id == "openAICompatibleChatProvider")

        settingsStore.update(
            providerKind: .anthropicMessages,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(),
            anthropicConfiguration: AnthropicMessagesConfiguration(apiKey: "test-key")
        )
        #expect(ChatProviderFactory.provider(for: settingsStore).id == "anthropicMessagesChatProvider")
    }

    @Test func mockChatProviderReturnsTestReply() async throws {
        let provider = MockChatProvider()
        let result = try await provider.send(
            request: ChatRequest(
                messages: [ChatMessage(role: .user, content: "矩阵乘法")],
                context: nil,
                modelName: nil,
                maxTokens: 100,
                temperature: 0.1
            )
        )

        #expect(result.providerID == "mockChatProvider")
        #expect(result.message.role == .assistant)
        #expect(result.message.content.contains("矩阵乘法"))
    }

    @Test @MainActor func sendingMessageAppendsUserAndAssistantMessages() async throws {
        let coordinator = ChatCoordinator(
            providerResolver: { MockChatProvider() },
            conversationStore: nil
        )

        await coordinator.send("矩阵乘法怎么复习？")

        #expect(coordinator.visibleMessages.map(\.role) == [.user, .assistant])
        #expect(coordinator.visibleMessages.first?.content == "矩阵乘法怎么复习？")
        #expect(coordinator.visibleMessages.last?.content.contains("矩阵乘法怎么复习") == true)
    }

    @Test @MainActor func emptyConversationDoesNotCreateWelcomeMessage() {
        let coordinator = ChatCoordinator(
            providerResolver: { MockChatProvider() },
            conversationStore: nil
        )

        #expect(coordinator.visibleMessages.isEmpty)
        #expect(coordinator.conversation.title == "新对话")
    }

    @Test func emptyConversationGreetingUsesUserNameAndTimePeriod() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let morning = try Self.date(hour: 8, calendar: calendar)
        let afternoon = try Self.date(hour: 14, calendar: calendar)
        let evening = try Self.date(hour: 21, calendar: calendar)
        let lateNight = try Self.date(hour: 3, calendar: calendar)

        #expect(ChatGreeting.make(userName: "Ari", defaultName: MacUserProfile.defaultDisplayName, date: morning, calendar: calendar).text == "Ari，早上好！")
        #expect(ChatGreeting.make(userName: "Ari", defaultName: MacUserProfile.defaultDisplayName, date: afternoon, calendar: calendar).text == "Ari，下午好！")
        #expect(ChatGreeting.make(userName: "Ari", defaultName: MacUserProfile.defaultDisplayName, date: evening, calendar: calendar).text == "Ari，晚上好！")
        #expect(ChatGreeting.make(userName: "Ari", defaultName: MacUserProfile.defaultDisplayName, date: lateNight, calendar: calendar).text == "Ari，晚上好！")
    }

    @Test func emptyConversationGreetingUsesProfileDisplayName() {
        let profile = MacUserProfile(displayName: " Vivian ", handle: "vivian")
        let greeting = ChatGreeting.make(userName: profile.displayName, defaultName: MacUserProfile.defaultDisplayName, date: Date(timeIntervalSince1970: 0), calendar: .current)

        #expect(greeting.text.contains("Vivian"))
    }

    @Test func chatTypographyUsesDedicatedChatStyles() {
        #expect(RokuricsTextStyle.allCases == [
            .pageTitle,
            .pageSubtitle,
            .sectionTitle,
            .cardTitle,
            .body,
            .secondary,
            .chatGreeting,
            .chatMessage,
            .chatInput,
            .technical
        ])
        #expect(RokuricsTextStyle.chatGreeting != .pageTitle)
        #expect(RokuricsTextStyle.chatMessage != .pageTitle)
        #expect(RokuricsTextStyle.chatInput != .pageTitle)
        #expect(MacTypography.chatGreetingSpec != MacTypography.pageTitleSpec)
        #expect(MacTypography.chatGreetingSpec.family == .jetBrainsMono)
        #expect(MacTypography.chatGreetingSpec.size == 24)
        #expect(MacTypography.chatGreetingSpec.weight == .semibold)
        #expect(MacTypography.chatInputSpec != MacTypography.pageTitleSpec)
        #expect(MacTypography.chatMessageSpec != MacTypography.pageTitleSpec)

        let greetingStyle = MacTypography.mixedStyle(for: .chatGreeting)
        #expect(greetingStyle.latin.family == .jetBrainsMono)
        #expect(greetingStyle.chinese.family == .jetBrainsMono)
        #expect(greetingStyle.punctuation.family == .jetBrainsMono)
        #expect(greetingStyle.number.family == .jetBrainsMono)
        #expect(greetingStyle.number.usesMonospacedDigits)
        #expect(greetingStyle.technical.family == .jetBrainsMono)
    }

    @Test func mixedScriptTypographySplitsGreetingByCharacterClass() {
        let runs = MacMixedTextRun.runs(in: "Vita，晚上好！")

        #expect(runs == [
            MacMixedTextRun(kind: .latin, value: "Vita"),
            MacMixedTextRun(kind: .punctuation, value: "，"),
            MacMixedTextRun(kind: .chinese, value: "晚上好"),
            MacMixedTextRun(kind: .punctuation, value: "！")
        ])
    }

    @Test func mixedScriptTypographyKeepsNumbersAndTechnicalTextInJetBrainsMonoRuns() {
        #expect(MacMixedTextRun.runs(in: "录音 2026-05-16 12:46").map(\.kind) == [
            .chinese,
            .punctuation,
            .number,
            .punctuation,
            .number
        ])
        #expect(MacMixedTextRun.runs(in: "transcripts/2026-05-16/recording-01/transcript.md") == [
            MacMixedTextRun(kind: .technical, value: "transcripts/2026-05-16/recording-01/transcript.md")
        ])
        #expect(MacMixedTextRun.runs(in: "127.0.0.1:8848") == [
            MacMixedTextRun(kind: .technical, value: "127.0.0.1:8848")
        ])
        #expect(MacMixedTextRun.runs(in: "recording-01") == [
            MacMixedTextRun(kind: .technical, value: "recording-01")
        ])
        #expect(MacMixedTextRun.runs(in: "Provider: OpenAI-compatible").map(\.kind) == [
            .latin,
            .punctuation,
            .latin
        ])
    }

    @Test func chatToolbarDoesNotUseWindowOverlayLayout() {
        #expect(!MacAIChatToolbarLayout.usesWindowOverlay)
        #expect(MacAIChatToolbarLayout.placement == "navigation")
    }

    @Test func chatTopControlsUseSharedGlassCapsuleInsteadOfIndependentCircles() {
        #expect(ChatTopControl.allCases == [.recentConversations, .newConversation])
        #expect(ChatTopControl.recentConversations.systemImage == "sidebar.left")
        #expect(ChatTopControl.newConversation.systemImage == "square.and.pencil")
        #expect(ChatTopControl.recentConversations.accessibilityTitle == "最近对话")
        #expect(ChatTopControl.newConversation.accessibilityTitle == "新建对话")
        #expect(ChatTopControlGroupConfiguration.usesSharedGlassCapsule)
        #expect(!ChatTopControlGroupConfiguration.usesIndependentCircularButtons)
        #expect(ChatTopControlGroupConfiguration.usesSystemSymbols)
        #expect(ChatTopControlGroupConfiguration.borderWidth == 1)
        #expect(ChatTopControlGroupConfiguration.itemWidth != ChatTopControlGroupConfiguration.itemHeight)
        #expect(ChatTopControlGroupConfiguration.separatorWidth == 1)
    }

    @Test func attachmentMenuContainsStudyLibraryAndUploadEntries() {
        let titles = MacAIChatAttachmentMenuAction.allCases.map(\.title)

        #expect(titles.contains("导入学习库内容"))
        #expect(titles.contains("上传文件"))
        #expect(titles.contains("上传图片"))
    }

    @Test @MainActor func creatingNewConversationGeneratesNewConversationID() {
        let coordinator = ChatCoordinator(
            providerResolver: { MockChatProvider() },
            conversationStore: nil
        )
        let originalID = coordinator.conversation.id

        coordinator.createNewConversation()

        #expect(coordinator.conversation.id != originalID)
        #expect(coordinator.visibleMessages.isEmpty)
        #expect(coordinator.activeContext == nil)
    }

    @Test @MainActor func creatingNewConversationDoesNotReuseOldMessages() async throws {
        let coordinator = ChatCoordinator(
            providerResolver: { MockChatProvider() },
            conversationStore: nil
        )

        await coordinator.send("旧对话消息")
        let previousConversationID = coordinator.conversation.id

        coordinator.createNewConversation()

        #expect(coordinator.conversation.id != previousConversationID)
        #expect(coordinator.visibleMessages.isEmpty)
    }

    @Test @MainActor func switchingRecentConversationLoadsItsMessages() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let store = ChatConversationStore(rootURL: rootURL)
        let older = ChatConversation(
            id: "conversation-older",
            title: "较早对话",
            messages: [ChatMessage(role: .user, content: "旧消息")],
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = ChatConversation(
            id: "conversation-newer",
            title: "较新对话",
            messages: [ChatMessage(role: .user, content: "新消息")],
            createdAt: Date(timeIntervalSince1970: 2_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        try store.saveConversation(older)
        try store.saveConversation(newer)

        let coordinator = ChatCoordinator(
            providerResolver: { MockChatProvider() },
            conversationStore: store
        )
        #expect(coordinator.conversation.id == "conversation-newer")

        coordinator.selectConversation(id: "conversation-older")

        #expect(coordinator.conversation.id == "conversation-older")
        #expect(coordinator.visibleMessages.first?.content == "旧消息")
    }

    @Test @MainActor func importingContextSetsActiveChatContext() {
        let coordinator = ChatCoordinator(
            providerResolver: { MockChatProvider() },
            conversationStore: nil
        )
        let context = ChatContext(
            id: "context-active",
            title: "线性代数",
            browsePathComponents: ["数学", "线性代数"],
            itemCount: 1,
            items: [],
            maxContextCharacters: 20_000
        )
        let previousConversationID = coordinator.conversation.id

        coordinator.importContext(context)

        #expect(coordinator.activeContext == context)
        #expect(coordinator.conversation.activeContextID == "context-active")
        #expect(coordinator.conversation.id != previousConversationID)
        #expect(coordinator.conversation.contextPathDisplay == "学习库 / 数学 / 线性代数")
        #expect(coordinator.conversation.contextItemCount == 1)
        #expect(coordinator.conversation.title == "线性代数对话")
    }

    @Test @MainActor func importingSingleStudyItemCreatesIndependentConversationWithoutProviderCall() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let provider = CapturingChatProvider(titleResult: .success("不会调用"))
        let coordinator = ChatCoordinator(
            providerResolver: { provider },
            conversationStore: nil
        )
        let context = StudyLibraryContextExporter(rootURL: rootURL).export(
            item: Self.makeItem(
                id: "single-import",
                title: "矩阵课",
                filing: StudyFilingPath(type: "课堂", subject: "线性代数")
            )
        )
        let previousConversationID = coordinator.conversation.id

        coordinator.importContext(context)

        #expect(coordinator.conversation.id != previousConversationID)
        #expect(coordinator.conversation.title == "矩阵课")
        #expect(coordinator.conversation.activeContextID == context.id)
        #expect(coordinator.conversation.contextPathDisplay == context.pathDisplay)
        #expect(provider.sentRequests.isEmpty)
        #expect(provider.titleRequests.isEmpty)
    }

    @Test @MainActor func importingFolderCreatesContextWithoutProviderCall() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let provider = CapturingChatProvider(titleResult: .success("不会调用"))
        let coordinator = ChatCoordinator(
            providerResolver: { provider },
            conversationStore: nil
        )
        let context = StudyLibraryContextExporter(rootURL: rootURL).export(
            items: Self.makeScopeItems(),
            path: StudyBrowsePath(components: ["课堂", "线性代数"])
        )

        coordinator.importContext(context)

        #expect(coordinator.activeContext?.id == context.id)
        #expect(coordinator.conversation.contextItemCount == 2)
        #expect(coordinator.conversation.contextPathDisplay == "学习库 / 课堂 / 线性代数")
        #expect(provider.sentRequests.isEmpty)
        #expect(provider.titleRequests.isEmpty)
    }

    @Test @MainActor func reopeningConversationKeepsContextPathDisplay() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let store = ChatConversationStore(rootURL: rootURL)
        let context = ChatContext(
            id: "context-reopen",
            title: "Ch1",
            browsePathComponents: ["数学", "线性代数", "Ch1"],
            itemCount: 3,
            items: [],
            maxContextCharacters: 20_000
        )
        let coordinator = ChatCoordinator(
            providerResolver: { MockChatProvider() },
            conversationStore: store
        )

        coordinator.importContext(context)
        let conversationID = coordinator.conversation.id
        let reopened = ChatCoordinator(
            providerResolver: { MockChatProvider() },
            conversationStore: store
        )

        #expect(reopened.conversation.id == conversationID)
        #expect(reopened.conversation.contextPathDisplay == "学习库 / 数学 / 线性代数 / Ch1")
        #expect(reopened.activeContext?.id == "context-reopen")
    }

    @Test @MainActor func deletingActiveConversationSwitchesOrCreatesEmptyConversation() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let store = ChatConversationStore(rootURL: rootURL)
        let older = ChatConversation(
            id: "conversation-older",
            title: "较早对话",
            messages: [ChatMessage(role: .user, content: "旧消息")],
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = ChatConversation(
            id: "conversation-newer",
            title: "较新对话",
            messages: [ChatMessage(role: .user, content: "新消息")],
            createdAt: Date(timeIntervalSince1970: 2_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        try store.saveConversation(older)
        try store.saveConversation(newer)
        let coordinator = ChatCoordinator(
            providerResolver: { MockChatProvider() },
            conversationStore: store
        )

        coordinator.deleteConversation(id: "conversation-newer")

        #expect(coordinator.conversation.id == "conversation-older")
        #expect(store.loadConversation(id: "conversation-newer") == nil)

        coordinator.deleteConversation(id: "conversation-older")

        #expect(coordinator.conversation.id != "conversation-older")
        #expect(coordinator.conversation.title == "新对话")
        #expect(coordinator.visibleMessages.isEmpty)
    }

    @Test @MainActor func deletingConversationDoesNotDeleteStudyLibraryFiles() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let studyDirectoryURL = rootURL.appendingPathComponent("study", isDirectory: true)
        try FileManager.default.createDirectory(at: studyDirectoryURL, withIntermediateDirectories: true)
        let studyItemURL = studyDirectoryURL.appendingPathComponent("study-item.json", isDirectory: false)
        try #"{"title":"矩阵课"}"#.write(to: studyItemURL, atomically: true, encoding: .utf8)
        let store = ChatConversationStore(rootURL: rootURL)
        try store.saveConversation(ChatConversation(id: "conversation-delete", title: "待删除"))
        let coordinator = ChatCoordinator(
            providerResolver: { MockChatProvider() },
            conversationStore: store
        )

        coordinator.deleteConversation(id: "conversation-delete")

        #expect(store.loadConversation(id: "conversation-delete") == nil)
        #expect(FileManager.default.fileExists(atPath: studyItemURL.path))
    }

    @Test @MainActor func titleGeneratorSuccessWritesAIGeneratedTitle() async throws {
        let provider = CapturingChatProvider(titleResult: .success("矩阵乘法复习"))
        let coordinator = ChatCoordinator(
            providerResolver: { provider },
            conversationStore: nil
        )

        await coordinator.send("矩阵乘法怎么复习？")

        #expect(coordinator.conversation.title == "矩阵乘法复习")
        #expect(coordinator.conversation.titleSource == .aiGenerated)
        #expect(coordinator.conversation.titleGeneratedAt != nil)
    }

    @Test @MainActor func titleGeneratorFailureUsesFallbackTitle() async throws {
        let provider = CapturingChatProvider(titleResult: .failure(ChatProviderError.emptyAssistantMessage))
        let coordinator = ChatCoordinator(
            providerResolver: { provider },
            conversationStore: nil
        )

        await coordinator.send("行列式有哪些重点？")

        #expect(coordinator.conversation.title == "行列式有哪些重点？")
        #expect(coordinator.conversation.titleSource == .fallback)
        #expect(coordinator.conversation.titleGeneratedAt != nil)
    }

    @Test @MainActor func titleGenerationDoesNotReceiveFullContextText() async throws {
        let provider = CapturingChatProvider(titleResult: .success("线性代数复习"))
        let coordinator = ChatCoordinator(
            providerResolver: { provider },
            conversationStore: nil
        )
        let context = ChatContext(
            id: "context-title",
            title: "线性代数",
            browsePathComponents: ["数学", "线性代数"],
            itemCount: 1,
            items: [
                ChatContextItem(
                    id: "secret-item",
                    title: "完整上下文",
                    filingPath: StudyFilingPath(type: "数学"),
                    content: "这是一段不应该进入标题生成请求的完整 context 原文。"
                )
            ],
            maxContextCharacters: 20_000
        )

        coordinator.importContext(context)
        await coordinator.send("帮我复习矩阵乘法")

        let titleRequest = try #require(provider.titleRequests.first)
        #expect(titleRequest.contextPathDisplay == "学习库 / 数学 / 线性代数")
        #expect(!titleRequest.firstUserMessages.joined().contains("完整 context 原文"))
        #expect(titleRequest.firstAssistantMessage?.contains("完整 context 原文") == false)
    }

    @Test func attachmentFileNameSanitizerRemovesPathCharacters() {
        let sanitized = ChatConversationStore.sanitizedAttachmentFileName("../bad/name?.png")

        #expect(!sanitized.contains("/"))
        #expect(!sanitized.contains("?"))
        #expect(sanitized.hasSuffix(".png"))
    }

    @Test func savingAttachmentCopiesFileUnderConversationDirectory() throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let sourceURL = rootURL
            .deletingLastPathComponent()
            .appendingPathComponent("source-note.txt", isDirectory: false)
        try "矩阵乘法".write(to: sourceURL, atomically: true, encoding: .utf8)
        let store = ChatConversationStore(rootURL: rootURL)

        let attachment = try store.saveAttachment(from: sourceURL, conversationID: "conversation-attachments")

        #expect(attachment.conversationID == "conversation-attachments")
        #expect(attachment.kind == .document)
        #expect(attachment.relativePath.hasPrefix("chats/attachments/conversation-attachments/"))
        #expect(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(attachment.relativePath).path))
    }

    @Test @MainActor func unsupportedAttachmentKindsAreNotSentToProvider() async throws {
        let rootURL = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        let sourceURL = rootURL
            .deletingLastPathComponent()
            .appendingPathComponent("image.png", isDirectory: false)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)
        let provider = CapturingChatProvider(supportedAttachmentKinds: [], titleResult: .success("图片问题"))
        let coordinator = ChatCoordinator(
            providerResolver: { provider },
            conversationStore: ChatConversationStore(rootURL: rootURL)
        )

        coordinator.addAttachments(from: [sourceURL])
        await coordinator.send("看看这张图")

        #expect(provider.sentRequests.first?.attachments.isEmpty == true)
        #expect(coordinator.visibleMessages.first?.attachmentIDs.count == 1)
        #expect(coordinator.errorMessage?.contains("暂不支持附件输入") == true)
    }

    private static func makeScopeItems() -> [StudyItemMetadata] {
        [
            makeItem(
                id: "la-matrix",
                title: "矩阵乘法",
                filing: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
            ),
            makeItem(
                id: "la-determinant",
                title: "行列式",
                filing: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "行列式", topic: "余子式")
            ),
            makeItem(
                id: "calc-green",
                title: "格林公式",
                filing: StudyFilingPath(type: "课堂", subject: "高等数学", chapter: "多元积分", topic: "格林公式")
            ),
            makeItem(
                id: "review-ml",
                title: "机器学习复习",
                filing: StudyFilingPath(type: "复习", subject: "机器学习", chapter: "回归", topic: "线性回归")
            )
        ]
    }

    private static func makeItem(
        id: String,
        title: String,
        filing: StudyFilingPath,
        noteRelativePath: String? = nil,
        transcriptMarkdownRelativePath: String? = nil
    ) -> StudyItemMetadata {
        StudyItemMetadata(
            recordingID: id,
            sanitizedRecordingID: id,
            title: title,
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 60,
            transcriptMarkdownRelativePath: transcriptMarkdownRelativePath,
            noteRelativePath: noteRelativePath,
            studyFiling: filing
        )
    }

    private static let defaultsSuiteName = "RokuricsMacChatFeatureTests"

    private static func makeUserDefaults() throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }

    private static func date(hour: Int, calendar: Calendar) throws -> Date {
        let date = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 20,
            hour: hour
        ))
        return try #require(date)
    }

    fileprivate static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    fileprivate static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private final class CapturingChatProvider: ChatProvider {
    let id = "capturingChatProvider"
    let displayName = "Capturing"
    let supportedAttachmentKinds: Set<ChatAttachmentKind>

    private let titleResult: Result<String, Error>
    private(set) var sentRequests: [ChatRequest] = []
    private(set) var titleRequests: [ChatTitleRequest] = []

    init(
        supportedAttachmentKinds: Set<ChatAttachmentKind> = Set(ChatAttachmentKind.allCases),
        titleResult: Result<String, Error>
    ) {
        self.supportedAttachmentKinds = supportedAttachmentKinds
        self.titleResult = titleResult
    }

    func validateConfiguration() async throws {}

    func send(request: ChatRequest) async throws -> ChatResult {
        sentRequests.append(request)
        let userText = request.messages.last(where: { $0.role == .user })?.content ?? ""
        return ChatResult(
            message: ChatMessage(role: .assistant, content: "回复：\(userText)"),
            providerID: id,
            providerName: displayName,
            modelName: "fake",
            finishReason: "stop",
            outputWasTruncated: false
        )
    }

    func generateConversationTitle(request: ChatTitleRequest) async throws -> String {
        titleRequests.append(request)
        return try titleResult.get()
    }
}

private func makeScratchRoot() throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("RokuricsMacChatFeatureTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("Rokurics", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    return rootURL
}

private func writeNote(rootURL: URL, recordingID: String, summary: String, keyPoints: [String]) throws {
    let noteURL = try writeNoteMarkdown(rootURL: rootURL, recordingID: recordingID, markdown: "# \(recordingID)\n\n## 摘要\n\(summary)")
    let preview = NoteSummaryPreview(
        recordingID: recordingID,
        noteRelativePath: "notes/1970-01-01/\(recordingID)/note.md",
        shortSummary: summary,
        keyPoints: keyPoints,
        generatedAt: Date(timeIntervalSince1970: 2_000),
        providerDisplayName: "Mock",
        modelName: "mock"
    )
    let data = try ChatFeatureTests.encoder.encode(preview)
    try data.write(to: noteURL.deletingLastPathComponent().appendingPathComponent("summary.json", isDirectory: false))
}

@discardableResult
private func writeNoteMarkdown(rootURL: URL, recordingID: String, markdown: String) throws -> URL {
    let noteDirectoryURL = rootURL
        .appendingPathComponent("notes", isDirectory: true)
        .appendingPathComponent("1970-01-01", isDirectory: true)
        .appendingPathComponent(recordingID, isDirectory: true)
    try FileManager.default.createDirectory(at: noteDirectoryURL, withIntermediateDirectories: true)
    let noteURL = noteDirectoryURL.appendingPathComponent("note.md", isDirectory: false)
    try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
    return noteURL
}

private func writeTranscript(rootURL: URL, recordingID: String, markdown: String) throws {
    let transcriptDirectoryURL = rootURL
        .appendingPathComponent("transcripts", isDirectory: true)
        .appendingPathComponent("1970-01-01", isDirectory: true)
        .appendingPathComponent(recordingID, isDirectory: true)
    try FileManager.default.createDirectory(at: transcriptDirectoryURL, withIntermediateDirectories: true)
    try markdown.write(
        to: transcriptDirectoryURL.appendingPathComponent("transcript.md", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
}
