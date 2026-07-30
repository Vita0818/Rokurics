import Foundation

/// Executes Mac -> iPhone content transfer independently from sync discovery.
/// The only input is a durable offer created by the Mac Upload button.
@MainActor
final class MacToIPhoneUploadReceiver {
    private let audioFileStore: AudioFileStore
    private let recordingManager: RecordingManager
    private let reconciliationStore: SyncReconciliationStore
    private var activeTransferIDs: Set<String> = []
    private let chunkSize = 2 * 1024 * 1024

    init(
        audioFileStore: AudioFileStore,
        recordingManager: RecordingManager,
        reconciliationStore: SyncReconciliationStore? = nil
    ) {
        self.audioFileStore = audioFileStore
        self.recordingManager = recordingManager
        self.reconciliationStore = reconciliationStore
            ?? SyncReconciliationStore(rootURL: try? audioFileStore.baseDirectory())
    }

    func receive(
        offer: MacToIPhoneUploadOffer,
        settings: SecureMacConnectionSnapshot,
        client: any LocalNetworkHeartbeatClientProtocol
    ) async {
        guard offer.targetDeviceID == settings.deviceID,
              offer.size > 0,
              !offer.checksum.isEmpty,
              activeTransferIDs.insert(offer.transferID).inserted else {
            return
        }
        defer { activeTransferIDs.remove(offer.transferID) }

        do {
            guard let recordID = offer.reconciliationRecordID,
                  let record = reconciliationStore.pendingTargetRecord(
                    objectID: "recordingAudio:\(offer.recordingID)",
                    targetDeviceID: settings.deviceID,
                    sourceDeviceID: offer.sourceDeviceID
                  ),
                  record.recordID == recordID,
                  record.sourceSHA256?.lowercased() == offer.checksum.lowercased(),
                  record.sourceSize == offer.size,
                  record.targetSHA256?.lowercased() == offer.expectedTargetSHA256?.lowercased(),
                  record.targetSize == offer.expectedTargetSize else {
                throw SecureMacUploadError.serverRejected("sync_transfer_mark_mismatch")
            }
            try reconciliationStore.update(recordID: recordID, status: .transferring, transferID: offer.transferID)
            let transferDirectory = try audioFileStore.baseDirectory()
                .appendingPathComponent("Transfers/MacToIPhone", isDirectory: true)
            try FileManager.default.createDirectory(at: transferDirectory, withIntermediateDirectories: true)
            let temporaryURL = transferDirectory
                .appendingPathComponent(offer.transferID, isDirectory: false)
                .appendingPathExtension("part")
            if !FileManager.default.fileExists(atPath: temporaryURL.path) {
                FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
            var offset = min((attributes[.size] as? NSNumber)?.int64Value ?? 0, offer.size)
            if offset == offer.size,
               try SecureUploadUtilities.sha256Hex(fileURL: temporaryURL) != offer.checksum.lowercased() {
                try Data().write(to: temporaryURL, options: .atomic)
                offset = 0
            }

            let handle = try FileHandle(forWritingTo: temporaryURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            while offset < offer.size {
                let response = try await client.pullMacToIPhoneUploadChunk(
                    settings: settings,
                    request: MacToIPhoneUploadChunkRequest(
                        transferID: offer.transferID,
                        deviceID: settings.deviceID,
                        offset: offset,
                        length: min(chunkSize, Int(offer.size - offset))
                    )
                )
                guard response.ok,
                      response.transferID == offer.transferID,
                      response.offset == offset,
                      response.totalSize == offer.size,
                      let base64 = response.dataBase64,
                      let data = Data(base64Encoded: base64),
                      !data.isEmpty,
                      SecureUploadUtilities.sha256Hex(data) == response.chunkChecksum else {
                    throw SecureMacUploadError.invalidResponse
                }
                try handle.write(contentsOf: data)
                offset += Int64(data.count)
            }
            try handle.synchronize()

            guard offset == offer.size,
                  try SecureUploadUtilities.sha256Hex(fileURL: temporaryURL) == offer.checksum.lowercased() else {
                throw SecureMacUploadError.serverRejected("mac_to_iphone_upload_checksum_mismatch")
            }

            try install(offer: offer, temporaryURL: temporaryURL)
            let ack = try await client.acknowledgeMacToIPhoneUpload(
                settings: settings,
                request: MacToIPhoneUploadAckRequest(
                    transferID: offer.transferID,
                    deviceID: settings.deviceID,
                    checksum: offer.checksum,
                    size: offer.size,
                    completedAt: Date()
                )
            )
            guard ack.ok else {
                throw SecureMacUploadError.serverRejected(ack.error ?? "mac_to_iphone_upload_ack_failed")
            }
            try reconciliationStore.update(
                recordID: recordID,
                status: .transferredAwaitingVerification,
                transferID: offer.transferID,
                proof: SyncReconciliationCompletionProof(
                    transferID: offer.transferID,
                    verifiedSHA256: offer.checksum,
                    verifiedSize: offer.size,
                    verifiedAt: Date()
                )
            )
            try? FileManager.default.removeItem(at: temporaryURL)
            recordingManager.reloadRecordings()
        } catch {
            ConnectionDiagnosticsStore.shared.record(
                phase: "macToIPhoneUploadFailed",
                deviceID: settings.deviceID,
                result: String(offer.transferID.prefix(12)),
                errorCode: "mac_to_iphone_upload_failed",
                errorMessage: error.localizedDescription
            )
        }
    }

    private func install(offer: MacToIPhoneUploadOffer, temporaryURL: URL) throws {
        let existing = try? audioFileStore.loadMetadata(id: offer.recordingID)
        if let existing,
           let existingURL = try? audioFileStore.audioURL(for: existing),
           (try? SecureUploadUtilities.sha256Hex(fileURL: existingURL)) == offer.checksum.lowercased() {
            return
        }

        let safeID = offer.recordingID.replacingOccurrences(of: "/", with: "-")
        let destinationURL: URL
        var backupURL: URL?
        if let existing, let existingURL = try? audioFileStore.audioURL(for: existing) {
            let currentSize = (try? audioFileStore.fileSize(at: existingURL))
            let currentHash = try? SecureUploadUtilities.sha256Hex(fileURL: existingURL)
            let currentBusinessModifiedAt = recordingManager.studyLibraryStore.item(recordingID: existing.id)?.updatedAt
            let modifiedAtMatches = offer.targetModifiedAt.map { expected in
                guard let currentBusinessModifiedAt else { return false }
                return SyncTimestampPolicy.matches(expected, currentBusinessModifiedAt)
            } ?? true
            guard currentHash?.lowercased() == offer.expectedTargetSHA256?.lowercased(),
                  currentSize == offer.expectedTargetSize,
                  modifiedAtMatches else {
                throw SecureMacUploadError.serverRejected("sync_target_version_stale")
            }
            destinationURL = existingURL
            let backup = existingURL.deletingLastPathComponent()
                .appendingPathComponent(".\(offer.transferID).backup", isDirectory: false)
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: existingURL, to: backup)
            backupURL = backup
            let incomingURL = existingURL.deletingLastPathComponent()
                .appendingPathComponent(".\(offer.transferID).incoming", isDirectory: false)
            try? FileManager.default.removeItem(at: incomingURL)
            try FileManager.default.copyItem(at: temporaryURL, to: incomingURL)
            _ = try FileManager.default.replaceItemAt(existingURL, withItemAt: incomingURL)
        } else {
            guard offer.expectedTargetSHA256 == nil, offer.expectedTargetSize == nil else {
                throw SecureMacUploadError.serverRejected("sync_target_version_stale")
            }
            destinationURL = try audioFileStore.recordingsDirectory()
                .appendingPathComponent(safeID, isDirectory: false)
                .appendingPathExtension((offer.fileName as NSString).pathExtension.isEmpty ? "m4a" : (offer.fileName as NSString).pathExtension)
            guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
                throw SecureMacUploadError.serverRejected("mac_to_iphone_upload_destination_exists")
            }
            try FileManager.default.copyItem(at: temporaryURL, to: destinationURL)
        }
        let metadataURL = try audioFileStore.makeMetadataURL(id: safeID)
        let metadata = RecordingMetadata(
            id: safeID,
            title: offer.title,
            fileName: destinationURL.lastPathComponent,
            relativeAudioPath: try audioFileStore.relativePath(for: destinationURL),
            relativeMetadataPath: try audioFileStore.relativePath(for: metadataURL),
            createdAt: offer.createdAt,
            endedAt: offer.createdAt.addingTimeInterval(offer.duration),
            duration: offer.duration,
            format: existing?.format ?? destinationURL.pathExtension.lowercased(),
            codec: existing?.codec ?? "unknown",
            sampleRate: existing?.sampleRate ?? 0,
            channels: existing?.channels ?? 0,
            bitrate: existing?.bitrate ?? 0,
            fileSize: offer.size,
            uploadStatus: RecordingUploadStatus.localOnly.rawValue,
            transcriptionStatus: existing?.transcriptionStatus ?? "notStarted",
            noteStatus: existing?.noteStatus ?? "notStarted",
            tags: existing?.tags ?? [],
            studyFiling: existing?.studyFiling
        )
        do {
            try audioFileStore.saveMetadata(metadata)
            if let backupURL { try? FileManager.default.removeItem(at: backupURL) }
        } catch {
            if let backupURL {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    _ = try? FileManager.default.replaceItemAt(destinationURL, withItemAt: backupURL)
                } else {
                    try? FileManager.default.moveItem(at: backupURL, to: destinationURL)
                }
            } else {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            throw error
        }
    }
}
