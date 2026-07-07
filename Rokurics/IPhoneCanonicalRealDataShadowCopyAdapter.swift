//
//  IPhoneCanonicalRealDataShadowCopyAdapter.swift
//  Rokurics
//
//  Created by Codex on 2026/6/3.
//

import Foundation

nonisolated struct IPhoneCanonicalRealDataShadowCopyAdapter: Sendable {
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
        var recordings: [RecordingMetadata]
        var inventory: LocalNetworkSyncInventory?
        var studyManifest: StudyLibrarySyncManifest?
        var generatedArtifacts: [GeneratedArtifactFact]
        var policy: CanonicalRealDataShadowCopyPolicy

        nonisolated init(
            productionRootURL: URL? = nil,
            shadowRootURL: URL,
            rootToken: CanonicalRootToken = CanonicalRootToken("iphone-execution-shadow-root"),
            cleanupRootID: String = UUID().uuidString,
            recordings: [RecordingMetadata] = [],
            inventory: LocalNetworkSyncInventory? = nil,
            studyManifest: StudyLibrarySyncManifest? = nil,
            generatedArtifacts: [GeneratedArtifactFact] = [],
            policy: CanonicalRealDataShadowCopyPolicy = .enabled()
        ) {
            self.productionRootURL = productionRootURL?.standardizedFileURL
            self.shadowRootURL = shadowRootURL.standardizedFileURL
            self.rootToken = rootToken
            self.cleanupRootID = CanonicalProductionRedaction.safeIdentifier(cleanupRootID, fallback: "iphone-shadow-root")
            self.recordings = recordings
            self.inventory = inventory
            self.studyManifest = studyManifest
            self.generatedArtifacts = generatedArtifacts
            self.policy = policy
        }
    }

    nonisolated init() {}

    nonisolated func buildPlan(_ input: Input) -> CanonicalRealDataShadowCopyPlan {
        var sources: [CanonicalRealDataShadowCopySource] = []
        for recording in input.recordings {
            if let bytes = try? Self.encoder.encode(recording) {
                sources.append(
                    .inline(
                        sourceID: "iphone-recording-metadata-\(recording.id)",
                        kind: .recordingMetadata,
                        logicalName: "\(recording.id).json",
                        targetLogicalPathToken: "metadata/\(safeToken(recording.id)).json",
                        bytes: bytes,
                        modifiedAt: recording.endedAt
                    )
                )
            }
            sources.append(audioDescriptorSource(recording))
        }
        if let studyManifest = input.studyManifest,
           let bytes = try? Self.encoder.encode(studyManifest) {
            sources.append(
                .inline(
                    sourceID: "iphone-study-manifest",
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
                    sourceID: "iphone-local-inventory",
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
                        sourceID: "iphone-generated-artifact-\(artifact.artifactID)",
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
                        sourceID: "iphone-generated-artifact-\(artifact.artifactID)",
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
            planID: "iphone-real-data-shadow-copy-\(input.cleanupRootID)",
            sources: sources,
            target: target,
            policy: input.policy
        )
    }

    nonisolated func copy(_ input: Input, fileManager: FileManager = .default) -> CanonicalRealDataShadowCopyResult {
        CanonicalRealDataShadowCopyRunner().run(plan: buildPlan(input), fileManager: fileManager)
    }

    private nonisolated func audioDescriptorSource(_ recording: RecordingMetadata) -> CanonicalRealDataShadowCopySource {
        let descriptor = AudioDescriptor(
            objectID: recording.id,
            logicalPathToken: recording.relativeAudioPath,
            byteSize: recording.fileSize,
            contentHashPrefix: nil,
            descriptorOnly: true
        )
        let bytes = (try? Self.encoder.encode(descriptor)) ?? Data()
        return .descriptor(
            sourceID: "iphone-audio-descriptor-\(recording.id)",
            logicalName: "audio-descriptor.json",
            targetLogicalPathToken: "audio-descriptors/\(safeToken(recording.id)).json",
            descriptorBytes: bytes,
            byteSize: recording.fileSize
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
            sourceID: "iphone-inventory-audio-descriptor-\(recording.recordingID)",
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
