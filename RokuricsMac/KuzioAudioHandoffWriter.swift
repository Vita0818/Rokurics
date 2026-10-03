import Darwin
import Foundation
import KuzioLibraryAPI
import UniformTypeIdentifiers

enum KuzioAudioHandoffError: Error, Equatable, Sendable {
    case appGroupUnavailable
    case invalidRoot
    case invalidDisplayFileName
    case unsupportedAudioFile
    case sourceUnavailable
    case destinationConflict
    case writeFailed
    case publishFailed
}

extension KuzioAudioHandoffError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            RokuricsCopy.text(
                "Kuzio 共享投递箱不可用，请确认两个 App 使用同一个 App Group 签名。",
                "The Kuzio handoff folder is unavailable. Confirm that both apps use the same App Group signing entitlement."
            )
        case .invalidRoot:
            RokuricsCopy.text(
                "Kuzio 共享投递箱目录无效。",
                "The Kuzio handoff folder is invalid."
            )
        case .invalidDisplayFileName:
            RokuricsCopy.text(
                "录音文件名无效。",
                "The recording file name is invalid."
            )
        case .unsupportedAudioFile:
            RokuricsCopy.text(
                "只能把受支持的音频文件交给 Kuzio。",
                "Only a supported audio file can be handed to Kuzio."
            )
        case .sourceUnavailable:
            RokuricsCopy.text(
                "录音临时文件不可读取，请重试。",
                "The temporary recording cannot be read. Please retry."
            )
        case .destinationConflict:
            RokuricsCopy.text(
                "Kuzio 投递任务标识发生冲突，请重试。",
                "The Kuzio handoff request conflicts with an existing item. Please retry."
            )
        case .writeFailed:
            RokuricsCopy.text(
                "无法完整写入 Kuzio 投递箱，请重试。",
                "The recording could not be written completely to the Kuzio handoff folder. Please retry."
            )
        case .publishFailed:
            RokuricsCopy.text(
                "无法将录音发布到 Kuzio 队列，请重试。",
                "The recording could not be published to the Kuzio queue. Please retry."
            )
        }
    }
}

struct KuzioAudioHandoffReceipt: Equatable, Sendable {
    let requestID: UUID
    let displayFileName: String
}

/// The Mac-only producer for Kuzio's official App Group handoff contract.
/// It owns no library state: one complete source file becomes one hidden queue
/// file, then one same-directory ready rename. Kuzio owns all later import work.
actor KuzioAudioHandoffWriter {
    typealias RootURLResolver = @Sendable () -> URL?
    typealias PublicationObserver = @Sendable (_ temporaryURL: URL, _ readyURL: URL) throws -> Void

    private static let copyChunkBytes = 1 * 1_024 * 1_024

    private let fileManager: FileManager
    private let rootURLResolver: RootURLResolver
    private let publicationObserver: PublicationObserver?

    init(fileManager: FileManager = FileManager()) {
        self.fileManager = fileManager
        self.rootURLResolver = {
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    KuzioLibraryFileHandoffContract.appGroupIdentifier
            )?.appendingPathComponent(
                KuzioLibraryFileHandoffContract.rootDirectoryName,
                isDirectory: true
            )
        }
        self.publicationObserver = nil
    }

    /// Test-only construction keeps production path resolution inside the
    /// official App Group API while allowing deterministic filesystem tests.
    init(
        rootURL: URL,
        fileManager: FileManager = FileManager(),
        publicationObserver: PublicationObserver? = nil
    ) {
        self.fileManager = fileManager
        self.rootURLResolver = { rootURL }
        self.publicationObserver = publicationObserver
    }

    /// Test-only construction for the explicit unavailable-container case.
    init(
        rootURLResolver: @escaping RootURLResolver,
        fileManager: FileManager = FileManager()
    ) {
        self.fileManager = fileManager
        self.rootURLResolver = rootURLResolver
        self.publicationObserver = nil
    }

    func handoffAudio(
        at sourceURL: URL,
        displayFileName: String,
        requestID: UUID = UUID()
    ) throws -> KuzioAudioHandoffReceipt {
        guard let temporaryFileName = KuzioLibraryFileHandoffContract.temporaryFileName(
            requestID: requestID,
            displayFileName: displayFileName
        ), let readyFileName = KuzioLibraryFileHandoffContract.readyFileName(
            requestID: requestID,
            displayFileName: displayFileName
        ) else {
            throw KuzioAudioHandoffError.invalidDisplayFileName
        }

        let fileExtension = URL(fileURLWithPath: displayFileName).pathExtension
        guard let contentType = UTType(filenameExtension: fileExtension),
              contentType.conforms(to: .audio) else {
            throw KuzioAudioHandoffError.unsupportedAudioFile
        }

        guard let resolvedRootURL = rootURLResolver() else {
            throw KuzioAudioHandoffError.appGroupUnavailable
        }
        let rootURL = resolvedRootURL.standardizedFileURL
        let incomingURL = rootURL.appendingPathComponent(
            KuzioLibraryFileHandoffContract.incomingDirectoryName,
            isDirectory: true
        ).standardizedFileURL
        try ensureDirectory(rootURL, parent: rootURL.deletingLastPathComponent())
        try ensureDirectory(incomingURL, parent: rootURL)

        let temporaryURL = incomingURL.appendingPathComponent(
            temporaryFileName,
            isDirectory: false
        ).standardizedFileURL
        let readyURL = incomingURL.appendingPathComponent(
            readyFileName,
            isDirectory: false
        ).standardizedFileURL
        guard isDirectChild(temporaryURL, of: incomingURL),
              isDirectChild(readyURL, of: incomingURL) else {
            throw KuzioAudioHandoffError.invalidRoot
        }
        guard !fileManager.fileExists(atPath: temporaryURL.path),
              !fileManager.fileExists(atPath: readyURL.path) else {
            throw KuzioAudioHandoffError.destinationConflict
        }

        let sourceDescriptor = Darwin.open(
            sourceURL.standardizedFileURL.path,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard sourceDescriptor >= 0 else {
            throw KuzioAudioHandoffError.sourceUnavailable
        }
        let sourceFile = FileHandle(fileDescriptor: sourceDescriptor, closeOnDealloc: true)
        defer { try? sourceFile.close() }

        var sourceInformation = stat()
        guard fstat(sourceDescriptor, &sourceInformation) == 0,
              (sourceInformation.st_mode & S_IFMT) == S_IFREG,
              sourceInformation.st_nlink == 1,
              sourceInformation.st_size >= 0 else {
            throw KuzioAudioHandoffError.sourceUnavailable
        }
        let expectedByteCount = UInt64(sourceInformation.st_size)

        let targetDescriptor = Darwin.open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard targetDescriptor >= 0 else {
            if errno == EEXIST {
                throw KuzioAudioHandoffError.destinationConflict
            }
            throw KuzioAudioHandoffError.writeFailed
        }

        var targetFile: FileHandle? = FileHandle(
            fileDescriptor: targetDescriptor,
            closeOnDealloc: true
        )
        defer {
            try? targetFile?.close()
        }

        do {
            guard let openedTargetFile = targetFile else {
                throw KuzioAudioHandoffError.writeFailed
            }
            var copiedByteCount: UInt64 = 0
            while let chunk = try sourceFile.read(upToCount: Self.copyChunkBytes),
                  !chunk.isEmpty {
                try openedTargetFile.write(contentsOf: chunk)
                copiedByteCount += UInt64(chunk.count)
            }
            guard copiedByteCount == expectedByteCount else {
                throw KuzioAudioHandoffError.writeFailed
            }
            try openedTargetFile.synchronize()
            try openedTargetFile.close()
            targetFile = nil
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporaryURL.path
            )
            try publicationObserver?(temporaryURL, readyURL)
        } catch let error as KuzioAudioHandoffError {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw KuzioAudioHandoffError.writeFailed
        }

        let renameResult = temporaryURL.path.withCString { temporaryPath in
            readyURL.path.withCString { readyPath in
                Darwin.renamex_np(
                    temporaryPath,
                    readyPath,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard renameResult == 0 else {
            let renameError = errno
            try? fileManager.removeItem(at: temporaryURL)
            if renameError == EEXIST {
                throw KuzioAudioHandoffError.destinationConflict
            }
            throw KuzioAudioHandoffError.publishFailed
        }

        return KuzioAudioHandoffReceipt(
            requestID: requestID,
            displayFileName: displayFileName
        )
    }

    private func ensureDirectory(_ url: URL, parent: URL) throws {
        guard url.deletingLastPathComponent().standardizedFileURL
            == parent.standardizedFileURL else {
            throw KuzioAudioHandoffError.invalidRoot
        }
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(
                    at: url,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw KuzioAudioHandoffError.invalidRoot
            }
        }
        do {
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ])
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  values.isAliasFile != true else {
                throw KuzioAudioHandoffError.invalidRoot
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.path
            )
        } catch let error as KuzioAudioHandoffError {
            throw error
        } catch {
            throw KuzioAudioHandoffError.invalidRoot
        }
    }

    private func isDirectChild(_ url: URL, of directoryURL: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL
            == directoryURL.standardizedFileURL
    }
}
