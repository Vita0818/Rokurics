//
//  LocalNetworkBusinessSignatureV2.swift
//  RokuricsShared
//
//  Cross-device business metadata signatures for local-network sync.
//

import CryptoKit
import Foundation

/// A normalized tag that is safe to compare across device-local models.
///
/// Tag creation dates and generated identifiers are intentionally absent. The
/// three user-facing components are normalized and sorted before hashing.
nonisolated struct LocalNetworkBusinessTagV2: Codable, Equatable, Hashable, Sendable {
    let namespace: String
    let value: String
    let displayName: String

    nonisolated init(namespace: String, value: String, displayName: String? = nil) {
        self.namespace = LocalNetworkBusinessSignatureV2.normalizedComparisonText(namespace).lowercased()
        self.value = LocalNetworkBusinessSignatureV2.normalizedComparisonText(value).lowercased()
        self.displayName = LocalNetworkBusinessSignatureV2.normalizedText(displayName)
    }
}

/// A custom property explicitly admitted to the cross-device business schema.
/// Unknown, transport, diagnostic, preview and device-local keys never enter a
/// signature merely because they happen to exist in a model dictionary.
nonisolated struct LocalNetworkBusinessCustomPropertyV2: Codable, Equatable, Hashable, Sendable {
    let key: String
    let value: String

    nonisolated init(key: String, value: String) {
        self.key = LocalNetworkBusinessSignatureV2.normalizedComparisonText(key).lowercased()
        self.value = LocalNetworkBusinessSignatureV2.normalizedText(value)
    }
}

/// Semantic filing/classification values. These are user business metadata,
/// not filesystem paths or device-local resource locations.
nonisolated struct LocalNetworkBusinessFilingV2: Codable, Equatable, Hashable, Sendable {
    let type: String
    let subject: String
    let chapter: String
    let topic: String

    nonisolated init(
        type: String? = nil,
        subject: String? = nil,
        chapter: String? = nil,
        topic: String? = nil
    ) {
        self.type = LocalNetworkBusinessSignatureV2.normalizedText(type)
        self.subject = LocalNetworkBusinessSignatureV2.normalizedText(subject)
        self.chapter = LocalNetworkBusinessSignatureV2.normalizedText(chapter)
        self.topic = LocalNetworkBusinessSignatureV2.normalizedText(topic)
    }
}

nonisolated struct LocalNetworkRecordingBusinessFieldsV2: Codable, Equatable, Sendable {
    let recordingID: String
    let title: String
    let filing: LocalNetworkBusinessFilingV2
    let tags: [LocalNetworkBusinessTagV2]
    let isDeleted: Bool
    let customProperties: [LocalNetworkBusinessCustomPropertyV2]

    nonisolated init(
        recordingID: String,
        title: String,
        filing: LocalNetworkBusinessFilingV2 = LocalNetworkBusinessFilingV2(),
        tags: [LocalNetworkBusinessTagV2] = [],
        isDeleted: Bool,
        customProperties: [LocalNetworkBusinessCustomPropertyV2] = []
    ) {
        self.recordingID = LocalNetworkBusinessSignatureV2.normalizedIdentifier(recordingID)
        self.title = LocalNetworkBusinessSignatureV2.normalizedText(title)
        self.filing = filing
        self.tags = LocalNetworkBusinessSignatureV2.normalizedTags(tags)
        self.isDeleted = isDeleted
        self.customProperties = LocalNetworkBusinessSignatureV2.normalizedCustomProperties(customProperties)
    }
}

nonisolated struct LocalNetworkStudyItemBusinessFieldsV2: Codable, Equatable, Sendable {
    let itemID: String
    let itemKind: String
    let title: String
    let filing: LocalNetworkBusinessFilingV2
    let tags: [LocalNetworkBusinessTagV2]
    let recordingID: String
    let isTrashed: Bool
    let customProperties: [LocalNetworkBusinessCustomPropertyV2]

    nonisolated init(
        itemID: String,
        itemKind: String,
        title: String,
        filing: LocalNetworkBusinessFilingV2 = LocalNetworkBusinessFilingV2(),
        tags: [LocalNetworkBusinessTagV2] = [],
        recordingID: String? = nil,
        isTrashed: Bool,
        customProperties: [LocalNetworkBusinessCustomPropertyV2] = []
    ) {
        self.itemID = LocalNetworkBusinessSignatureV2.normalizedIdentifier(itemID)
        self.itemKind = LocalNetworkBusinessSignatureV2.normalizedComparisonText(itemKind)
        self.title = LocalNetworkBusinessSignatureV2.normalizedText(title)
        self.filing = filing
        self.tags = LocalNetworkBusinessSignatureV2.normalizedTags(tags)
        self.recordingID = LocalNetworkBusinessSignatureV2.normalizedIdentifier(recordingID)
        self.isTrashed = isTrashed
        self.customProperties = LocalNetworkBusinessSignatureV2.normalizedCustomProperties(customProperties)
    }
}

nonisolated struct LocalNetworkFolderBusinessFieldsV2: Codable, Equatable, Sendable {
    let folderID: String
    let name: String
    let level: String
    let parentFolderID: String
    let colorToken: String
    let isTrashed: Bool
    let customProperties: [LocalNetworkBusinessCustomPropertyV2]

    nonisolated init(
        folderID: String,
        name: String,
        level: String,
        parentFolderID: String? = nil,
        colorToken: String? = nil,
        isTrashed: Bool,
        customProperties: [LocalNetworkBusinessCustomPropertyV2] = []
    ) {
        self.folderID = LocalNetworkBusinessSignatureV2.normalizedIdentifier(folderID)
        self.name = LocalNetworkBusinessSignatureV2.normalizedText(name)
        self.level = LocalNetworkBusinessSignatureV2.normalizedComparisonText(level)
        self.parentFolderID = LocalNetworkBusinessSignatureV2.normalizedIdentifier(parentFolderID)
        self.colorToken = LocalNetworkBusinessSignatureV2.normalizedComparisonText(colorToken)
        self.isTrashed = isTrashed
        self.customProperties = LocalNetworkBusinessSignatureV2.normalizedCustomProperties(customProperties)
    }
}

/// Deterministic v2 signatures for metadata comparison between iPhone and Mac.
///
/// Timestamps, file/resource paths, transfer/processing state, source-device
/// facts, conflict diagnostics and derived identifier lists are deliberately
/// absent from all field structs. Business clocks remain separate planner data.
nonisolated enum LocalNetworkBusinessSignatureV2 {
    nonisolated static let schemaVersion = "local-network-business-signature-v2"
    nonisolated static let wirePrefix = "ln-business-v2:"

    /// No current custom-property key is part of the business schema. Adding a
    /// key here is an explicit protocol decision and requires cross-device tests.
    nonisolated static let explicitBusinessCustomPropertyKeys: Set<String> = []

    nonisolated static func recording(_ fields: LocalNetworkRecordingBusinessFieldsV2) -> String {
        versionedHash(entityKind: "recording", fields: fields)
    }

    nonisolated static func studyItem(_ fields: LocalNetworkStudyItemBusinessFieldsV2) -> String {
        versionedHash(entityKind: "studyItem", fields: fields)
    }

    nonisolated static func folder(_ fields: LocalNetworkFolderBusinessFieldsV2) -> String {
        versionedHash(entityKind: "folder", fields: fields)
    }

    nonisolated static func isCurrentVersion(_ signature: String?) -> Bool {
        signature?.hasPrefix(wirePrefix) == true
    }

    nonisolated static func filteredBusinessCustomProperties(
        _ properties: [String: String],
        explicitBusinessKeys: Set<String> = explicitBusinessCustomPropertyKeys
    ) -> [LocalNetworkBusinessCustomPropertyV2] {
        let allowed = Set(explicitBusinessKeys.map { normalizedComparisonText($0).lowercased() })
        guard !allowed.isEmpty else {
            return []
        }
        return normalizedCustomProperties(properties.compactMap { key, value in
            let normalizedKey = normalizedComparisonText(key).lowercased()
            guard allowed.contains(normalizedKey) else {
                return nil
            }
            return LocalNetworkBusinessCustomPropertyV2(key: normalizedKey, value: value)
        })
    }

    /// Replaces only explicitly admitted business keys. All local-only keys in
    /// the destination dictionary survive unchanged.
    nonisolated static func mergingBusinessCustomProperties(
        local: [String: String],
        remote: [String: String],
        explicitBusinessKeys: Set<String> = explicitBusinessCustomPropertyKeys
    ) -> [String: String] {
        let allowed = Set(explicitBusinessKeys.map { normalizedComparisonText($0).lowercased() })
        guard !allowed.isEmpty else {
            return local
        }

        var result = local
        for existingKey in Array(result.keys) where allowed.contains(normalizedComparisonText(existingKey).lowercased()) {
            result.removeValue(forKey: existingKey)
        }
        for property in filteredBusinessCustomProperties(
            remote,
            explicitBusinessKeys: allowed
        ) {
            result[property.key] = property.value
        }
        return result
    }

    nonisolated static func normalizedTags(_ tags: [LocalNetworkBusinessTagV2]) -> [LocalNetworkBusinessTagV2] {
        Array(Set(tags)).sorted {
            if $0.namespace != $1.namespace { return $0.namespace < $1.namespace }
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.displayName < $1.displayName
        }
    }

    nonisolated static func normalizedCustomProperties(
        _ properties: [LocalNetworkBusinessCustomPropertyV2]
    ) -> [LocalNetworkBusinessCustomPropertyV2] {
        Array(Set(properties)).sorted {
            if $0.key != $1.key { return $0.key < $1.key }
            return $0.value < $1.value
        }
    }

    nonisolated static func normalizedText(_ value: String?) -> String {
        value?
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    nonisolated static func normalizedComparisonText(_ value: String?) -> String {
        normalizedText(value)
    }

    nonisolated static func normalizedIdentifier(_ value: String?) -> String {
        normalizedText(value)
    }

    private nonisolated static func versionedHash<Fields: Encodable>(entityKind: String, fields: Fields) -> String {
        let payload = SignaturePayload(
            schemaVersion: schemaVersion,
            entityKind: entityKind,
            fields: fields
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            preconditionFailure("Local-network business signature encoding failed")
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return wirePrefix + digest
    }
}

private nonisolated struct SignaturePayload<Fields: Encodable>: Encodable {
    let schemaVersion: String
    let entityKind: String
    let fields: Fields
}
