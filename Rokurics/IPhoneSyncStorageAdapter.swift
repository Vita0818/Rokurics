//
//  IPhoneSyncStorageAdapter.swift
//  Rokurics
//
//  Created by Codex on 2026/5/30.
//

import Foundation

@MainActor
struct IPhoneSyncStorageAdapter: SyncStorageAdapter {
    let audioFileStore: AudioFileStore
    let studyLibraryStore: StudyLibraryStore
    let uploadJobStore: RecordingUploadJobStore
    let fileManager: FileManager
    let checksumRuntime: CanonicalChecksumRuntime

    init(
        audioFileStore: AudioFileStore,
        studyLibraryStore: StudyLibraryStore,
        uploadJobStore: RecordingUploadJobStore? = nil,
        fileManager: FileManager = .default,
        checksumRuntime: CanonicalChecksumRuntime = CanonicalChecksumRuntime()
    ) {
        self.audioFileStore = audioFileStore
        self.studyLibraryStore = studyLibraryStore
        self.uploadJobStore = uploadJobStore ?? RecordingUploadJobStore(audioFileStore: audioFileStore)
        self.fileManager = fileManager
        self.checksumRuntime = checksumRuntime
    }

    func buildDirectorySnapshot() throws -> [SyncDirectory] {
        studyLibraryStore
            .makeSyncManifest(deviceID: "iphone-local")
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
                    revisionHash: LocalNetworkSyncMetadataHash.hash(folder)
                )
            }
    }

    func buildObjectSnapshot() throws -> [SyncObject] {
        LocalNetworkSyncInventoryBuilder(
            audioFileStore: audioFileStore,
            studyLibraryStore: studyLibraryStore,
            uploadJobStore: uploadJobStore
        )
        .build(deviceID: "iphone-local", deviceName: "iPhone", lastKnownPeerRevision: nil)
        .syncCoreInventory
        .objects
    }

    func resolveLogicalPathToken(_ token: String, for object: SyncObject) throws -> URL {
        let rootURL = try audioFileStore.baseDirectory()
        if let kind = artifactKind(for: object), kind != .audio {
            return try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: token, kind: kind)
        }
        return try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: token)
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
        let rootURL = try audioFileStore.baseDirectory()
        let tempDirectory = rootURL
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("Incoming", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return tempDirectory.appendingPathComponent("\(object.objectID.safeSyncFileComponent)-\(UUID().uuidString).tmp")
    }

    func verifyChecksum(for object: SyncObject, at url: URL) async throws -> Bool {
        guard let expected = object.sha256 else {
            return true
        }
        let cacheDirectoryURL = try audioFileStore.baseDirectory()
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("CanonicalChecksumCache", isDirectory: true)
            .standardizedFileURL
        var configuration = CanonicalInventoryRuntimeConfiguration()
        configuration.persistentChecksumCacheEnabled = false
        let result = await checksumRuntime.checksum(
            fileURL: url,
            logicalToken: object.logicalPathToken,
            nodeRole: .iPhone,
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
