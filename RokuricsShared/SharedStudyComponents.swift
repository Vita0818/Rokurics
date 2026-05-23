//
//  SharedStudyComponents.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

enum StudyLibraryHeaderModel {
    static let title = "学习库"
    static let showsLeadingIcon = false
    static let titleToken: RokuricsSharedTypographyToken = .pageTitle
}

struct StudyLibraryBrowserLayout {
    let horizontalPadding: CGFloat
    let headerTopPadding: CGFloat
    let rootSpacing: CGFloat
    let contentSpacing: CGFloat
    let folderSpacing: CGFloat
    let itemSpacing: CGFloat
    let contentPadding: CGFloat
    let contentBottomPadding: CGFloat
    let showsScrollIndicators: Bool
    let showsHeaderControlRow: Bool
    let folderColumns: [GridItem]

    static var mac: StudyLibraryBrowserLayout {
        StudyLibraryBrowserLayout(
            horizontalPadding: 0,
            headerTopPadding: 0,
            rootSpacing: 20,
            contentSpacing: 18,
            folderSpacing: 16,
            itemSpacing: 12,
            contentPadding: 4,
            contentBottomPadding: 24,
            showsScrollIndicators: true,
            showsHeaderControlRow: false,
            folderColumns: [GridItem(.adaptive(minimum: 142, maximum: 210), spacing: 16, alignment: .top)]
        )
    }

    static var iPhone: StudyLibraryBrowserLayout {
        StudyLibraryBrowserLayout(
            horizontalPadding: RokuricsMobilePageLayoutMetrics.horizontalPadding,
            headerTopPadding: RokuricsMobilePageLayoutMetrics.topPadding,
            rootSpacing: 20,
            contentSpacing: RokuricsMobilePageLayoutMetrics.contentSpacing,
            folderSpacing: 16,
            itemSpacing: 12,
            contentPadding: 4,
            contentBottomPadding: RokuricsMobilePageLayoutMetrics.bottomPadding,
            showsScrollIndicators: false,
            showsHeaderControlRow: true,
            folderColumns: [GridItem(.adaptive(minimum: 142, maximum: 210), spacing: 16, alignment: .top)]
        )
    }
}

struct StudyLibraryPageShell<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            RokuricsSharedStyle.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            content
        }
    }
}

extension StudyFilingPath {
    var browsePath: StudyBrowsePath {
        StudyBrowsePath(
            components: [type, subject, chapter, topic]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}

struct StudyLibraryBrowserView<
    HeaderLeading: View,
    HeaderTrailing: View,
    NavigationLeading: View,
    NavigationTrailing: View,
    FolderTile: View,
    RecordingCard: View,
    NoteCard: View
>: View {
    let items: [StudyItemMetadata]
    let folders: [StudyFolderMetadata]
    @Binding var browsePath: StudyBrowsePath
    var layout: StudyLibraryBrowserLayout
    var emptyLibraryTitle = "暂无学习内容"
    var emptyLibraryMessage: String?
    var emptyFolderTitle = "暂无学习内容"
    var emptyFolderMessage = "这个文件夹里暂时没有学习内容"
    let headerLeading: () -> HeaderLeading
    let headerTrailing: () -> HeaderTrailing
    let navigationLeading: () -> NavigationLeading
    let navigationTrailing: () -> NavigationTrailing
    let folderTile: (StudyBrowseFolder) -> FolderTile
    let recordingCard: (StudyItemMetadata) -> RecordingCard
    let noteCard: (StudyItemMetadata) -> NoteCard

    init(
        items: [StudyItemMetadata],
        folders: [StudyFolderMetadata],
        browsePath: Binding<StudyBrowsePath>,
        layout: StudyLibraryBrowserLayout,
        emptyLibraryTitle: String = "暂无学习内容",
        emptyLibraryMessage: String?,
        emptyFolderTitle: String = "暂无学习内容",
        emptyFolderMessage: String = "这个文件夹里暂时没有学习内容",
        @ViewBuilder headerLeading: @escaping () -> HeaderLeading,
        @ViewBuilder headerTrailing: @escaping () -> HeaderTrailing,
        @ViewBuilder navigationLeading: @escaping () -> NavigationLeading,
        @ViewBuilder navigationTrailing: @escaping () -> NavigationTrailing,
        @ViewBuilder folderTile: @escaping (StudyBrowseFolder) -> FolderTile,
        @ViewBuilder recordingCard: @escaping (StudyItemMetadata) -> RecordingCard,
        @ViewBuilder noteCard: @escaping (StudyItemMetadata) -> NoteCard
    ) {
        self.items = items
        self.folders = folders
        self._browsePath = browsePath
        self.layout = layout
        self.emptyLibraryTitle = emptyLibraryTitle
        self.emptyLibraryMessage = emptyLibraryMessage
        self.emptyFolderTitle = emptyFolderTitle
        self.emptyFolderMessage = emptyFolderMessage
        self.headerLeading = headerLeading
        self.headerTrailing = headerTrailing
        self.navigationLeading = navigationLeading
        self.navigationTrailing = navigationTrailing
        self.folderTile = folderTile
        self.recordingCard = recordingCard
        self.noteCard = noteCard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.rootSpacing) {
            StudyLibraryBrowserHeaderView(
                showsControls: layout.showsHeaderControlRow,
                leading: headerLeading,
                trailing: headerTrailing
            )

            if items.isEmpty && folders.isEmpty {
                StudyEmptyState(title: emptyLibraryTitle, message: emptyLibraryMessage)
                Spacer(minLength: 0)
            } else {
                StudyLibraryNavigationPathView(
                    path: browsePath,
                    onSelectPath: { browsePath = $0 },
                    leading: navigationLeading,
                    trailing: navigationTrailing
                )

                StudyLibraryBrowserBody(
                    content: browserContent,
                    layout: layout,
                    emptyFolderTitle: emptyFolderTitle,
                    emptyFolderMessage: emptyFolderMessage,
                    folderTile: folderTile,
                    recordingCard: recordingCard,
                    noteCard: noteCard
                )
            }
        }
        .padding(.top, layout.headerTopPadding)
        .padding(.horizontal, layout.horizontalPadding)
    }

    private var browserContent: StudyBrowseContent {
        StudyLibraryBrowser.content(items: items, folders: folders, path: browsePath)
    }
}

struct StudyLibraryBrowserHeaderView<Leading: View, Trailing: View>: View {
    let showsControls: Bool
    let leading: () -> Leading
    let trailing: () -> Trailing
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if showsControls {
            RokuricsMobilePageHeader(
                leading: leading,
                trailing: trailing
            ) {
                headerTitle
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                headerTitle
            }
        }
    }

    private var headerTitle: some View {
        RokuricsSharedText(
            text: StudyLibraryHeaderModel.title,
            token: StudyLibraryHeaderModel.titleToken,
            size: RokuricsMobilePageLayoutMetrics.titleSize,
            weight: .bold
        )
            .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
            .multilineTextAlignment(.leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct StudyLibraryNavigationPathView<Leading: View, Trailing: View>: View {
    let path: StudyBrowsePath
    let onSelectPath: (StudyBrowsePath) -> Void
    let leading: () -> Leading
    let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            leading()

            StudyBreadcrumb(path: path, onSelect: onSelectPath)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StudyLibraryBrowserBody<
    FolderTile: View,
    RecordingCard: View,
    NoteCard: View
>: View {
    let content: StudyBrowseContent
    let layout: StudyLibraryBrowserLayout
    let emptyFolderTitle: String
    let emptyFolderMessage: String
    let folderTile: (StudyBrowseFolder) -> FolderTile
    let recordingCard: (StudyItemMetadata) -> RecordingCard
    let noteCard: (StudyItemMetadata) -> NoteCard

    var body: some View {
        Group {
            if content.folders.isEmpty && content.items.isEmpty {
                StudyEmptyState(title: emptyFolderTitle, message: emptyFolderMessage)
            } else {
                ScrollView(showsIndicators: layout.showsScrollIndicators) {
                    LazyVStack(alignment: .leading, spacing: layout.contentSpacing) {
                        StudyLibraryFolderSection(
                            folders: content.folders,
                            columns: layout.folderColumns,
                            spacing: layout.folderSpacing,
                            folderTile: folderTile
                        )

                        StudyLibraryItemSection(
                            items: content.items,
                            spacing: layout.itemSpacing,
                            recordingCard: recordingCard,
                            noteCard: noteCard
                        )
                    }
                    .padding(layout.contentPadding)
                    .padding(.bottom, layout.contentBottomPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

struct StudyLibraryFolderSection<FolderTile: View>: View {
    let folders: [StudyBrowseFolder]
    let columns: [GridItem]
    let spacing: CGFloat
    let folderTile: (StudyBrowseFolder) -> FolderTile

    var body: some View {
        if !folders.isEmpty {
            LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                ForEach(folders) { folder in
                    folderTile(folder)
                }
            }
        }
    }
}

struct StudyLibraryItemSection<RecordingCard: View, NoteCard: View>: View {
    let items: [StudyItemMetadata]
    let spacing: CGFloat
    let recordingCard: (StudyItemMetadata) -> RecordingCard
    let noteCard: (StudyItemMetadata) -> NoteCard

    var body: some View {
        if !items.isEmpty {
            LazyVStack(alignment: .leading, spacing: spacing) {
                ForEach(items) { item in
                    if item.kind == .recordingBundle {
                        recordingCard(item)
                    } else {
                        noteCard(item)
                    }
                }
            }
        }
    }
}

struct StudyStatusCapsule: View {
    let text: String
    let systemImage: String
    var tint: Color?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(statusFont)
            .foregroundStyle(tint ?? RokuricsSharedStyle.softText(for: colorScheme))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .rokuricsSharedGlassCapsule(fillOpacity: 0.24, strokeOpacity: 0.22)
    }

    private var statusFont: Font {
        #if os(macOS)
        MacTypography.chineseCaption(size: 11, weight: .bold)
        #else
        RokuricsTypography.secondary(size: 11, weight: .bold)
        #endif
    }
}

struct StudyBreadcrumb: View {
    let path: StudyBrowsePath
    let onSelect: (StudyBrowsePath) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var breadcrumbs: [(title: String, path: StudyBrowsePath)] {
        StudyLibraryBrowser.breadcrumbs(for: path)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { index, breadcrumb in
                    if index > 0 {
                        Text("/")
                            .font(separatorFont)
                            .foregroundStyle(RokuricsSharedStyle.tertiaryText(for: colorScheme))
                    }

                    Button {
                        onSelect(breadcrumb.path)
                    } label: {
                        RokuricsSharedText(
                            text: breadcrumb.title,
                            token: .secondary,
                            weight: index == breadcrumbs.count - 1 ? .semibold : .medium
                        )
                        .foregroundStyle(index == breadcrumbs.count - 1 ? RokuricsSharedStyle.deepText(for: colorScheme) : RokuricsSharedStyle.softText(for: colorScheme))
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background {
                            Capsule(style: .continuous)
                                .fill(index == breadcrumbs.count - 1 ? RokuricsSharedStyle.aqua.opacity(0.10) : Color.clear)
                        }
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #else
                    .buttonStyle(RokuricsScaleButtonStyle())
                    #endif
                    .disabled(index == breadcrumbs.count - 1)
                    .accessibilityLabel(breadcrumb.title)
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.vertical, 2)
        }
    }

    private var separatorFont: Font {
        #if os(macOS)
        MacTypography.chineseCaption(size: 12, weight: .semibold)
        #else
        RokuricsTypography.secondary(size: 12, weight: .semibold)
        #endif
    }
}

struct StudyFolderRow: View {
    let folder: StudyBrowseFolder
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 13) {
                StudyFolderIconView(
                    folder: folder,
                    frameWidth: 34,
                    frameHeight: 34,
                    imageWidth: 34,
                    imageHeight: 29,
                    badgeSize: 7,
                    badgeOffsetX: -1,
                    badgeOffsetY: -2
                )

                VStack(alignment: .leading, spacing: 4) {
                    RokuricsSharedText(text: folder.title, token: .cardTitle)
                        .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                        .lineLimit(1)

                    Text("\(folder.itemCount) 项")
                        .font(secondaryFont)
                        .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                }

                Spacer(minLength: 10)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RokuricsSharedStyle.tertiaryText(for: colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rokuricsSharedGlassCard(cornerRadius: 20, fillOpacity: 0.34, strokeOpacity: 0.32, shadowOpacity: 0.05, shadowRadius: 8, shadowY: 4)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .buttonStyle(RokuricsScaleButtonStyle())
        #endif
    }

    private var secondaryFont: Font {
        #if os(macOS)
        MacTypography.chineseCaption(size: 12, weight: .semibold)
        #else
        RokuricsTypography.font(for: .secondary)
        #endif
    }
}

struct StudyStatusCapsuleModel: Identifiable {
    var id: String { "\(text)-\(systemImage)" }
    let text: String
    let systemImage: String
    var tint: Color?

    static var standaloneNote: StudyStatusCapsuleModel {
        StudyStatusCapsuleModel(text: "笔记", systemImage: "doc.text", tint: RokuricsSharedStyle.mint)
    }
}

struct StudyItemCard: View {
    let item: StudyItemMetadata
    var metadataText: String
    var statusItems: [StudyStatusCapsuleModel]
    var showsChevron = true
    @Environment(\.colorScheme) private var colorScheme

    init(
        item: StudyItemMetadata,
        metadataText: String,
        statusItems: [StudyStatusCapsuleModel] = [],
        showsChevron: Bool = true
    ) {
        self.item = item
        self.metadataText = metadataText
        self.statusItems = statusItems
        self.showsChevron = showsChevron
    }

    var body: some View {
        VStack(alignment: .leading, spacing: statusItems.isEmpty ? 0 : 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.kind == .recordingBundle ? "waveform" : "doc.text.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(item.kind == .recordingBundle ? RokuricsSharedStyle.aqua : RokuricsSharedStyle.mint)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 6) {
                    RokuricsSharedText(text: item.title, token: .cardTitle, size: 15)
                        .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                        .lineLimit(1)

                    Text(metadataText)
                        .font(numberFont)
                        .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(RokuricsSharedStyle.tertiaryText(for: colorScheme))
                }
            }

            if !statusItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(statusItems) { item in
                            StudyStatusCapsule(text: item.text, systemImage: item.systemImage, tint: item.tint)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsSharedGlassCard(cornerRadius: 20, fillOpacity: 0.34, strokeOpacity: 0.32, shadowOpacity: 0.05, shadowRadius: 8, shadowY: 4)
    }

    private var numberFont: Font {
        #if os(macOS)
        MacTypography.numberBody(size: 12, weight: .semibold)
        #else
        RokuricsTypography.numberBody(size: 12, weight: .semibold)
        #endif
    }
}

struct StudyEmptyState: View {
    let title: String
    let message: String?
    var systemImage = "books.vertical"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(RokuricsSharedStyle.aqua)

            RokuricsSharedText(text: title, token: .sectionTitle, size: 22, weight: .bold)
                .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))

            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RokuricsSharedText(text: message, token: .secondary)
                    .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsSharedGlassCard(cornerRadius: 22, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.04, shadowRadius: 9, shadowY: 4)
    }
}

struct StudyFolderIconView: View {
    let folder: StudyBrowseFolder
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let imageWidth: CGFloat
    let imageHeight: CGFloat
    let badgeSize: CGFloat
    let badgeOffsetX: CGFloat
    let badgeOffsetY: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    init(
        folder: StudyBrowseFolder,
        frameWidth: CGFloat = 58,
        frameHeight: CGFloat = 52,
        imageWidth: CGFloat = 58,
        imageHeight: CGFloat = 50,
        badgeSize: CGFloat = 12,
        badgeOffsetX: CGFloat = -2,
        badgeOffsetY: CGFloat = -3
    ) {
        self.folder = folder
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.badgeSize = badgeSize
        self.badgeOffsetX = badgeOffsetX
        self.badgeOffsetY = badgeOffsetY
    }

    var body: some View {
        StudyFolderIconProvider.icon(
            accent: folder.isFallback ? RokuricsSharedStyle.softText(for: colorScheme) : accent,
            colorToken: folder.colorToken,
            isFallback: folder.isFallback,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )
        .overlay(alignment: .bottomTrailing) {
            if let color = folder.colorToken?.sharedAccentColor {
                Circle()
                    .fill(color)
                    .frame(width: badgeSize, height: badgeSize)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.35 : 0.78), lineWidth: 1)
                    }
                    .offset(x: badgeOffsetX, y: badgeOffsetY)
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .frame(height: frameHeight)
    }

    private var accent: Color {
        folder.colorToken?.sharedAccentColor ?? RokuricsSharedStyle.aqua
    }
}

private enum StudyFolderIconProvider {
    @ViewBuilder
    static func icon(
        accent: Color,
        colorToken: StudyFolderColorToken?,
        isFallback: Bool,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> some View {
        #if os(iOS)
        StudyFinderFolderAssetIcon(
            assetName: StudyFolderIconAsset.name(for: colorToken, isFallback: isFallback),
            fallbackTint: accent,
            isFallback: isFallback,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )
        #else
        StudyFolderVectorIcon(accent: accent, isFallback: isFallback)
            .frame(width: imageWidth, height: imageHeight)
        #endif
    }
}

enum StudyFolderMenuModel {
    static let renameTitle = "重命名"
    static let moveToTrashTitle = "移入废纸篓"
    static let primaryActionTitles = [renameTitle, moveToTrashTitle]
    static let colorColumnsPerRow = 6
    static let colorTokens: [StudyFolderColorToken] = [
        .default,
        .red,
        .orange,
        .yellow,
        .green,
        .mint,
        .teal,
        .cyan,
        .blue,
        .indigo,
        .purple,
        .gray
    ]

    static var colorRows: [[StudyFolderColorToken]] {
        stride(from: 0, to: colorTokens.count, by: colorColumnsPerRow).map { startIndex in
            Array(colorTokens[startIndex..<min(startIndex + colorColumnsPerRow, colorTokens.count)])
        }
    }

    static func title(for colorToken: StudyFolderColorToken) -> String {
        switch colorToken {
        case .default:
            return "默认"
        case .red:
            return "红"
        case .orange:
            return "橙"
        case .yellow:
            return "黄"
        case .green:
            return "绿"
        case .mint:
            return "薄荷"
        case .teal:
            return "青绿"
        case .cyan:
            return "青"
        case .blue:
            return "蓝"
        case .indigo:
            return "靛"
        case .purple:
            return "紫"
        case .gray:
            return "灰"
        }
    }
}

#if os(iOS)
private enum StudyFolderIconBadge: String {
    case plus
    case checkmark
    case star
    case trash
    case lock
    case upload
    case transcript
    case note
    case ai
}

private enum StudyFolderIconAsset {
    static let defaultName = "finder-folder-default"

    static func name(
        for colorToken: StudyFolderColorToken?,
        badge: StudyFolderIconBadge? = nil,
        isFallback: Bool
    ) -> String {
        if let badge {
            return "\(defaultName)-\(badge.rawValue)"
        }

        guard let colorToken else {
            return defaultName
        }

        switch colorToken {
        case .default:
            return defaultName
        case .orange:
            return "finder-folder-orange"
        case .blue:
            return "finder-folder-blue"
        case .green:
            return "finder-folder-green"
        case .mint:
            return "finder-folder-mint"
        case .teal:
            return "finder-folder-teal"
        case .cyan:
            return "finder-folder-cyan"
        case .yellow:
            return "finder-folder-yellow"
        case .red:
            return "finder-folder-red"
        case .indigo:
            return "finder-folder-indigo"
        case .purple:
            return "finder-folder-purple"
        case .gray:
            return "finder-folder-gray"
        }
    }
}

private struct StudyFinderFolderAssetIcon: View {
    let assetName: String
    let fallbackTint: Color
    let isFallback: Bool
    let imageWidth: CGFloat
    let imageHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = UIImage(named: assetName) ?? UIImage(named: StudyFolderIconAsset.defaultName) {
            Image(uiImage: image)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .scaledToFit()
                .frame(width: imageWidth, height: imageHeight)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 5, x: 0, y: 3)
        } else {
            StudyMacLikeFolderGlyph(
                fallbackTint: fallbackTint,
                isFallback: isFallback,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )
        }
    }
}
#endif

private struct StudyMacLikeFolderGlyph: View {
    let fallbackTint: Color
    let isFallback: Bool
    let imageWidth: CGFloat
    let imageHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            StudyFinderFolderBackShape()
                .fill(backGradient)

            StudyFinderFolderFrontShape()
                .fill(frontGradient)
                .overlay {
                    StudyFinderFolderFrontShape()
                        .stroke(frontStroke, lineWidth: 0.9)
                }

            StudyFinderFolderHighlightShape()
                .fill(highlightGradient)
                .opacity(isFallback ? 0.18 : 1)
                .blendMode(.screen)

            StudyFinderFolderRidgeShape()
                .stroke(ridgeStroke, lineWidth: 1)
                .opacity(isFallback ? 0 : 1)
        }
        .frame(width: imageWidth, height: imageHeight)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 5, x: 0, y: 3)
        .saturation(isFallback ? 0.35 : 1)
        .opacity(isFallback ? 0.76 : 1)
    }

    private var backGradient: LinearGradient {
        if isFallback {
            return LinearGradient(
                colors: [
                    fallbackTint.opacity(colorScheme == .dark ? 0.64 : 0.56),
                    fallbackTint.opacity(colorScheme == .dark ? 0.38 : 0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.66, green: 0.85, blue: 1.00),
                Color(red: 0.30, green: 0.62, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var frontGradient: LinearGradient {
        if isFallback {
            return LinearGradient(
                colors: [
                    fallbackTint.opacity(colorScheme == .dark ? 0.72 : 0.64),
                    fallbackTint.opacity(colorScheme == .dark ? 0.44 : 0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.50, green: 0.77, blue: 0.99),
                Color(red: 0.16, green: 0.52, blue: 0.93)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var highlightGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.46),
                Color.white.opacity(colorScheme == .dark ? 0.04 : 0.10),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var frontStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.62),
                Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var ridgeStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.36),
                Color.white.opacity(0.02)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct StudyFinderFolderBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(3, 13, in: rect))
        path.addCurve(to: point(9, 8, in: rect), control1: point(3, 10, in: rect), control2: point(6, 8, in: rect))
        path.addLine(to: point(22, 8, in: rect))
        path.addCurve(to: point(28, 12, in: rect), control1: point(25, 8, in: rect), control2: point(26, 10, in: rect))
        path.addLine(to: point(51, 12, in: rect))
        path.addCurve(to: point(56, 17, in: rect), control1: point(54, 12, in: rect), control2: point(56, 14, in: rect))
        path.addLine(to: point(56, 41, in: rect))
        path.addCurve(to: point(51, 46, in: rect), control1: point(56, 44, in: rect), control2: point(54, 46, in: rect))
        path.addLine(to: point(7, 46, in: rect))
        path.addCurve(to: point(2, 41, in: rect), control1: point(4, 46, in: rect), control2: point(2, 44, in: rect))
        path.addLine(to: point(2, 18, in: rect))
        path.addCurve(to: point(3, 13, in: rect), control1: point(2, 16, in: rect), control2: point(2, 14, in: rect))
        path.closeSubpath()
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x / 58, y: rect.minY + rect.height * y / 50)
    }
}

private struct StudyFinderFolderFrontShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(2, 20, in: rect))
        path.addCurve(to: point(8, 15, in: rect), control1: point(2, 17, in: rect), control2: point(5, 15, in: rect))
        path.addLine(to: point(53, 15, in: rect))
        path.addCurve(to: point(56, 19, in: rect), control1: point(55, 15, in: rect), control2: point(57, 17, in: rect))
        path.addLine(to: point(53, 42, in: rect))
        path.addCurve(to: point(48, 47, in: rect), control1: point(53, 45, in: rect), control2: point(51, 47, in: rect))
        path.addLine(to: point(7, 47, in: rect))
        path.addCurve(to: point(2, 42, in: rect), control1: point(4, 47, in: rect), control2: point(2, 45, in: rect))
        path.addLine(to: point(2, 20, in: rect))
        path.closeSubpath()
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x / 58, y: rect.minY + rect.height * y / 50)
    }
}

private struct StudyFinderFolderHighlightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(5, 20, in: rect))
        path.addCurve(to: point(53, 19, in: rect), control1: point(18, 16, in: rect), control2: point(39, 16, in: rect))
        path.addLine(to: point(52, 27, in: rect))
        path.addCurve(to: point(5, 27, in: rect), control1: point(38, 23, in: rect), control2: point(19, 23, in: rect))
        path.closeSubpath()
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x / 58, y: rect.minY + rect.height * y / 50)
    }
}

private struct StudyFinderFolderRidgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(5, 18, in: rect))
        path.addCurve(to: point(53, 17, in: rect), control1: point(18, 14, in: rect), control2: point(39, 14, in: rect))
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x / 58, y: rect.minY + rect.height * y / 50)
    }
}

private struct StudyFolderVectorIcon: View {
    let accent: Color
    let isFallback: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tabGradient)
                .frame(width: 31, height: 15)
                .offset(x: 4, y: 4)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(bodyGradient)
                .frame(width: 54, height: 38)
                .offset(x: 2, y: 12)
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.58), lineWidth: 1)
                        .frame(width: 54, height: 38)
                        .offset(x: 2, y: 12)
                }
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.10), radius: 5, x: 0, y: 3)
        .saturation(isFallback ? 0.35 : 1)
        .opacity(isFallback ? 0.76 : 1)
    }

    private var bodyGradient: LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(colorScheme == .dark ? 0.78 : 0.88),
                RokuricsSharedStyle.mint.opacity(colorScheme == .dark ? 0.50 : 0.62)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var tabGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.56),
                accent.opacity(colorScheme == .dark ? 0.62 : 0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct StudyInlineEditableText<Display: View>: View {
    let text: String
    let token: RokuricsSharedTypographyToken
    var size: CGFloat?
    var weight: Font.Weight?
    var textAlignment: TextAlignment = .leading
    var editTriggerID = 0
    var onCommit: ((String) -> Void)?
    var onEditingChanged: (Bool) -> Void = { _ in }
    let display: (String) -> Display

    @State private var draft: String
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    init(
        text: String,
        token: RokuricsSharedTypographyToken,
        size: CGFloat? = nil,
        weight: Font.Weight? = nil,
        textAlignment: TextAlignment = .leading,
        editTriggerID: Int = 0,
        onCommit: ((String) -> Void)? = nil,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder display: @escaping (String) -> Display
    ) {
        self.text = text
        self.token = token
        self.size = size
        self.weight = weight
        self.textAlignment = textAlignment
        self.editTriggerID = editTriggerID
        self.onCommit = onCommit
        self.onEditingChanged = onEditingChanged
        self.display = display
        _draft = State(initialValue: text)
    }

    var body: some View {
        Group {
            if isEditing, onCommit != nil {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(editFont)
                    .multilineTextAlignment(textAlignment)
                    .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                    .focused($isFocused)
                    .onSubmit(commit)
            } else {
                display(text)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: beginEditing)
            }
        }
        .onChange(of: text) {
            if !isEditing {
                draft = text
            }
        }
        .onChange(of: editTriggerID) {
            beginEditing()
        }
        .onChange(of: isFocused) {
            if !isFocused, isEditing {
                commit()
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var editFont: Font {
        #if os(macOS)
        MacTypography.chineseBody(size: size ?? defaultSize, weight: weight ?? .medium)
        #else
        RokuricsTypography.chineseBody(size: size ?? defaultSize, weight: weight ?? .medium)
        #endif
    }

    private var defaultSize: CGFloat {
        switch token {
        case .pageTitle:
            return 30
        case .sectionTitle:
            return 20
        case .cardTitle:
            return 16
        case .pageSubtitle, .body, .chatMessage, .chatInput:
            return 15
        case .secondary, .technical:
            return 13
        case .chatGreeting:
            return 26
        }
    }

    private func beginEditing() {
        guard onCommit != nil else {
            return
        }

        draft = text
        isEditing = true
        isFocused = true
        onEditingChanged(true)
    }

    private func commit() {
        guard isEditing else {
            return
        }

        defer {
            isEditing = false
            isFocused = false
            onEditingChanged(false)
        }

        let submitted = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submitted.isEmpty else {
            draft = text
            return
        }
        onCommit?(submitted)
    }

    private func cancel() {
        draft = text
        isEditing = false
        isFocused = false
        onEditingChanged(false)
    }
}

struct StudyFolderTileShell<TitleContent: View>: View {
    let folder: StudyBrowseFolder
    var minHeight: CGFloat = 128
    let titleContent: TitleContent
    @Environment(\.colorScheme) private var colorScheme

    init(
        folder: StudyBrowseFolder,
        minHeight: CGFloat = 128,
        @ViewBuilder title: () -> TitleContent
    ) {
        self.folder = folder
        self.minHeight = minHeight
        self.titleContent = title()
    }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            folderIcon

            titleContent

            Text("\(folder.itemCount) 项")
                .font(countFont)
                .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .rokuricsSharedGlassCard(
            cornerRadius: 18,
            material: .thinMaterial,
            fillOpacity: 0.34,
            strokeOpacity: 0.28,
            shadowOpacity: 0.04,
            shadowRadius: 8,
            shadowY: 4
        )
    }

    private var folderIcon: some View {
        StudyFolderIconView(folder: folder)
    }

    private var countFont: Font {
        #if os(macOS)
        MacTypography.chineseCaption(size: 11, weight: .semibold)
        #else
        RokuricsTypography.secondary(size: 11, weight: .semibold)
        #endif
    }
}

struct StudyFolderTitleView: View {
    let folder: StudyBrowseFolder
    var editTriggerID = 0
    var onRename: ((String) -> Void)?
    var onEditingChanged: (Bool) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        StudyInlineEditableText(
            text: folder.title,
            token: .cardTitle,
            size: 14,
            weight: .bold,
            textAlignment: .center,
            editTriggerID: editTriggerID,
            onCommit: onRename,
            onEditingChanged: onEditingChanged
        ) { title in
            RokuricsSharedText(text: title, token: .cardTitle, size: 14, weight: .bold)
                .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .minimumScaleFactor(0.82)
        }
    }
}

struct StudyFolderTileContent: View {
    let folder: StudyBrowseFolder
    var editTriggerID = 0
    var onRename: ((String) -> Void)?
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        StudyFolderTileShell(folder: folder) {
            StudyFolderTitleView(
                folder: folder,
                editTriggerID: editTriggerID,
                onRename: onRename,
                onEditingChanged: onEditingChanged
            )
        }
    }
}

struct StudyFolderTile: View {
    let folder: StudyBrowseFolder
    let onOpen: () -> Void
    var editTriggerID = 0
    var onRename: ((String) -> Void)?
    var onSetColor: ((StudyFolderColorToken) -> Void)?
    var onMoveToTrash: (() -> Void)?
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var localEditTriggerID = 0
    @State private var isEditingName = false
    @State private var isFolderMenuPresented = false

    var body: some View {
        #if os(iOS)
        StudyFolderTileContent(
            folder: folder,
            editTriggerID: editTriggerID + localEditTriggerID,
            onRename: onRename,
            onEditingChanged: handleEditingChanged
        )
        .onTapGesture {
            if !isEditingName {
                onOpen()
            }
        }
        .onLongPressGesture {
            if !isEditingName {
                isFolderMenuPresented = true
            }
        }
        .sheet(isPresented: $isFolderMenuPresented) {
            StudyFolderMenuContent(
                selectedColorToken: folder.colorToken ?? .default,
                onRename: onRename.map { _ in
                    {
                        isFolderMenuPresented = false
                        localEditTriggerID += 1
                    }
                },
                onMoveToTrash: onMoveToTrash.map { action in
                    {
                        isFolderMenuPresented = false
                        action()
                    }
                },
                onSetColor: onSetColor.map { action in
                    { colorToken in
                        isFolderMenuPresented = false
                        action(colorToken)
                    }
                }
            )
            .presentationDetents([.height(190)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(.clear)
        }
        .accessibilityLabel("打开\(folder.title)")
        .accessibilityAddTraits(.isButton)
        #else
        Button(action: onOpen) {
            StudyFolderTileContent(
                folder: folder,
                editTriggerID: editTriggerID,
                onRename: onRename,
                onEditingChanged: onEditingChanged
            )
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel("打开\(folder.title)")
        #endif
    }

    private func handleEditingChanged(_ isEditing: Bool) {
        isEditingName = isEditing
        onEditingChanged(isEditing)
    }

}

struct StudyFolderMenuContent: View {
    let selectedColorToken: StudyFolderColorToken
    var onRename: (() -> Void)?
    var onMoveToTrash: (() -> Void)?
    var onSetColor: ((StudyFolderColorToken) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if let onRename {
                    StudyFolderMenuActionButton(
                        title: StudyFolderMenuModel.renameTitle,
                        role: nil,
                        action: onRename
                    )
                }

                if let onMoveToTrash {
                    StudyFolderMenuActionButton(
                        title: StudyFolderMenuModel.moveToTrashTitle,
                        role: .destructive,
                        action: onMoveToTrash
                    )
                }
            }

            if let onSetColor {
                VStack(spacing: 8) {
                    ForEach(StudyFolderMenuModel.colorRows.indices, id: \.self) { rowIndex in
                        HStack(spacing: 10) {
                            ForEach(StudyFolderMenuModel.colorRows[rowIndex]) { colorToken in
                                StudyFolderColorDotButton(
                                    colorToken: colorToken,
                                    isSelected: selectedColorToken == colorToken,
                                    action: {
                                        onSetColor(colorToken)
                                    }
                                )
                            }
                        }
                    }
                }
                .frame(width: 194)
                .padding(.top, 1)
            }
        }
        .padding(12)
        .frame(width: 260)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RokuricsSharedStyle.tertiaryText(for: colorScheme).opacity(0.30), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, x: 0, y: 10)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct StudyFolderMenuActionButton: View {
    let title: String
    let role: ButtonRole?
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(role: role, action: action) {
            RokuricsSharedText(text: title, token: .secondary, size: 12, weight: .semibold)
                .foregroundStyle(role == .destructive ? RokuricsSharedStyle.coral : RokuricsSharedStyle.deepText(for: colorScheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            role == .destructive
                                ? RokuricsSharedStyle.coral.opacity(0.10)
                                : RokuricsSharedStyle.tertiaryText(for: colorScheme).opacity(0.10)
                        )
                }
        }
        .buttonStyle(.plain)
    }
}

private struct StudyFolderColorDotButton: View {
    let colorToken: StudyFolderColorToken
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(colorToken.sharedAccentColor ?? Color.clear)
                    .frame(width: 15, height: 15)
                    .overlay {
                        Circle()
                            .stroke(
                                colorToken.sharedAccentColor == nil
                                    ? RokuricsSharedStyle.softText(for: colorScheme).opacity(0.55)
                                    : Color.white.opacity(colorScheme == .dark ? 0.22 : 0.70),
                                lineWidth: 1
                            )
                    }

                if isSelected {
                    Circle()
                        .stroke(RokuricsSharedStyle.deepText(for: colorScheme).opacity(0.72), lineWidth: 1.5)
                        .frame(width: 21, height: 21)
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(StudyFolderMenuModel.title(for: colorToken))
    }
}

struct StudyRecordingCardShell<TitleContent: View, ActionsContent: View>: View {
    let metadataText: String
    var isDeleteIconActive = false
    let titleContent: TitleContent
    let actionsContent: ActionsContent
    @Environment(\.colorScheme) private var colorScheme

    init(
        metadataText: String,
        isDeleteIconActive: Bool = false,
        @ViewBuilder title: () -> TitleContent,
        @ViewBuilder actions: () -> ActionsContent
    ) {
        self.metadataText = metadataText
        self.isDeleteIconActive = isDeleteIconActive
        self.titleContent = title()
        self.actionsContent = actions()
    }

    var body: some View {
        HStack(spacing: 14) {
            StudyRecordingLeadingIcon(isDeleteIconActive: isDeleteIconActive)

            VStack(alignment: .leading, spacing: 8) {
                titleContent

                Text(metadataText)
                    .font(metadataFont)
                    .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            actionsContent
                .frame(maxWidth: actionsMaxWidth, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .rokuricsSharedGlassCard(
            cornerRadius: 18,
            material: .ultraThinMaterial,
            fillOpacity: 0.34,
            strokeOpacity: 0.30,
            shadowOpacity: 0.04,
            shadowRadius: 8,
            shadowY: 4
        )
    }

    private var metadataFont: Font {
        #if os(macOS)
        MacTypography.numberBody(size: 13, weight: .semibold)
        #else
        RokuricsTypography.numberBody(size: 13, weight: .semibold)
        #endif
    }

    private var actionsMaxWidth: CGFloat {
        #if os(iOS)
        196
        #else
        150
        #endif
    }
}

struct StudyLibraryRecordingCard<TitleContent: View, ActionsContent: View>: View {
    let metadataText: String
    var isDeleteIconActive = false
    let titleContent: TitleContent
    let actionsContent: ActionsContent

    init(
        metadataText: String,
        isDeleteIconActive: Bool = false,
        @ViewBuilder title: () -> TitleContent,
        @ViewBuilder actions: () -> ActionsContent
    ) {
        self.metadataText = metadataText
        self.isDeleteIconActive = isDeleteIconActive
        self.titleContent = title()
        self.actionsContent = actions()
    }

    var body: some View {
        StudyRecordingCardShell(
            metadataText: metadataText,
            isDeleteIconActive: isDeleteIconActive
        ) {
            titleContent
        } actions: {
            actionsContent
        }
    }
}

struct StudyLibraryRecordingActionGlyph: View {
    let systemImage: String
    let tint: Color
    let accessibilityLabel: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .rokuricsSharedGlassCircle(fillOpacity: 0.24, strokeOpacity: 0.22, shadowOpacity: 0.03, shadowRadius: 5, shadowY: 2)
            .accessibilityLabel(accessibilityLabel)
    }
}

struct StudyLibraryPageBackButton: View {
    let action: () -> Void

    var body: some View {
        RokuricsMobileBackButton(action: action)
    }
}

struct StudyLibraryFolderBackButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        RokuricsMobileBackButton(isEnabled: isEnabled, action: action)
    }
}

struct StudyLibraryTrashButtonGroup: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RokuricsIconButtonGroup {
            RokuricsIconButtonGroupItem(
                systemName: "trash",
                accessibilityLabel: "打开废纸篓",
                tint: RokuricsSharedStyle.softText(for: colorScheme),
                isEnabled: true,
                action: action
            )
        }
    }
}

enum StudyRecordingMetadataFormatter {
    static func cardMetadataText(for item: StudyItemMetadata) -> String {
        "\(cardDateFormatter.string(from: item.createdAt)) · \(StudyLibraryDurationText.text(item.durationForDisplay))"
    }

    static func detailMetadataText(for item: StudyItemMetadata) -> String {
        "\(detailDateFormatter.string(from: item.createdAt)) · \(StudyLibraryDurationText.text(item.durationForDisplay))"
    }

    private static let cardDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

struct StudyRecordingCardActionModel: Identifiable {
    let id: String
    let systemImage: String
    let tint: Color
    let accessibilityLabel: String
    let isEnabled: Bool
    let action: (() -> Void)?

    init(
        id: String,
        systemImage: String,
        tint: Color,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.systemImage = systemImage
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
        self.isEnabled = isEnabled
        self.action = action
    }
}

enum StudyRecordingStatusPresentation {
    static func transcriptionText(_ status: String?) -> String {
        switch status {
        case "transcribed":
            return "已转写"
        case "transcribing", "queued":
            return "转写中"
        case "failed":
            return "转写失败"
        default:
            return "未转写"
        }
    }

    static func noteText(_ status: String?) -> String {
        switch status {
        case "generated":
            return "有总结"
        case "generating":
            return "总结中"
        case "failed":
            return "总结失败"
        default:
            return "无总结"
        }
    }

    static func transcriptAction(for item: StudyItemMetadata) -> StudyRecordingCardActionModel {
        StudyRecordingCardActionModel(
            id: "transcript",
            systemImage: item.hasTranscript ? "text.quote" : "waveform.and.magnifyingglass",
            tint: RokuricsSharedStyle.aqua,
            accessibilityLabel: transcriptionText(item.transcriptionStatus)
        )
    }

    static func noteAction(for item: StudyItemMetadata) -> StudyRecordingCardActionModel {
        StudyRecordingCardActionModel(
            id: "note",
            systemImage: item.hasNote ? "sparkles.rectangle.stack" : "sparkles",
            tint: RokuricsSharedStyle.mint,
            accessibilityLabel: noteText(item.noteStatus)
        )
    }

    static var detailAction: StudyRecordingCardActionModel {
        StudyRecordingCardActionModel(
            id: "detail",
            systemImage: "chevron.right",
            tint: RokuricsSharedStyle.aqua,
            accessibilityLabel: "打开详情"
        )
    }
}

enum StudyRecordingActionPolicy {
    static func uploadAction(
        systemImage: String,
        tint: Color,
        accessibilityLabel: String,
        isEnabled: Bool,
        action: (() -> Void)? = nil
    ) -> StudyRecordingCardActionModel {
        StudyRecordingCardActionModel(
            id: "upload",
            systemImage: systemImage,
            tint: tint,
            accessibilityLabel: accessibilityLabel,
            isEnabled: isEnabled,
            action: action
        )
    }

    static func playAction(isEnabled: Bool, action: (() -> Void)? = nil) -> StudyRecordingCardActionModel {
        StudyRecordingCardActionModel(
            id: "play",
            systemImage: "play.fill",
            tint: RokuricsSharedStyle.leaf,
            accessibilityLabel: "播放录音",
            isEnabled: isEnabled,
            action: action
        )
    }

    static func transcriptionAction(
        for item: StudyItemMetadata,
        isProcessing: Bool = false,
        isEnabled: Bool? = nil,
        action: (() -> Void)? = nil
    ) -> StudyRecordingCardActionModel {
        let canUse = isEnabled ?? ((item.audioRelativePath != nil || item.recordingID != nil) && !isProcessing)
        return StudyRecordingCardActionModel(
            id: "transcript",
            systemImage: item.hasTranscript ? "arrow.clockwise" : "waveform.and.magnifyingglass",
            tint: RokuricsSharedStyle.aqua,
            accessibilityLabel: transcriptionActionLabel(for: item, isProcessing: isProcessing),
            isEnabled: canUse,
            action: action
        )
    }

    static func noteAction(
        for item: StudyItemMetadata,
        isProcessing: Bool = false,
        isEnabled: Bool? = nil,
        action: (() -> Void)? = nil
    ) -> StudyRecordingCardActionModel {
        let canUse = isEnabled ?? ((item.hasTranscript || item.transcriptMarkdownRelativePath != nil) && !isProcessing)
        return StudyRecordingCardActionModel(
            id: "note",
            systemImage: item.hasNote ? "sparkles.rectangle.stack" : "sparkles",
            tint: RokuricsSharedStyle.mint,
            accessibilityLabel: noteActionLabel(for: item, isProcessing: isProcessing),
            isEnabled: canUse,
            action: action
        )
    }

    static func importToChatAction(action: (() -> Void)? = nil) -> StudyRecordingCardActionModel {
        StudyRecordingCardActionModel(
            id: "chat",
            systemImage: "bubble.left.and.bubble.right",
            tint: RokuricsSharedStyle.aqua,
            accessibilityLabel: "导入 AI 对话",
            isEnabled: true,
            action: action
        )
    }

    static func detailAction(action: (() -> Void)? = nil) -> StudyRecordingCardActionModel {
        StudyRecordingCardActionModel(
            id: "detail",
            systemImage: "chevron.right",
            tint: RokuricsSharedStyle.aqua,
            accessibilityLabel: "打开详情",
            isEnabled: true,
            action: action
        )
    }

    static func transcriptionActionLabel(for item: StudyItemMetadata, isProcessing: Bool = false) -> String {
        if isProcessing || item.transcriptionStatus == "transcribing" || item.transcriptionStatus == "queued" {
            return "转写中"
        }
        if item.hasTranscript {
            return "重新转写"
        }
        if item.transcriptionStatus == "failed" {
            return "重试转写"
        }
        return "转写"
    }

    static func noteActionLabel(for item: StudyItemMetadata, isProcessing: Bool = false) -> String {
        if isProcessing || item.noteStatus == "generating" {
            return "总结中"
        }
        if item.hasNote {
            return "重新总结"
        }
        if item.noteStatus == "failed" {
            return "重试总结"
        }
        return "AI 总结"
    }
}

struct StudyRecordingCardActions: View {
    let actions: [StudyRecordingCardActionModel]

    var body: some View {
        #if os(iOS)
        RokuricsIconButtonGroup {
            ForEach(actions) { action in
                StudyRecordingCardActionGroupGlyph(model: action)
            }
        }
        #else
        HStack(spacing: 8) {
            ForEach(actions) { action in
                StudyRecordingCardActionView(model: action)
            }
        }
        #endif
    }
}

private struct StudyRecordingCardActionGroupGlyph: View {
    let model: StudyRecordingCardActionModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let action = model.action {
            RokuricsIconButtonGroupItem(
                systemName: model.systemImage,
                accessibilityLabel: model.accessibilityLabel,
                tint: model.tint,
                isEnabled: model.isEnabled,
                action: action
            )
        } else {
            Image(systemName: model.systemImage)
                .font(.system(size: RokuricsSharedIconButtonConfiguration.iconSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.isEnabled ? model.tint : RokuricsSharedStyle.tertiaryText(for: colorScheme))
                .frame(
                    width: RokuricsSharedIconButtonConfiguration.groupItemSize,
                    height: RokuricsSharedIconButtonConfiguration.groupItemSize
                )
                .contentShape(Circle())
                .opacity(model.isEnabled ? 1 : RokuricsSharedIconButtonConfiguration.disabledOpacity)
                .accessibilityLabel(model.accessibilityLabel)
        }
    }
}

private struct StudyRecordingCardActionView: View {
    let model: StudyRecordingCardActionModel

    var body: some View {
        if let action = model.action {
            Button(action: action) {
                glyph
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #else
            .buttonStyle(RokuricsScaleButtonStyle())
            #endif
            .disabled(!model.isEnabled)
            .opacity(model.isEnabled ? 1 : 0.46)
            .help(model.accessibilityLabel)
        } else {
            glyph
                .opacity(model.isEnabled ? 1 : 0.46)
        }
    }

    private var glyph: some View {
        StudyLibraryRecordingActionGlyph(
            systemImage: model.systemImage,
            tint: model.tint,
            accessibilityLabel: model.accessibilityLabel
        )
    }
}

struct StudyRecordingBundleCardContent: View {
    let item: StudyItemMetadata
    let metadataText: String
    let actions: [StudyRecordingCardActionModel]
    var isDeleteIconActive = false
    var renameTriggerID = 0
    var onRename: ((String) -> Void)?
    var onTitleEditingChanged: (Bool) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme

    init(
        item: StudyItemMetadata,
        metadataText: String? = nil,
        actions: [StudyRecordingCardActionModel],
        isDeleteIconActive: Bool = false,
        renameTriggerID: Int = 0,
        onRename: ((String) -> Void)? = nil,
        onTitleEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.item = item
        self.metadataText = metadataText ?? StudyRecordingMetadataFormatter.cardMetadataText(for: item)
        self.actions = actions
        self.isDeleteIconActive = isDeleteIconActive
        self.renameTriggerID = renameTriggerID
        self.onRename = onRename
        self.onTitleEditingChanged = onTitleEditingChanged
    }

    var body: some View {
        StudyLibraryRecordingCard(metadataText: metadataText, isDeleteIconActive: isDeleteIconActive) {
            StudyInlineEditableText(
                text: item.title,
                token: .cardTitle,
                size: 16,
                weight: .semibold,
                editTriggerID: renameTriggerID,
                onCommit: onRename,
                onEditingChanged: onTitleEditingChanged
            ) { title in
                RokuricsSharedText(text: title, token: .cardTitle, size: 16, weight: .semibold)
                    .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                    .lineLimit(1)
            }
        } actions: {
            StudyRecordingCardActions(actions: actions)
        }
    }
}

struct StudyRecordingBundleCard: View {
    let item: StudyItemMetadata
    let metadataText: String?
    let actions: [StudyRecordingCardActionModel]

    init(
        item: StudyItemMetadata,
        metadataText: String? = nil,
        actions: [StudyRecordingCardActionModel]
    ) {
        self.item = item
        self.metadataText = metadataText
        self.actions = actions
    }

    var body: some View {
        StudyRecordingBundleCardContent(
            item: item,
            metadataText: metadataText,
            actions: actions
        )
    }
}

struct StudyMissingContentView: View {
    let message: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RokuricsSharedStyle.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            Text(message)
                .font(bodyFont)
                .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                .padding(22)
        }
    }

    private var bodyFont: Font {
        #if os(macOS)
        MacTypography.chineseBody(size: 15, weight: .regular)
        #else
        RokuricsTypography.font(for: .body)
        #endif
    }
}

struct StudyTrashSheet<Item: Identifiable, RowContent: View>: View {
    let items: [Item]
    let emptyTitle: String
    let rowContent: (Item) -> RowContent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(
        items: [Item],
        emptyTitle: String,
        @ViewBuilder rowContent: @escaping (Item) -> RowContent
    ) {
        self.items = items
        self.emptyTitle = emptyTitle
        self.rowContent = rowContent
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RokuricsSharedStyle.pageGradient(for: colorScheme)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    if items.isEmpty {
                        Text(emptyTitle)
                            .font(bodyFont)
                            .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                            .padding(22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .rokuricsSharedGlassCard(cornerRadius: 22, fillOpacity: 0.34, strokeOpacity: 0.34, shadowOpacity: 0.08, shadowRadius: 8, shadowY: 4)
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 12) {
                                ForEach(items) { item in
                                    rowContent(item)
                                }
                            }
                            .padding(.bottom, 18)
                        }
                    }
                }
                .padding(22)
            }
            .navigationTitle("废纸篓")
            .toolbar {
                ToolbarItem(placement: doneToolbarPlacement) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private var bodyFont: Font {
        #if os(macOS)
        MacTypography.chineseBody(size: 15, weight: .regular)
        #else
        RokuricsTypography.font(for: .body)
        #endif
    }

    private var doneToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .topBarTrailing
        #endif
    }
}

struct StudyRecordingTrashRow: View {
    let title: String
    let metadataText: String
    let onRestore: () -> Void
    let onPermanentDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 6) {
                RokuricsSharedText(text: title, token: .cardTitle, size: 15)
                    .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                    .lineLimit(1)

                Text(metadataText)
                    .font(metadataFont)
                    .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button("恢复", action: onRestore)
                .font(buttonFont)
                .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .rokuricsSharedGlassCapsule(fillOpacity: 0.28, strokeOpacity: 0.28)

            Button("永久删除", action: onPermanentDelete)
                .font(buttonFont)
                .foregroundStyle(RokuricsSharedStyle.coral)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .rokuricsSharedGlassCapsule(fillOpacity: 0.20, strokeOpacity: 0.24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .rokuricsSharedGlassCard(cornerRadius: 18, fillOpacity: 0.32, strokeOpacity: 0.30, shadowOpacity: 0.06, shadowRadius: 8, shadowY: 4)
    }

    private var metadataFont: Font {
        #if os(macOS)
        MacTypography.numberBody(size: 12, weight: .semibold)
        #else
        RokuricsTypography.numberBody(size: 12, weight: .semibold)
        #endif
    }

    private var buttonFont: Font {
        #if os(macOS)
        MacTypography.chineseCaption(size: 12, weight: .bold)
        #else
        RokuricsTypography.font(for: .secondary)
        #endif
    }
}

struct StudyRecordingLeadingIcon: View {
    let isDeleteIconActive: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(containerFill)

            Circle()
                .stroke(containerStroke, lineWidth: 1)

            Image(systemName: isDeleteIconActive ? "trash.fill" : "waveform")
                .font(.system(size: isDeleteIconActive ? 14 : 16, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(glyphColor)
                .frame(width: 20, height: 20)
        }
        .background(.ultraThinMaterial, in: Circle())
        .frame(width: 38, height: 38)
        .scaleEffect(isDeleteIconActive ? 1.015 : 1)
        .animation(.easeInOut(duration: 0.12), value: isDeleteIconActive)
    }

    private var containerFill: Color {
        if isDeleteIconActive {
            return RokuricsSharedStyle.coral.opacity(colorScheme == .dark ? 0.11 : 0.09)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.075)
            : Color.white.opacity(0.58)
    }

    private var containerStroke: LinearGradient {
        let accent = isDeleteIconActive ? RokuricsSharedStyle.coral : RokuricsSharedStyle.aqua

        return LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.62),
                accent.opacity(isDeleteIconActive ? 0.42 : 0.34)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glyphColor: Color {
        isDeleteIconActive
            ? RokuricsSharedStyle.coral.opacity(colorScheme == .dark ? 0.86 : 0.78)
            : RokuricsSharedStyle.aqua
    }
}

struct StudyRecordingCardIconButton: View {
    let systemImage: String
    let isEnabled: Bool
    let tint: Color
    let helpText: String
    let action: () -> Void

    var body: some View {
        RokuricsGlassIconButton(
            systemImage: systemImage,
            accessibilityTitle: helpText,
            tint: tint,
            isEnabled: isEnabled,
            action: action
        )
    }
}

struct StudyDetailActionButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            StudyDetailActionLabel(title: title, systemImage: systemImage, isEnabled: isEnabled)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .buttonStyle(RokuricsScaleButtonStyle())
        #endif
        .disabled(!isEnabled)
    }
}

struct StudyDetailActionModel: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    init(
        id: String,
        title: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }
}

struct StudyDetailActionGrid: View {
    let actions: [StudyDetailActionModel]

    var body: some View {
        ForEach(actions) { action in
            StudyDetailActionButton(
                title: action.title,
                systemImage: action.systemImage,
                isEnabled: action.isEnabled,
                action: action.action
            )
        }
    }
}

struct StudyDetailHeaderActionModel: Identifiable {
    let id: String
    let systemImage: String
    let accessibilityLabel: String
    let tint: Color
    let isEnabled: Bool
    let role: ButtonRole?
    let action: () -> Void

    init(
        id: String,
        systemImage: String,
        accessibilityLabel: String,
        tint: Color,
        isEnabled: Bool = true,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.tint = tint
        self.isEnabled = isEnabled
        self.role = role
        self.action = action
    }
}

struct StudyDetailHeaderActionGroup: View {
    let actions: [StudyDetailHeaderActionModel]

    var body: some View {
        RokuricsIconButtonGroup {
            ForEach(actions) { action in
                RokuricsIconButtonGroupItem(
                    systemName: action.systemImage,
                    accessibilityLabel: action.accessibilityLabel,
                    tint: action.tint,
                    isEnabled: action.isEnabled,
                    role: action.role,
                    action: action.action
                )
            }
        }
    }
}

enum StudyRecordingDetailActionSymbol {
    static let upload = "arrow.up.circle"
    static let play = "play.fill"
    static let transcript = "text.quote"
    static let transcribe = "waveform.and.magnifyingglass"
    static let note = "doc.text"
    static let generateNote = "sparkles"
    static let generatedNote = "sparkles.rectangle.stack"
    static let rename = "pencil"
    static let trash = "trash"
    static let chat = "bubble.left.and.bubble.right"
}

enum StudyDetailActionPolicy {
    static func uploadHeaderAction(
        systemImage: String,
        title: String,
        tint: Color,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> StudyDetailHeaderActionModel {
        StudyDetailHeaderActionModel(
            id: "upload",
            systemImage: systemImage,
            accessibilityLabel: title,
            tint: tint,
            isEnabled: isEnabled,
            action: action
        )
    }

    static func importToChatHeaderAction(action: @escaping () -> Void) -> StudyDetailHeaderActionModel {
        StudyDetailHeaderActionModel(
            id: "chat",
            systemImage: StudyRecordingDetailActionSymbol.chat,
            accessibilityLabel: "导入 AI 对话",
            tint: RokuricsSharedStyle.aqua,
            action: action
        )
    }

    static func renameHeaderAction(tint: Color, action: @escaping () -> Void) -> StudyDetailHeaderActionModel {
        StudyDetailHeaderActionModel(
            id: "rename",
            systemImage: StudyRecordingDetailActionSymbol.rename,
            accessibilityLabel: "重命名",
            tint: tint,
            action: action
        )
    }

    static func trashHeaderAction(
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> StudyDetailHeaderActionModel {
        StudyDetailHeaderActionModel(
            id: "trash",
            systemImage: StudyRecordingDetailActionSymbol.trash,
            accessibilityLabel: "移入废纸篓",
            tint: RokuricsSharedStyle.coral,
            isEnabled: isEnabled,
            role: .destructive,
            action: action
        )
    }

    static func uploadDetailAction(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> StudyDetailActionModel {
        StudyDetailActionModel(
            id: "upload",
            title: title,
            systemImage: systemImage,
            isEnabled: isEnabled,
            action: action
        )
    }

    static func transcribeDetailAction(
        for item: StudyItemMetadata,
        isProcessing: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> StudyDetailActionModel {
        StudyDetailActionModel(
            id: "transcribe",
            title: StudyRecordingActionPolicy.transcriptionActionLabel(for: item, isProcessing: isProcessing),
            systemImage: item.hasTranscript ? "arrow.clockwise" : StudyRecordingDetailActionSymbol.transcribe,
            isEnabled: isEnabled,
            action: action
        )
    }

    static func viewTranscriptAction(
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> StudyDetailActionModel {
        StudyDetailActionModel(
            id: "viewTranscript",
            title: isEnabled ? "查看转写" : "未转写",
            systemImage: StudyRecordingDetailActionSymbol.transcript,
            isEnabled: isEnabled,
            action: action
        )
    }

    static func generateNoteDetailAction(
        for item: StudyItemMetadata,
        isProcessing: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> StudyDetailActionModel {
        StudyDetailActionModel(
            id: "generateNote",
            title: StudyRecordingActionPolicy.noteActionLabel(for: item, isProcessing: isProcessing),
            systemImage: item.hasNote ? StudyRecordingDetailActionSymbol.generatedNote : StudyRecordingDetailActionSymbol.generateNote,
            isEnabled: isEnabled,
            action: action
        )
    }

    static func viewNoteAction(
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> StudyDetailActionModel {
        StudyDetailActionModel(
            id: "viewNote",
            title: isEnabled ? "查看总结" : "无总结",
            systemImage: StudyRecordingDetailActionSymbol.note,
            isEnabled: isEnabled,
            action: action
        )
    }

    static func renameDetailAction(action: @escaping () -> Void) -> StudyDetailActionModel {
        StudyDetailActionModel(
            id: "rename",
            title: "重命名",
            systemImage: StudyRecordingDetailActionSymbol.rename,
            action: action
        )
    }
}

enum StudyRecordingFileStatusRows {
    static func rows(for item: StudyItemMetadata) -> [RokuricsDocumentMetadataRow] {
        [
            RokuricsDocumentMetadataRow("audio", item.audioRelativePath == nil ? "缺失" : "可用"),
            RokuricsDocumentMetadataRow("transcript", StudyRecordingStatusPresentation.transcriptionText(item.transcriptionStatus)),
            RokuricsDocumentMetadataRow("note", StudyRecordingStatusPresentation.noteText(item.noteStatus)),
            RokuricsDocumentMetadataRow("recordingID", item.recordingID, isTechnical: true),
            RokuricsDocumentMetadataRow("audio path", item.audioRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow("transcript path", item.transcriptMarkdownRelativePath ?? item.transcriptRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow("note path", item.noteRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow("receive", item.receiveRelativePath, isTechnical: true)
        ]
    }
}

enum StudyReadingMetadataRows {
    static func transcriptInfoRows(
        item: StudyItemMetadata,
        markdown: String,
        transcriptResult: TranscriptionResult?,
        receiveRecord: RecordingReceiveRecord?
    ) -> [RokuricsDocumentMetadataRow] {
        let metadata = RokuricsTranscriptMarkdownCleaner.metadata(from: markdown)
        return [
            RokuricsDocumentMetadataRow("录音时间", RokuricsDocumentFormatting.dateTime(item.createdAt)),
            RokuricsDocumentMetadataRow("时长", RokuricsDocumentFormatting.duration(item.durationForDisplay)),
            RokuricsDocumentMetadataRow("语言", transcriptResult?.language ?? metadata["language"]),
            RokuricsDocumentMetadataRow("转写 Provider", RokuricsProviderDisplayName.transcription(receiveRecord?.transcriptionProviderID ?? transcriptResult?.providerID ?? transcriptResult?.providerName ?? metadata["provider"])),
            RokuricsDocumentMetadataRow("转写模型", RokuricsModelDisplayName.friendly(receiveRecord?.transcriptionModelName ?? transcriptResult?.modelName)),
            RokuricsDocumentMetadataRow("转写时间", RokuricsDocumentFormatting.dateTime(transcriptResult?.completedAt ?? receiveRecord?.transcriptionCompletedAt) ?? metadata["transcribedAt"]),
            RokuricsDocumentMetadataRow("mode", RokuricsDocumentFormatting.mode(receiveRecord?.transcriptionMode)),
            RokuricsDocumentMetadataRow("chunks", receiveRecord?.transcriptionChunks.map { "\($0.count)" })
        ]
    }

    static func transcriptAdvancedRows(
        item: StudyItemMetadata,
        markdown: String,
        transcriptResult: TranscriptionResult?,
        receiveRecord: RecordingReceiveRecord?
    ) -> [RokuricsDocumentMetadataRow] {
        let metadata = RokuricsTranscriptMarkdownCleaner.metadata(from: markdown)
        return [
            RokuricsDocumentMetadataRow("转写 Provider", RokuricsProviderDisplayName.transcription(receiveRecord?.transcriptionProviderID ?? transcriptResult?.providerID ?? transcriptResult?.providerName ?? metadata["provider"])),
            RokuricsDocumentMetadataRow("转写模型", RokuricsModelDisplayName.friendly(receiveRecord?.transcriptionModelName ?? transcriptResult?.modelName)),
            RokuricsDocumentMetadataRow("转写时间", RokuricsDocumentFormatting.dateTime(transcriptResult?.completedAt ?? receiveRecord?.transcriptionCompletedAt) ?? metadata["transcribedAt"]),
            RokuricsDocumentMetadataRow("mode", RokuricsDocumentFormatting.mode(receiveRecord?.transcriptionMode)),
            RokuricsDocumentMetadataRow("chunks", receiveRecord?.transcriptionChunks.map { "\($0.count)" }),
            RokuricsDocumentMetadataRow("recordingID", item.recordingID, isTechnical: true),
            RokuricsDocumentMetadataRow("transcript.json", item.transcriptRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow("transcript.md", item.transcriptMarkdownRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow("receive", item.receiveRelativePath, isTechnical: true)
        ]
    }

    static func noteInfoRows(
        item: StudyItemMetadata,
        markdown: String,
        receiveRecord: RecordingReceiveRecord?
    ) -> [RokuricsDocumentMetadataRow] {
        let metadata = RokuricsNoteMarkdownCleaner.metadata(from: markdown)
        return [
            RokuricsDocumentMetadataRow("生成时间", RokuricsDocumentFormatting.dateTime(receiveRecord?.noteGeneratedAt) ?? metadata["generatedAt"]),
            RokuricsDocumentMetadataRow("Note Provider", RokuricsProviderDisplayName.note(receiveRecord?.noteProviderID ?? metadata["provider"])),
            RokuricsDocumentMetadataRow("模型", RokuricsModelDisplayName.friendly(receiveRecord?.noteModelName ?? metadata["model"])),
            RokuricsDocumentMetadataRow("mode", RokuricsDocumentFormatting.mode(receiveRecord?.noteGenerationMode) ?? metadata["mode"]),
            RokuricsDocumentMetadataRow("sections", receiveRecord?.noteSections.map { "\($0.count)" } ?? metadata["sections"])
        ]
    }

    static func noteAdvancedRows(
        item: StudyItemMetadata,
        markdown: String,
        receiveRecord: RecordingReceiveRecord?
    ) -> [RokuricsDocumentMetadataRow] {
        let metadata = RokuricsNoteMarkdownCleaner.metadata(from: markdown)
        let sectionPaths = receiveRecord?.noteSections?
            .compactMap(\.sectionNoteRelativePath)
            .joined(separator: "\n")

        return [
            RokuricsDocumentMetadataRow("recordingID", item.recordingID, isTechnical: true),
            RokuricsDocumentMetadataRow("note", item.noteRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow("来源 transcript", metadata["sourceTranscript"] ?? item.transcriptMarkdownRelativePath ?? item.transcriptRelativePath, isTechnical: true),
            RokuricsDocumentMetadataRow("note sections", sectionPaths, isTechnical: true)
        ]
    }
}

struct StudyDetailActionLabel: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(buttonFont)
            .foregroundStyle(isEnabled ? RokuricsSharedStyle.deepText(for: colorScheme) : RokuricsSharedStyle.tertiaryText(for: colorScheme))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .rokuricsSharedGlassCapsule(fillOpacity: isEnabled ? 0.28 : 0.16, strokeOpacity: 0.24)
    }

    private var buttonFont: Font {
        #if os(macOS)
        MacTypography.chineseCaption(size: 12, weight: .bold)
        #else
        RokuricsTypography.secondary(size: 12, weight: .bold)
        #endif
    }
}

struct StudyFilingPicker: View {
    @Binding var type: String
    @Binding var subject: String
    @Binding var chapter: String
    @Binding var topic: String
    let items: [StudyItemMetadata]
    let folders: [StudyFolderMetadata]
    let onSave: () -> Void
    var onCreate: (StudyFolderLevel, String) -> Void = { _, _ in }

    @State private var activeLevel: StudyFolderLevel?
    @State private var newValueDraft = ""
    @FocusState private var isNewValueFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private let levels: [StudyFolderLevel] = [.type, .subject, .chapter, .topic]
    private let candidateColumns = [
        GridItem(.adaptive(minimum: 96, maximum: 168), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(levels, id: \.self) { level in
                        StudyFilingLevelButton(
                            level: level,
                            value: draft.value(for: level),
                            isActive: selectionLevel == level,
                            isEnabled: canActivate(level)
                        ) {
                            guard canActivate(level) else {
                                return
                            }

                            activeLevel = level
                            newValueDraft = ""
                            isNewValueFocused = false
                        }
                    }
                }
            }

            LazyVGrid(columns: candidateColumns, alignment: .leading, spacing: 8) {
                ForEach(currentCandidates, id: \.self) { candidate in
                    StudyFilingValueButton(title: candidate, isSelected: draft.value(for: selectionLevel) == candidate) {
                        select(candidate, for: selectionLevel)
                    }
                }

                HStack(spacing: 6) {
                    TextField("新建", text: $newValueDraft)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        #endif
                        .textFieldStyle(.plain)
                        .font(inputFont)
                        .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                        .focused($isNewValueFocused)
                        .onSubmit(createCurrentValue)

                    RokuricsGlassIconButton(
                        systemImage: "plus",
                        accessibilityTitle: "新建\(selectionLevel.title)",
                        tint: RokuricsSharedStyle.aqua,
                        isEnabled: !newValueDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: createCurrentValue
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(RokuricsSharedStyle.deepText(for: colorScheme).opacity(colorScheme == .dark ? 0.06 : 0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(RokuricsSharedStyle.tertiaryText(for: colorScheme).opacity(0.20), lineWidth: 1)
                }
            }
        }
    }

    private var draft: StudyFilingSelectionDraft {
        StudyFilingSelectionDraft(
            path: StudyFilingPath(
                type: type,
                subject: subject,
                chapter: chapter,
                topic: topic
            )
        )
    }

    private var selectionLevel: StudyFolderLevel {
        if let activeLevel, canActivate(activeLevel) {
            return activeLevel
        }

        return firstMissingLevel ?? .topic
    }

    private var firstMissingLevel: StudyFolderLevel? {
        levels.first { draft.value(for: $0).isEmpty }
    }

    private var currentCandidates: [String] {
        StudyFilingCandidateResolver.candidates(
            for: selectionLevel,
            current: draft.filingPath,
            items: items,
            folders: folders
        )
    }

    private var inputFont: Font {
        #if os(macOS)
        MacTypography.chineseBody(size: 13, weight: .medium)
        #else
        RokuricsTypography.chineseBody(size: 13, weight: .medium)
        #endif
    }

    private func canActivate(_ level: StudyFolderLevel) -> Bool {
        switch level {
        case .type:
            return true
        case .subject:
            return !type.isEmpty
        case .chapter:
            return !type.isEmpty && !subject.isEmpty
        case .topic:
            return !type.isEmpty && !subject.isEmpty && !chapter.isEmpty
        case .custom:
            return false
        }
    }

    private func select(_ value: String, for level: StudyFolderLevel) {
        var updated = draft
        updated.select(level, value: value)
        apply(updated)
        finishCommit(for: level)
        newValueDraft = ""
        onSave()
    }

    private func createCurrentValue() {
        let trimmedName = newValueDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        let level = selectionLevel
        onCreate(level, trimmedName)
        select(trimmedName, for: level)
    }

    private func finishCommit(for level: StudyFolderLevel) {
        activeLevel = StudyFilingSelectionFlow.nextLevelAfterCommit(level)
        isNewValueFocused = false
    }

    private func apply(_ updated: StudyFilingSelectionDraft) {
        type = updated.type
        subject = updated.subject
        chapter = updated.chapter
        topic = updated.topic
    }
}

private struct StudyFilingLevelButton: View {
    let level: StudyFolderLevel
    let value: String
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(level.title)
                    .font(labelFont)
                    .foregroundStyle(RokuricsSharedStyle.tertiaryText(for: colorScheme))

                Text(value.isEmpty ? "未选择" : value)
                    .font(valueFont)
                    .foregroundStyle(isEnabled ? RokuricsSharedStyle.deepText(for: colorScheme) : RokuricsSharedStyle.tertiaryText(for: colorScheme))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(minWidth: 82, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(RokuricsSharedStyle.deepText(for: colorScheme).opacity(isActive ? 0.08 : 0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isActive ? RokuricsSharedStyle.aqua.opacity(0.42) : RokuricsSharedStyle.tertiaryText(for: colorScheme).opacity(0.20), lineWidth: 1)
            }
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .buttonStyle(RokuricsScaleButtonStyle())
        #endif
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
    }

    private var labelFont: Font {
        #if os(macOS)
        MacTypography.chineseCaption(size: 10, weight: .bold)
        #else
        RokuricsTypography.secondary(size: 10, weight: .bold)
        #endif
    }

    private var valueFont: Font {
        #if os(macOS)
        MacTypography.chineseCaption(size: 12, weight: .bold)
        #else
        RokuricsTypography.secondary(size: 12, weight: .bold)
        #endif
    }
}

private struct StudyFilingValueButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(valueFont)
                .foregroundStyle(isSelected ? .white : RokuricsSharedStyle.deepText(for: colorScheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? RokuricsSharedStyle.aqua : RokuricsSharedStyle.deepText(for: colorScheme).opacity(0.045))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? RokuricsSharedStyle.aqua.opacity(0.34) : RokuricsSharedStyle.tertiaryText(for: colorScheme).opacity(0.20), lineWidth: 1)
                }
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .buttonStyle(RokuricsScaleButtonStyle())
        #endif
    }

    private var valueFont: Font {
        #if os(macOS)
        MacTypography.chineseCaption(size: 12, weight: .bold)
        #else
        RokuricsTypography.secondary(size: 12, weight: .bold)
        #endif
    }
}

enum StudyLibraryDurationText {
    static func text(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes == 0 {
            return "\(seconds)''"
        }

        return "\(minutes)'\(String(format: "%02d", seconds))''"
    }
}

extension StudyFolderColorToken {
    var sharedAccentColor: Color? {
        switch self {
        case .default:
            return nil
        case .orange:
            return Color(red: 0.96, green: 0.52, blue: 0.16)
        case .blue:
            return RokuricsSharedStyle.aqua
        case .green:
            #if os(macOS)
            return MacTheme.leaf
            #else
            return RokuricsColors.softTeal
            #endif
        case .mint:
            return RokuricsSharedStyle.mint
        case .teal:
            return Color(red: 0.17, green: 0.68, blue: 0.66)
        case .cyan:
            return Color(red: 0.22, green: 0.72, blue: 0.92)
        case .yellow:
            #if os(macOS)
            return MacTheme.amber
            #else
            return Color(red: 0.94, green: 0.70, blue: 0.20)
            #endif
        case .red:
            return RokuricsSharedStyle.coral
        case .indigo:
            return Color(red: 0.34, green: 0.42, blue: 0.86)
        case .purple:
            return Color(red: 0.55, green: 0.43, blue: 0.94)
        case .gray:
            return Color.secondary
        }
    }
}

struct RecordingStatusSummaryView: View {
    let upload: StudyStatusCapsuleModel
    let transcription: StudyStatusCapsuleModel
    let note: StudyStatusCapsuleModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                StudyStatusCapsule(text: upload.text, systemImage: upload.systemImage, tint: upload.tint)
                StudyStatusCapsule(text: transcription.text, systemImage: transcription.systemImage, tint: transcription.tint)
                StudyStatusCapsule(text: note.text, systemImage: note.systemImage, tint: note.tint)
            }
        }
    }
}

struct StudyLibraryDetailLayout {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let spacing: CGFloat
    let showsScrollIndicators: Bool
    let wrapsPageBackground: Bool
    let actionColumns: [GridItem]

    static var mac: StudyLibraryDetailLayout {
        StudyLibraryDetailLayout(
            horizontalPadding: 0,
            topPadding: 0,
            bottomPadding: 28,
            spacing: 18,
            showsScrollIndicators: true,
            wrapsPageBackground: false,
            actionColumns: [
                GridItem(.flexible(minimum: 116), spacing: 10),
                GridItem(.flexible(minimum: 116), spacing: 10),
                GridItem(.flexible(minimum: 116), spacing: 10),
                GridItem(.flexible(minimum: 116), spacing: 10)
            ]
        )
    }

    static var iPhone: StudyLibraryDetailLayout {
        StudyLibraryDetailLayout(
            horizontalPadding: RokuricsMobilePageLayoutMetrics.horizontalPadding,
            topPadding: RokuricsMobilePageLayoutMetrics.topPadding,
            bottomPadding: RokuricsMobilePageLayoutMetrics.bottomPadding,
            spacing: RokuricsMobilePageLayoutMetrics.contentSpacing,
            showsScrollIndicators: false,
            wrapsPageBackground: true,
            actionColumns: [
                GridItem(.flexible(minimum: 116), spacing: 10),
                GridItem(.flexible(minimum: 116), spacing: 10)
            ]
        )
    }
}

struct StudyLibraryDetailContent<
    HeaderTrailing: View,
    Summary: View
>: View {
    let title: String
    let metadataText: String
    @Binding var type: String
    @Binding var subject: String
    @Binding var chapter: String
    @Binding var topic: String
    let items: [StudyItemMetadata]
    let folders: [StudyFolderMetadata]
    let statusMessage: String?
    let fileStatusRows: [RokuricsDocumentMetadataRow]
    let detailActions: [StudyDetailActionModel]
    var titleRenameTriggerID: Int
    let onRenameTitle: ((String) -> Void)?
    var layout: StudyLibraryDetailLayout
    let onBack: () -> Void
    let onSaveFiling: () -> Void
    let onCreateFilingValue: (StudyFolderLevel, String) -> Void
    let headerTrailing: () -> HeaderTrailing
    let summary: () -> Summary

    init(
        title: String,
        metadataText: String,
        type: Binding<String>,
        subject: Binding<String>,
        chapter: Binding<String>,
        topic: Binding<String>,
        items: [StudyItemMetadata],
        folders: [StudyFolderMetadata],
        statusMessage: String?,
        fileStatusRows: [RokuricsDocumentMetadataRow],
        detailActions: [StudyDetailActionModel],
        titleRenameTriggerID: Int = 0,
        onRenameTitle: ((String) -> Void)? = nil,
        layout: StudyLibraryDetailLayout,
        onBack: @escaping () -> Void,
        onSaveFiling: @escaping () -> Void,
        onCreateFilingValue: @escaping (StudyFolderLevel, String) -> Void,
        @ViewBuilder headerTrailing: @escaping () -> HeaderTrailing,
        @ViewBuilder summary: @escaping () -> Summary
    ) {
        self.title = title
        self.metadataText = metadataText
        self._type = type
        self._subject = subject
        self._chapter = chapter
        self._topic = topic
        self.items = items
        self.folders = folders
        self.statusMessage = statusMessage
        self.fileStatusRows = fileStatusRows
        self.detailActions = detailActions
        self.titleRenameTriggerID = titleRenameTriggerID
        self.onRenameTitle = onRenameTitle
        self.layout = layout
        self.onBack = onBack
        self.onSaveFiling = onSaveFiling
        self.onCreateFilingValue = onCreateFilingValue
        self.headerTrailing = headerTrailing
        self.summary = summary
    }

    var body: some View {
        Group {
            if layout.wrapsPageBackground {
                ZStack {
                    RokuricsSharedStyle.pageGradient(for: colorScheme)
                        .ignoresSafeArea()
                    scrollContent
                }
            } else {
                scrollContent
            }
        }
    }

    private var scrollContent: some View {
        ScrollView(showsIndicators: layout.showsScrollIndicators) {
            VStack(alignment: .leading, spacing: layout.spacing) {
                StudyLibraryDetailHeaderView(
                    title: title,
                    metadataText: metadataText,
                    onBack: onBack,
                    titleRenameTriggerID: titleRenameTriggerID,
                    onRenameTitle: onRenameTitle,
                    trailing: headerTrailing
                )

                LazyVGrid(columns: layout.actionColumns, alignment: .leading, spacing: 10) {
                    StudyDetailActionGrid(actions: detailActions)
                }

                filingPanel

                MetadataInfoPanel(title: "文件状态", rows: fileStatusRows)

                summary()
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, layout.topPadding)
            .padding(.bottom, layout.bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudyFilingPicker(
                type: $type,
                subject: $subject,
                chapter: $chapter,
                topic: $topic,
                items: items,
                folders: folders,
                onSave: onSaveFiling,
                onCreate: onCreateFilingValue
            )

            if let statusMessage {
                Text(statusMessage)
                    .font(statusFont)
                    .foregroundStyle(RokuricsSharedStyle.mint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsSharedGlassCard(cornerRadius: 16, fillOpacity: 0.30, strokeOpacity: 0.24, shadowOpacity: 0.035, shadowRadius: 7, shadowY: 3)
    }

    private var statusFont: Font {
        #if os(macOS)
        MacTypography.chineseCaption(size: 12, weight: .semibold)
        #else
        RokuricsTypography.font(for: .secondary)
        #endif
    }

    @Environment(\.colorScheme) private var colorScheme
}

struct StudyLibraryDetailHeaderView<Trailing: View>: View {
    let title: String
    let metadataText: String
    let onBack: () -> Void
    var titleRenameTriggerID = 0
    var onRenameTitle: ((String) -> Void)?
    let trailing: () -> Trailing
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        metadataText: String,
        onBack: @escaping () -> Void,
        titleRenameTriggerID: Int = 0,
        onRenameTitle: ((String) -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.metadataText = metadataText
        self.onBack = onBack
        self.titleRenameTriggerID = titleRenameTriggerID
        self.onRenameTitle = onRenameTitle
        self.trailing = trailing
    }

    var body: some View {
        #if os(iOS)
        RokuricsMobilePageHeader(
            leading: {
                StudyLibraryPageBackButton(action: onBack)
            },
            trailing: trailing
        ) {
            titleView
        } subtitle: {
            metadataView
        }
        #else
        HStack(alignment: .top, spacing: 12) {
            RokuricsBackButton(action: onBack)

            VStack(alignment: .leading, spacing: 7) {
                titleView

                metadataView
            }

            Spacer(minLength: 12)

            trailing()
        }
        #endif
    }

    private var titleView: some View {
        StudyInlineEditableText(
            text: title,
            token: .pageTitle,
            size: RokuricsMobilePageLayoutMetrics.titleSize,
            weight: .bold,
            editTriggerID: titleRenameTriggerID,
            onCommit: onRenameTitle
        ) { title in
            RokuricsSharedText(
                text: title,
                token: .pageTitle,
                size: RokuricsMobilePageLayoutMetrics.titleSize,
                weight: .bold
            )
                .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                .lineLimit(2)
        }
    }

    private var metadataView: some View {
        Text(metadataText)
            .font(metadataFont)
            .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
            .lineLimit(1)
    }

    private var metadataFont: Font {
        #if os(macOS)
        MacTypography.numberBody(size: 13, weight: .semibold)
        #else
        RokuricsTypography.numberBody(size: 12, weight: .semibold)
        #endif
    }
}

struct StudyReadingPageLayout {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let spacing: CGFloat
    let showsScrollIndicators: Bool
    let wrapsPageBackground: Bool

    static var mac: StudyReadingPageLayout {
        StudyReadingPageLayout(
            horizontalPadding: 0,
            topPadding: 0,
            bottomPadding: 28,
            spacing: 18,
            showsScrollIndicators: true,
            wrapsPageBackground: false
        )
    }

    static var iPhone: StudyReadingPageLayout {
        StudyReadingPageLayout(
            horizontalPadding: RokuricsMobilePageLayoutMetrics.horizontalPadding,
            topPadding: RokuricsMobilePageLayoutMetrics.topPadding,
            bottomPadding: RokuricsMobilePageLayoutMetrics.bottomPadding,
            spacing: RokuricsMobilePageLayoutMetrics.contentSpacing,
            showsScrollIndicators: false,
            wrapsPageBackground: true
        )
    }
}

struct StudyReadingPageContainer<Content: View>: View {
    let title: String
    let subtitle: String
    let primaryRows: [RokuricsDocumentMetadataRow]
    let advancedRows: [RokuricsDocumentMetadataRow]
    var layout: StudyReadingPageLayout
    let onBack: () -> Void
    let content: () -> Content

    @State private var isInfoPresented = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        subtitle: String,
        primaryRows: [RokuricsDocumentMetadataRow],
        advancedRows: [RokuricsDocumentMetadataRow],
        layout: StudyReadingPageLayout,
        onBack: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.primaryRows = primaryRows
        self.advancedRows = advancedRows
        self.layout = layout
        self.onBack = onBack
        self.content = content
    }

    var body: some View {
        Group {
            if layout.wrapsPageBackground {
                ZStack {
                    RokuricsSharedStyle.pageGradient(for: colorScheme)
                        .ignoresSafeArea()
                    scrollContent
                }
            } else {
                scrollContent
            }
        }
    }

    private var scrollContent: some View {
        ScrollView(showsIndicators: layout.showsScrollIndicators) {
            VStack(alignment: .leading, spacing: layout.spacing) {
                header
                content()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, layout.topPadding)
            .padding(.bottom, layout.bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        #if os(iOS)
        RokuricsMobilePageHeader(
            leading: {
                StudyLibraryPageBackButton(action: onBack)
            },
            trailing: {
                RokuricsInfoButton {
                    isInfoPresented = true
                }
                .sheet(isPresented: $isInfoPresented) {
                    RokuricsDocumentInfoSheet(primaryRows: primaryRows, advancedRows: advancedRows)
                }
            }
        ) {
            RokuricsSharedText(
                text: title,
                token: .pageTitle,
                size: RokuricsMobilePageLayoutMetrics.titleSize,
                weight: .bold
            )
                .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                .lineLimit(2)
        } subtitle: {
            RokuricsSharedText(text: subtitle, token: .pageSubtitle)
                .foregroundStyle(RokuricsSharedStyle.tertiaryText(for: colorScheme))
        }
        #else
        HStack(alignment: .top, spacing: 14) {
            RokuricsBackButton(action: onBack)

            VStack(alignment: .leading, spacing: 7) {
                RokuricsSharedText(text: title, token: .pageTitle, size: 32, weight: .bold)
                    .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                    .lineLimit(2)

                RokuricsSharedText(text: subtitle, token: .pageSubtitle)
                    .foregroundStyle(RokuricsSharedStyle.tertiaryText(for: colorScheme))
            }

            Spacer(minLength: 0)

            RokuricsInfoButton {
                isInfoPresented = true
            }
            .popover(isPresented: $isInfoPresented, arrowEdge: .bottom) {
                RokuricsDocumentInfoPopover(primaryRows: primaryRows, advancedRows: advancedRows)
            }
        }
        #endif
    }
}

struct StudyReadingLoadingCard: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RokuricsDocumentContentCard {
            Text(text)
                .font(loadingFont)
                .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
        }
    }

    private var loadingFont: Font {
        #if os(macOS)
        RokuricsDetailTypography.metadataValue
        #else
        RokuricsTypography.font(for: .body)
        #endif
    }
}

struct MetadataInfoPanel: View {
    var title = "文件状态"
    let rows: [RokuricsDocumentMetadataRow]
    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let visibleRows = rows.filter(\.isVisible)

        if !visibleRows.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(spacing: 0) {
                    ForEach(Array(visibleRows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(RokuricsSharedStyle.tertiaryText(for: colorScheme).opacity(0.18))
                                .frame(height: 1)
                                .padding(.leading, 18)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(row.label)
                                .font(labelFont)
                                .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                                .frame(width: 92, alignment: .leading)

                            RokuricsSharedText(
                                text: row.value,
                                token: row.isTechnical ? .technical : .body,
                                forceTechnical: row.isTechnical
                            )
                            .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                            .lineLimit(row.isTechnical ? 2 : 1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.vertical, 10)
                    }
                }
                .padding(.top, 10)
            } label: {
                RokuricsSharedText(text: title, token: .sectionTitle)
                    .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
            }
            .tint(RokuricsSharedStyle.softText(for: colorScheme))
            .padding(16)
            .rokuricsSharedGlassCard(cornerRadius: 22, fillOpacity: 0.26, strokeOpacity: 0.24, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
        }
    }

    private var labelFont: Font {
        #if os(macOS)
        MacTypography.chineseCaption(size: 12, weight: .semibold)
        #else
        RokuricsTypography.font(for: .secondary)
        #endif
    }
}

struct StudyReadingContentView: View {
    let title: String
    let markdown: String

    var body: some View {
        RokuricsDocumentContentCard(title: title) {
            RokuricsMarkdownContentView(markdown: markdown)
        }
    }
}

struct StudyNoteSummaryPreviewCard: View {
    let preview: NoteSummaryPreview?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RokuricsDocumentContentCard(title: "AI 摘要") {
            VStack(alignment: .leading, spacing: 12) {
                if let preview, preview.isVisible {
                    if !preview.shortSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        RokuricsSharedText(text: preview.shortSummary, token: .body)
                            .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !preview.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(preview.keyPoints.prefix(4), id: \.self) { point in
                                HStack(alignment: .firstTextBaseline, spacing: 9) {
                                    Text("•")
                                        .font(bodyEmphasisFont)
                                        .foregroundStyle(RokuricsSharedStyle.aqua)
                                    RokuricsSharedText(text: point, token: .body)
                                        .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                } else {
                    Text("暂无摘要")
                        .font(secondaryFont)
                        .foregroundStyle(RokuricsSharedStyle.softText(for: colorScheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bodyEmphasisFont: Font {
        #if os(macOS)
        RokuricsDetailTypography.bodyEmphasis
        #else
        RokuricsTypography.body(size: 15, weight: .semibold)
        #endif
    }

    private var secondaryFont: Font {
        #if os(macOS)
        RokuricsDetailTypography.metadataValue
        #else
        RokuricsTypography.font(for: .body)
        #endif
    }
}
