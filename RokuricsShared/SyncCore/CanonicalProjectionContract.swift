//
//  CanonicalProjectionContract.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalArtifactProducer: String, Codable, Equatable, CaseIterable, Sendable {
    case audioCapture
    case transcription
    case noteGeneration
    case unknown
}

nonisolated enum CanonicalProjectionContract {
    nonisolated static let generatedArtifactKinds: Set<CanonicalArtifact.Kind> = [
        .transcriptJSON,
        .transcriptMarkdown,
        .noteMarkdown,
        .noteJSON,
        .summaryJSON
    ]

    nonisolated static func artifactID(objectID: String, kind: CanonicalArtifact.Kind) -> String {
        kind.artifactID(for: normalizedRequired(objectID, fallback: "unknown-recording"))
    }

    nonisolated static func artifactKey(objectID: String, kind: CanonicalArtifact.Kind) -> String {
        "\(normalizedRequired(objectID, fallback: "unknown-recording"))|\(kind.rawValue)"
    }

    nonisolated static func makeCanonicalFolderID(_ folderID: String) -> CanonicalLibraryObjectID {
        CanonicalLibraryObjectID(folderID, fallback: "folder:unknown")
    }

    nonisolated static func makeCanonicalStudyItemID(_ itemID: String) -> CanonicalLibraryObjectID {
        CanonicalLibraryObjectID(itemID, fallback: "studyItem:unknown")
    }

    nonisolated static func normalizeFolderName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未命名文件夹"
    }

    nonisolated static func normalizeStudyItemTitle(_ title: String, itemKind: CanonicalStudyItemKind = .unknown) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (itemKind == .standaloneNote ? "未命名笔记" : "未命名条目")
    }

    nonisolated static func normalizeTags(_ tags: [String]) -> [String] {
        Array(Set(tags.compactMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.lowercased()
        })).sorted()
    }

    nonisolated static func normalizeFilingPath(_ path: CanonicalHierarchyPath) -> CanonicalHierarchyPath {
        CanonicalHierarchyPath(path.components)
    }

    nonisolated static func normalizeParentReferences(_ references: [CanonicalParentReference]) -> [CanonicalParentReference] {
        var seen = Set<String>()
        return references
            .sorted { $0.parentID.rawValue < $1.parentID.rawValue }
            .filter { reference in
                let key = "\(reference.relation)|\(reference.parentID.rawValue)"
                return seen.insert(key).inserted
            }
    }

    nonisolated static func normalizeTombstone(isDeleted: Bool, deletedAt: CanonicalTimestamp?) -> CanonicalTimestamp? {
        isDeleted ? deletedAt : nil
    }

    nonisolated static func metadataHashPayload(for folder: CanonicalFolderMetadata) -> [String: String] {
        CanonicalLibraryMetadataBusinessFields(folder: folder).stableBusinessHashInput
    }

    nonisolated static func metadataHashPayload(for item: CanonicalStudyItemMetadata) -> [String: String] {
        CanonicalLibraryMetadataBusinessFields(item: item).stableBusinessHashInput
    }

    nonisolated static func objectKind(
        legacyItemKind: String,
        recordingID: String?
    ) -> CanonicalObjectKind {
        let kind = legacyItemKind.trimmingCharacters(in: .whitespacesAndNewlines)
        if recordingID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil {
            return .recordingAssociatedStudyItem
        }
        if kind == "standaloneNote" {
            return .standaloneNote
        }
        return kind.isEmpty ? .unknownUnsupported : .standaloneStudyItem
    }

    nonisolated static func safeLogicalResourceToken(_ token: String?) -> String? {
        safeLogicalPathToken(token)
    }

    nonisolated static func safeLogicalPathToken(_ token: String?) -> String? {
        guard let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.contains("://"),
              !trimmed.contains("\\") else {
            return nil
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return trimmed
    }

    nonisolated private static func timestampString(_ timestamp: CanonicalTimestamp) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), timestamp.date.timeIntervalSince1970)
    }

    nonisolated static func logicalName(from token: String?) -> String? {
        guard let safeToken = safeLogicalPathToken(token) else {
            return nil
        }
        return safeToken.split(separator: "/").last.map(String.init)
    }

    nonisolated static func producer(for kind: CanonicalArtifact.Kind, platform: String) -> CanonicalArtifactProducer {
        let normalizedPlatform = platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch kind {
        case .audio:
            return normalizedPlatform.contains("iphone") ? .audioCapture : .unknown
        case .transcriptJSON, .transcriptMarkdown:
            return normalizedPlatform.contains("mac") ? .transcription : .unknown
        case .noteMarkdown, .noteJSON, .summaryJSON:
            return normalizedPlatform.contains("mac") ? .noteGeneration : .unknown
        case .metadata, .receiveRecord:
            return .unknown
        }
    }

    nonisolated static func requiredCapability(for kind: CanonicalArtifact.Kind) -> CanonicalCapability? {
        switch kind {
        case .audio:
            return .audioArtifact
        case .transcriptJSON, .transcriptMarkdown:
            return .transcriptArtifact
        case .noteMarkdown, .noteJSON:
            return .noteArtifact
        case .summaryJSON:
            return .summaryArtifact
        case .metadata, .receiveRecord:
            return nil
        }
    }

    nonisolated static func availability(
        isPresent: Bool,
        contentHash: CanonicalHash?,
        byteSize: Int64?
    ) -> CanonicalArtifact.Availability {
        guard isPresent else {
            return .missing
        }
        return contentHash != nil && byteSize != nil ? .available : .availableWithoutHash
    }

    nonisolated static func makeArtifact(
        objectID: String,
        kind: CanonicalArtifact.Kind,
        availability: CanonicalArtifact.Availability,
        contentHash: CanonicalHash? = nil,
        byteSize: Int64? = nil,
        logicalPathToken: String? = nil,
        modifiedAt: CanonicalTimestamp? = nil,
        observedAt: CanonicalTimestamp? = nil,
        producedByNodeID: String? = nil,
        platform: String
    ) -> CanonicalArtifact {
        let safeToken = safeLogicalPathToken(logicalPathToken)
        let producer = producer(for: kind, platform: platform)
        return CanonicalArtifact(
            artifactID: artifactID(objectID: objectID, kind: kind),
            objectID: objectID,
            kind: kind,
            availability: availability,
            contentHash: contentHash,
            byteSize: byteSize,
            logicalName: logicalName(from: safeToken),
            logicalPathToken: safeToken,
            modifiedAt: modifiedAt,
            observedAt: observedAt,
            producedBy: producer == .unknown ? nil : producer,
            producedByNodeID: producedByNodeID
        )
    }

    nonisolated static func provesGeneratedArtifactAvailability(_ artifact: CanonicalArtifact?) -> Bool {
        guard let artifact,
              generatedArtifactKinds.contains(artifact.kind),
              artifact.availability == .available,
              artifact.contentHash != nil,
              artifact.byteSize != nil,
              artifact.tombstone != true else {
            return false
        }
        return true
    }

    nonisolated static func sameContent(_ left: CanonicalArtifact, _ right: CanonicalArtifact) -> Bool {
        left.contentHash?.algorithm == right.contentHash?.algorithm
            && left.contentHash?.value == right.contentHash?.value
            && left.byteSize == right.byteSize
            && left.contentHash != nil
            && left.byteSize != nil
    }

    nonisolated static func isAuthoritativeProducer(_ artifact: CanonicalArtifact, node: CanonicalNode) -> Bool {
        guard artifact.tombstone != true,
              let requiredCapability = requiredCapability(for: artifact.kind),
              node.capabilities.contains(requiredCapability) else {
            return false
        }
        if let producedByNodeID = artifact.producedByNodeID,
           producedByNodeID != node.nodeID {
            return false
        }
        switch artifact.kind {
        case .audio:
            return artifact.producedBy == .audioCapture
                && node.platform.lowercased().contains("iphone")
        case .transcriptJSON, .transcriptMarkdown:
            return artifact.producedBy == .transcription
                && node.platform.lowercased().contains("mac")
        case .noteMarkdown, .noteJSON, .summaryJSON:
            return artifact.producedBy == .noteGeneration
                && node.platform.lowercased().contains("mac")
        case .metadata, .receiveRecord:
            return false
        }
    }

    nonisolated private static func normalizedRequired(_ value: String, fallback: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallback
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
