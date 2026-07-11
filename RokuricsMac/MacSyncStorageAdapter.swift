//
//  MacSyncStorageAdapter.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/30.
//

import Foundation

@MainActor
struct MacSyncStorageAdapter: SyncStorageAdapter {
    let recordingFileStore: MacRecordingFileStore
    let studyLibraryStore: StudyLibraryStore
    let fileManager: FileManager
    let checksumRuntime: CanonicalChecksumRuntime

    init(
        recordingFileStore: MacRecordingFileStore,
        studyLibraryStore: StudyLibraryStore,
        fileManager: FileManager = .default,
        checksumRuntime: CanonicalChecksumRuntime = CanonicalChecksumRuntime()
    ) {
        self.recordingFileStore = recordingFileStore
        self.studyLibraryStore = studyLibraryStore
        self.fileManager = fileManager
        self.checksumRuntime = checksumRuntime
    }

    func buildDirectorySnapshot() throws -> [SyncDirectory] {
        studyLibraryStore
            .makeSyncManifest(deviceID: "mac-local")
            .folders
            .map { folder in
                SyncDirectory(
                    directoryID: folder.folderID,
                    parentID: folder.parentFolderID,
                    pathComponents: folder.path.displaySummary.split(separator: "/").map(String.init),
                    name: folder.name,
                    colorToken: folder.colorToken?.rawValue,
                    updatedAt: folder.updatedAt,
                    tombstone: folder.isTrashed,
                    revisionHash: folder.localNetworkFolderBusinessSignatureV2
                )
            }
    }

    func buildObjectSnapshot() throws -> [SyncObject] {
        let generatedAt = Date()
        let manifest = studyLibraryStore.makeSyncManifest(deviceID: "mac-local", generatedAt: generatedAt)
        let device = LocalNetworkSyncDeviceSection(
            deviceID: "mac-local",
            deviceName: "Mac",
            platform: .Mac,
            generatedAt: generatedAt,
            lastKnownPeerRevision: nil,
            appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
        )
        return LocalNetworkSyncInventory.make(
            device: device,
            folders: manifest.folders.map(localNetworkFolder),
            studyItems: manifest.items.map(localNetworkStudyItem),
            artifacts: makeArtifacts(from: manifest),
            studyManifest: manifest
        )
        .syncCoreInventory
        .objects
    }

    func resolveLogicalPathToken(_ token: String, for object: SyncObject) throws -> URL {
        if let kind = artifactKind(for: object), kind != .audio {
            return try LocalNetworkSyncArtifactFileService.safeFileURL(
                rootURL: recordingFileStore.libraryRootURL,
                logicalPathToken: token,
                kind: kind
            )
        }
        return try LocalNetworkSyncArtifactFileService.safeFileURL(
            rootURL: recordingFileStore.libraryRootURL,
            logicalPathToken: token
        )
    }

    func createPlaceholder(for object: SyncObject) throws {
        guard let token = object.logicalPathToken else {
            return
        }
        let url = try resolveLogicalPathToken(token, for: object)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func openReadStream(for object: SyncObject) throws -> InputStream {
        guard let token = object.logicalPathToken else {
            throw StudyLibraryStoreError.writeFailed("sync_object_missing_logical_path")
        }
        let url = try resolveLogicalPathToken(token, for: object)
        guard let stream = InputStream(url: url) else {
            throw StudyLibraryStoreError.writeFailed("sync_read_stream_unavailable")
        }
        return stream
    }

    func openWriteTemp(for object: SyncObject) throws -> URL {
        let tempDirectory = recordingFileStore.libraryRootURL
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("Incoming", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return tempDirectory.appendingPathComponent("\(object.objectID.safeSyncFileComponent)-\(UUID().uuidString).tmp")
    }

    func verifyChecksum(for object: SyncObject, at url: URL) async throws -> Bool {
        guard let expected = object.sha256 else {
            return true
        }
        let cacheDirectoryURL = recordingFileStore.libraryRootURL
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("CanonicalChecksumCache", isDirectory: true)
            .standardizedFileURL
        var configuration = CanonicalInventoryRuntimeConfiguration()
        configuration.persistentChecksumCacheEnabled = false
        let result = await checksumRuntime.checksum(
            fileURL: url,
            logicalToken: object.logicalPathToken,
            nodeRole: .mac,
            cacheDirectoryURL: cacheDirectoryURL,
            configuration: configuration
        )
        return result.sha256 == expected
    }

    func atomicApply(tempURL: URL, for object: SyncObject) throws {
        guard let token = object.logicalPathToken else {
            throw StudyLibraryStoreError.writeFailed("sync_object_missing_logical_path")
        }
        let destinationURL = try resolveLogicalPathToken(token, for: object)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: destinationURL)
        }
    }

    func markTransferState(_ state: SyncTransferState, for object: SyncObject) throws {
        guard let item = studyLibraryStore.item(recordingID: object.ownerID) ?? studyLibraryStore.item(itemID: object.ownerID),
              let localState = LocalNetworkTransferState(rawValue: state.rawValue) else {
            return
        }
        let progress = LocalNetworkTransferProgress(
            objectID: object.ownerID,
            objectKind: object.objectKind,
            state: localState,
            progressFraction: object.transferProgress,
            receivedBytes: nil,
            totalBytes: object.size,
            sourceDeviceID: object.sourceDeviceID,
            statusText: nil
        )
        try studyLibraryStore.save(item.withLocalNetworkTransferProgress(progress))
    }

    func markConflict(_ status: String, for object: SyncObject) throws {
        guard var item = studyLibraryStore.item(recordingID: object.ownerID) ?? studyLibraryStore.item(itemID: object.ownerID) else {
            return
        }
        item.syncConflictStatus = status
        try studyLibraryStore.save(item)
    }

    private func localNetworkFolder(_ folder: StudyFolderMetadata) -> LocalNetworkSyncFolderEntry {
        LocalNetworkSyncFolderEntry(
            folderID: folder.folderID,
            parentID: folder.parentFolderID,
            path: folder.path.displaySummary,
            name: folder.name,
            colorToken: folder.colorToken?.rawValue,
            updatedAt: folder.updatedAt,
            revisionHash: folder.localNetworkFolderBusinessSignatureV2,
            deleted: folder.isTrashed
        )
    }

    private func localNetworkStudyItem(_ item: StudyItemMetadata) -> LocalNetworkSyncStudyItemEntry {
        LocalNetworkSyncStudyItemEntry(
            itemID: item.itemID,
            kind: item.kind,
            title: item.title,
            folderIDs: item.folderIDs,
            recordingID: item.recordingID,
            updatedAt: item.updatedAt,
            revisionHash: item.localNetworkStudyItemBusinessSignatureV2,
            deleted: item.isTrashed,
            path: item.filing.displaySummary,
            conflictStatus: item.syncConflictStatus
        )
    }

    private func makeArtifacts(from manifest: StudyLibrarySyncManifest) -> [LocalNetworkSyncArtifactEntry] {
        var artifacts: [LocalNetworkSyncArtifactEntry] = []
        for item in manifest.items {
            let ownerID = item.recordingID ?? item.itemID
            appendArtifact(relativePath: item.receiveRelativePath, kind: .receiveJSON, ownerID: ownerID, artifacts: &artifacts)
            appendArtifact(relativePath: item.transcriptMarkdownRelativePath, kind: .transcriptMarkdown, ownerID: ownerID, artifacts: &artifacts)
            appendArtifact(relativePath: item.transcriptRelativePath, kind: .transcriptJSON, ownerID: ownerID, artifacts: &artifacts)
            appendArtifact(relativePath: item.noteRelativePath, kind: item.noteRelativePath?.hasSuffix(".json") == true ? .noteJSON : .noteMarkdown, ownerID: ownerID, artifacts: &artifacts)
            appendArtifact(relativePath: item.audioRelativePath, kind: .audio, ownerID: ownerID, includeChecksum: false, artifacts: &artifacts)
        }
        return artifacts
    }

    private func appendArtifact(
        relativePath: String?,
        kind: LocalNetworkSyncArtifactKind,
        ownerID: String,
        includeChecksum: Bool = true,
        artifacts: inout [LocalNetworkSyncArtifactEntry]
    ) {
        let fileURL: URL?
        if kind == .audio {
            fileURL = try? LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: recordingFileStore.libraryRootURL, logicalPathToken: relativePath ?? "")
        } else {
            fileURL = try? LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: recordingFileStore.libraryRootURL, logicalPathToken: relativePath ?? "", kind: kind)
        }
        guard let relativePath,
              !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = fileURL,
              fileManager.fileExists(atPath: url.path),
              let metadata = LocalNetworkSyncArtifactFileService.metadata(for: url) else {
            return
        }

        artifacts.append(
            LocalNetworkSyncArtifactEntry(
                artifactID: LocalNetworkSyncArtifactID.make(kind: kind, ownerID: ownerID, logicalPathToken: relativePath),
                kind: kind,
                ownerID: ownerID,
                checksum: nil,
                size: metadata.size,
                updatedAt: metadata.updatedAt,
                availability: .local,
                logicalPathToken: relativePath,
                localAvailability: .local,
                peerAvailability: nil,
                autoDownloadAllowed: kind.isAutoDownloadAllowed
            )
        )
    }

    private func artifactKind(for object: SyncObject) -> LocalNetworkSyncArtifactKind? {
        guard let kind = LocalNetworkSyncObjectKind(rawValue: object.objectKind) else {
            return nil
        }
        switch kind {
        case .recordingMetadata:
            return .metadataJSON
        case .receiveRecord:
            return .receiveJSON
        case .transcriptMarkdown:
            return .transcriptMarkdown
        case .transcriptJSON:
            return .transcriptJSON
        case .noteMarkdown:
            return .noteMarkdown
        case .noteJSON:
            return .noteJSON
        case .summaryMarkdown:
            return .summaryMarkdown
        case .summaryJSON:
            return .summaryJSON
        case .recordingAudio:
            return .audio
        case .studyItem, .studyFolder:
            return nil
        }
    }
}

private extension String {
    var safeSyncFileComponent: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return value.isEmpty ? "sync-object" : value
    }
}
