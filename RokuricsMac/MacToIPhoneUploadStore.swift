import Foundation

enum MacToIPhoneUploadStoreError: LocalizedError {
    case invalidOffer
    case sourceMissing
    case targetMismatch
    case invalidRange
    case proofMismatch

    var errorDescription: String? {
        switch self {
        case .invalidOffer: return "mac_to_iphone_upload_invalid_offer"
        case .sourceMissing: return "mac_to_iphone_upload_source_missing"
        case .targetMismatch: return "mac_to_iphone_upload_target_mismatch"
        case .invalidRange: return "mac_to_iphone_upload_invalid_range"
        case .proofMismatch: return "mac_to_iphone_upload_proof_mismatch"
        }
    }
}

/// Persistent upload-layer ledger. Jobs can only be created by the explicit
/// Mac learning-library Upload action; sync discovery never writes this store.
final class MacToIPhoneUploadStore: @unchecked Sendable {
    private struct Job: Codable {
        var offer: MacToIPhoneUploadOffer
        var sourceRelativePath: String
        var state: String
        var completedAt: Date?
        var lastError: String?
    }

    private let rootURL: URL
    private let ledgerURL: URL
    private let lock = NSLock()
    private var jobs: [Job]

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        let directory = self.rootURL.appendingPathComponent("Transfers/MacToIPhone", isDirectory: true)
        ledgerURL = directory.appendingPathComponent("jobs.json", isDirectory: false)
        if let data = try? Data(contentsOf: ledgerURL),
           let decoded = try? Self.decoder.decode([Job].self, from: data) {
            jobs = decoded
        } else {
            jobs = []
        }
    }

    @discardableResult
    func enqueue(
        recordingID: String,
        title: String,
        createdAt: Date,
        duration: TimeInterval,
        sourceURL: URL,
        sourceDeviceID: String = "mac-local",
        targetDeviceID: String,
        checksum: String,
        size: Int64,
        reconciliationRecord: SyncReconciliationRecord? = nil,
        now: Date = Date()
    ) throws -> MacToIPhoneUploadOffer {
        let source = sourceURL.standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard source.path.hasPrefix(rootPath), FileManager.default.fileExists(atPath: source.path),
              !targetDeviceID.isEmpty, size >= 0, !checksum.isEmpty else {
            throw MacToIPhoneUploadStoreError.invalidOffer
        }
        let relativePath = String(source.path.dropFirst(rootPath.count))
        let offer = MacToIPhoneUploadOffer(
            transferID: UUID().uuidString.lowercased(),
            sourceDeviceID: sourceDeviceID,
            targetDeviceID: targetDeviceID,
            recordingID: recordingID,
            title: title,
            createdAt: createdAt,
            duration: duration,
            fileName: source.lastPathComponent,
            checksum: checksum.lowercased(),
            size: size,
            requestedAt: now,
            reconciliationRecordID: reconciliationRecord?.recordID,
            expectedTargetSHA256: reconciliationRecord?.targetSHA256,
            expectedTargetSize: reconciliationRecord?.targetSize,
            sourceModifiedAt: reconciliationRecord?.sourceModifiedAt,
            targetModifiedAt: reconciliationRecord?.targetModifiedAt
        )
        try withLockedJobs { jobs in
            jobs.append(Job(offer: offer, sourceRelativePath: relativePath, state: "queued", completedAt: nil, lastError: nil))
        }
        return offer
    }

    func nextOffer(targetDeviceID: String) -> MacToIPhoneUploadOffer? {
        lock.withLock {
            jobs.first { $0.offer.targetDeviceID == targetDeviceID && $0.state != "completed" }?.offer
        }
    }

    func chunk(transferID: String, targetDeviceID: String, offset: Int64, length: Int) throws -> MacToIPhoneUploadChunkResponse {
        let job = try lock.withLock { () throws -> Job in
            guard let job = jobs.first(where: { $0.offer.transferID == transferID }) else {
                throw MacToIPhoneUploadStoreError.invalidOffer
            }
            guard job.offer.targetDeviceID == targetDeviceID else {
                throw MacToIPhoneUploadStoreError.targetMismatch
            }
            return job
        }
        let sourceURL = rootURL.appendingPathComponent(job.sourceRelativePath, isDirectory: false).standardizedFileURL
        guard sourceURL.path.hasPrefix(rootURL.path + "/"), FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MacToIPhoneUploadStoreError.sourceMissing
        }
        guard offset >= 0, offset < job.offer.size, length > 0, length <= 2 * 1024 * 1024 else {
            throw MacToIPhoneUploadStoreError.invalidRange
        }
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: min(length, Int(job.offer.size - offset))) ?? Data()
        guard !data.isEmpty else { throw MacToIPhoneUploadStoreError.invalidRange }
        return MacToIPhoneUploadChunkResponse(
            ok: true,
            transferID: transferID,
            offset: offset,
            totalSize: job.offer.size,
            chunkChecksum: MacSecurityUtilities.sha256Hex(data),
            dataBase64: data.base64EncodedString(),
            isFinalChunk: offset + Int64(data.count) == job.offer.size,
            error: nil
        )
    }

    @discardableResult
    func acknowledge(_ request: MacToIPhoneUploadAckRequest) throws -> MacToIPhoneUploadOffer {
        var acknowledgedOffer: MacToIPhoneUploadOffer?
        try withLockedJobs { jobs in
            guard let index = jobs.firstIndex(where: { $0.offer.transferID == request.transferID }) else {
                throw MacToIPhoneUploadStoreError.invalidOffer
            }
            let offer = jobs[index].offer
            guard offer.targetDeviceID == request.deviceID else { throw MacToIPhoneUploadStoreError.targetMismatch }
            guard offer.checksum == request.checksum.lowercased(), offer.size == request.size else {
                throw MacToIPhoneUploadStoreError.proofMismatch
            }
            jobs[index].state = "completed"
            jobs[index].completedAt = request.completedAt
            jobs[index].lastError = nil
            acknowledgedOffer = offer
        }
        guard let acknowledgedOffer else { throw MacToIPhoneUploadStoreError.invalidOffer }
        return acknowledgedOffer
    }

    private func withLockedJobs(_ mutate: (inout [Job]) throws -> Void) throws {
        try lock.withLock {
            try mutate(&jobs)
            try FileManager.default.createDirectory(at: ledgerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(jobs).write(to: ledgerURL, options: .atomic)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
