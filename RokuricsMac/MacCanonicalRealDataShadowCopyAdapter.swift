//
//  MacCanonicalRealDataShadowCopyAdapter.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/3.
//

import Foundation

nonisolated struct MacCanonicalRealDataShadowCopyAdapter: Sendable {
    nonisolated struct GeneratedArtifactFact: Equatable, Sendable {
        var artifactID: String
        var logicalPathToken: String
        var logicalName: String
        var sourceURL: URL?
        var bytes: Data?
        var byteSize: Int64?
        var contentHash: CanonicalHash?
        var modifiedAt: Date?

        nonisolated init(
            artifactID: String,
            logicalPathToken: String,
            logicalName: String,
            sourceURL: URL? = nil,
            bytes: Data? = nil,
            byteSize: Int64? = nil,
            contentHash: CanonicalHash? = nil,
            modifiedAt: Date? = nil
        ) {
            self.artifactID = CanonicalProductionRedaction.safeIdentifier(artifactID, fallback: "artifact")
            self.logicalPathToken = logicalPathToken
            self.logicalName = logicalName
            self.sourceURL = sourceURL?.standardizedFileURL
            self.bytes = bytes
            self.byteSize = byteSize
            self.contentHash = contentHash
            self.modifiedAt = modifiedAt
        }
    }

    nonisolated struct Input: Sendable {
        var productionRootURL: URL?
        var shadowRootURL: URL
        var rootToken: CanonicalRootToken
        var cleanupRootID: String
        var receiveRecords: [RecordingReceiveRecord]
        var inboxItems: [MacRecordingInboxItem]
        var inventory: LocalNetworkSyncInventory?
        var studyManifest: StudyLibrarySyncManifest?
        var generatedArtifacts: [GeneratedArtifactFact]
        var policy: CanonicalRealDataShadowCopyPolicy

        nonisolated init(
            productionRootURL: URL? = nil,
            shadowRootURL: URL,
            rootToken: CanonicalRootToken = CanonicalRootToken("mac-execution-shadow-root"),
            cleanupRootID: String = UUID().uuidString,
            receiveRecords: [RecordingReceiveRecord] = [],
            inboxItems: [MacRecordingInboxItem] = [],
            inventory: LocalNetworkSyncInventory? = nil,
            studyManifest: StudyLibrarySyncManifest? = nil,
            generatedArtifacts: [GeneratedArtifactFact] = [],
            policy: CanonicalRealDataShadowCopyPolicy = .enabled()
        ) {
            self.productionRootURL = productionRootURL?.standardizedFileURL
            self.shadowRootURL = shadowRootURL.standardizedFileURL
            self.rootToken = rootToken
            self.cleanupRootID = CanonicalProductionRedaction.safeIdentifier(cleanupRootID, fallback: "mac-shadow-root")
            self.receiveRecords = receiveRecords
            self.inboxItems = inboxItems
            self.inventory = inventory
            self.studyManifest = studyManifest
            self.generatedArtifacts = generatedArtifacts
            self.policy = policy
        }
    }

    nonisolated init() {}

    nonisolated func buildPlan(_ input: Input) -> CanonicalRealDataShadowCopyPlan {
        var sources: [CanonicalRealDataShadowCopySource] = []
        for record in input.receiveRecords {
            if let bytes = try? Self.encoder.encode(record) {
                sources.append(
                    .inline(
                        sourceID: "mac-receive-record-\(record.recordingID)",
                        kind: .receiveRecord,
                        logicalName: "receive.json",
                        targetLogicalPathToken: "receive/\(safeToken(record.recordingID)).json",
                        bytes: bytes,
                        modifiedAt: record.updatedAt
                    )
                )
            }
            sources.append(audioDescriptorSource(record))
        }
        for item in input.inboxItems {
            sources.append(audioDescriptorSource(item))
        }
        if let studyManifest = input.studyManifest,
           let bytes = try? Self.encoder.encode(studyManifest) {
            sources.append(
                .inline(
                    sourceID: "mac-study-manifest",
                    kind: .studyMetadata,
                    logicalName: "study-manifest.json",
                    targetLogicalPathToken: "study/manifest.json",
                    bytes: bytes,
                    modifiedAt: studyManifest.generatedAt
                )
            )
        }
        if let inventory = input.inventory,
           let bytes = try? Self.encoder.encode(inventory) {
            sources.append(
                .inline(
                    sourceID: "mac-local-inventory",
                    kind: .studyMetadata,
                    logicalName: "inventory.json",
                    targetLogicalPathToken: "inventory/local.json",
                    bytes: bytes,
                    modifiedAt: inventory.device.generatedAt
                )
            )
            for recording in inventory.recordings {
                sources.append(audioDescriptorSource(recording))
            }
        }
        for artifact in input.generatedArtifacts {
            if let bytes = artifact.bytes {
                sources.append(
                    .inline(
                        sourceID: "mac-generated-artifact-\(artifact.artifactID)",
                        kind: .generatedArtifact,
                        logicalName: artifact.logicalName,
                        targetLogicalPathToken: "generated/\(safeToken(artifact.artifactID)).json",
                        bytes: bytes,
                        contentHash: artifact.contentHash,
                        modifiedAt: artifact.modifiedAt
                    )
                )
            } else if let sourceURL = artifact.sourceURL, let productionRootURL = input.productionRootURL {
                sources.append(
                    .file(
                        sourceID: "mac-generated-artifact-\(artifact.artifactID)",
                        kind: .generatedArtifact,
                        logicalName: artifact.logicalName,
                        targetLogicalPathToken: "generated/\(safeToken(artifact.artifactID)).json",
                        productionRootURL: productionRootURL,
                        sourceURL: sourceURL,
                        byteSize: artifact.byteSize,
                        modifiedAt: artifact.modifiedAt,
                        contentHash: artifact.contentHash
                    )
                )
            }
        }
        let target = CanonicalRealDataShadowCopyTarget(
            rootToken: input.rootToken,
            rootKind: .shadowCopy,
            rootURL: input.shadowRootURL,
            prohibitedProductionRootURL: input.productionRootURL
        )
        return CanonicalRealDataShadowCopyPlan(
            planID: "mac-real-data-shadow-copy-\(input.cleanupRootID)",
            sources: sources,
            target: target,
            policy: input.policy
        )
    }

    nonisolated func copy(_ input: Input, fileManager: FileManager = .default) -> CanonicalRealDataShadowCopyResult {
        CanonicalRealDataShadowCopyRunner().run(plan: buildPlan(input), fileManager: fileManager)
    }

    private nonisolated func audioDescriptorSource(_ record: RecordingReceiveRecord) -> CanonicalRealDataShadowCopySource {
        let descriptor = AudioDescriptor(
            objectID: record.recordingID,
            logicalPathToken: record.audioRelativePath,
            byteSize: record.fileSize,
            contentHashPrefix: record.checksum.flatMap { CanonicalProductionRedaction.hashPrefix($0) },
            descriptorOnly: true
        )
        let bytes = (try? Self.encoder.encode(descriptor)) ?? Data()
        return .descriptor(
            sourceID: "mac-audio-descriptor-\(record.recordingID)",
            logicalName: "audio-descriptor.json",
            targetLogicalPathToken: "audio-descriptors/\(safeToken(record.recordingID)).json",
            descriptorBytes: bytes,
            byteSize: record.fileSize
        )
    }

    private nonisolated func audioDescriptorSource(_ item: MacRecordingInboxItem) -> CanonicalRealDataShadowCopySource {
        let descriptor = AudioDescriptor(
            objectID: item.id,
            logicalPathToken: item.audioRelativePath,
            byteSize: item.fileSize,
            contentHashPrefix: item.audioChecksum.flatMap { CanonicalProductionRedaction.hashPrefix($0) },
            descriptorOnly: true
        )
        let bytes = (try? Self.encoder.encode(descriptor)) ?? Data()
        return .descriptor(
            sourceID: "mac-inbox-audio-descriptor-\(item.id)",
            logicalName: "audio-descriptor.json",
            targetLogicalPathToken: "audio-descriptors/\(safeToken(item.id)).json",
            descriptorBytes: bytes,
            byteSize: item.fileSize
        )
    }

    private nonisolated func audioDescriptorSource(_ recording: LocalNetworkSyncRecordingEntry) -> CanonicalRealDataShadowCopySource {
        let descriptor = AudioDescriptor(
            objectID: recording.recordingID,
            logicalPathToken: recording.audioLogicalPathToken,
            byteSize: recording.audioSize,
            contentHashPrefix: recording.audioChecksum.flatMap { CanonicalProductionRedaction.hashPrefix($0) },
            descriptorOnly: true
        )
        let bytes = (try? Self.encoder.encode(descriptor)) ?? Data()
        return .descriptor(
            sourceID: "mac-inventory-audio-descriptor-\(recording.recordingID)",
            logicalName: "audio-descriptor.json",
            targetLogicalPathToken: "audio-descriptors/\(safeToken(recording.recordingID)).json",
            descriptorBytes: bytes,
            byteSize: recording.audioSize
        )
    }

    private nonisolated func safeToken(_ value: String) -> String {
        CanonicalProductionRedaction.safeIdentifier(value, fallback: "object")
            .replacingOccurrences(of: ":", with: "-")
    }

    private struct AudioDescriptor: Codable, Equatable {
        var objectID: String
        var logicalPathToken: String?
        var byteSize: Int64?
        var contentHashPrefix: String?
        var descriptorOnly: Bool
    }

    private nonisolated static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
