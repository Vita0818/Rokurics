//
//  GitBackedStudyMetadataStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/21.
//

import Foundation

enum GitBackedStudyMetadataStoreError: LocalizedError, Equatable {
    case repositoryUnavailable(String)
    case gitFailed(String)
    case unsafePath

    var errorDescription: String? {
        switch self {
        case .repositoryUnavailable(let reason):
            return reason
        case .gitFailed(let reason):
            return reason
        case .unsafePath:
            return "unsafe_study_sync_path"
        }
    }
}

struct GitBackedStudyCommitResult: Equatable {
    let commitID: String?
    let didCreateCommit: Bool
    let trackedFiles: [String]
}

struct GitBackedStudyGitInvocation: Equatable {
    let arguments: [String]
    let environment: [String: String]
}

struct GitBackedStudySyncState: Codable, Equatable {
    var currentCommitID: String?
    var lastAppliedDeviceID: String?
    var lastAppliedManifestHash: String?
    var lastSyncAt: Date?
    var conflictCount: Int
    var pendingUploadCount: Int
    var lastError: String?
    var gitCommitSuppressedUntil: Date?
}

final class GitBackedStudyMetadataStore {
    let rootURL: URL
    let repoURL: URL
    let stateURL: URL

    private let fileManager: FileManager
    private let gitExecutableURL: URL
    private let gitCommandInterceptor: (([String]) throws -> String?)?
    private(set) var gitInvocations: [GitBackedStudyGitInvocation] = []
    private var gitCommitFuseUntil: Date?
    private let signingFailureRetryDelay: TimeInterval = 24 * 60 * 60

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        gitExecutableURL: URL? = nil,
        gitCommandInterceptor: (([String]) throws -> String?)? = nil
    ) {
        self.fileManager = fileManager
        self.gitExecutableURL = gitExecutableURL ?? Self.defaultGitExecutableURL(fileManager: fileManager)
        self.gitCommandInterceptor = gitCommandInterceptor

        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            self.rootURL = MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
                .appendingPathComponent("study-sync", isDirectory: true)
                .standardizedFileURL
        }

        repoURL = self.rootURL
            .appendingPathComponent("repo", isDirectory: true)
            .standardizedFileURL
        stateURL = self.rootURL
            .appendingPathComponent("state", isDirectory: true)
            .standardizedFileURL
    }

    var studyURL: URL {
        repoURL.appendingPathComponent("study", isDirectory: true)
    }

    var itemsURL: URL {
        studyURL.appendingPathComponent("items", isDirectory: true)
    }

    var foldersURL: URL {
        studyURL.appendingPathComponent("folders", isDirectory: true)
    }

    var tombstonesURL: URL {
        studyURL.appendingPathComponent("tombstones", isDirectory: true)
    }

    var manifestURL: URL {
        studyURL.appendingPathComponent("library_manifest.json", isDirectory: false)
    }

    var schemaVersionURL: URL {
        studyURL.appendingPathComponent("schema_version.json", isDirectory: false)
    }

    var pendingUploadsURL: URL {
        stateURL.appendingPathComponent("pending_uploads.json", isDirectory: false)
    }

    var syncStateURL: URL {
        stateURL.appendingPathComponent("sync_state.json", isDirectory: false)
    }

    @discardableResult
    func commitManifest(
        _ manifest: StudyLibrarySyncManifest,
        deviceDisplayName: String,
        message: String? = nil
    ) throws -> GitBackedStudyCommitResult {
        if let fuseMessage = activeGitCommitFuseMessage() {
            try? writeStateFiles(manifest: manifest, currentCommitID: persistedSyncState()?.currentCommitID, error: fuseMessage)
            throw GitBackedStudyMetadataStoreError.gitFailed(fuseMessage)
        }

        try ensureRepository()
        try writeMetadataSnapshot(manifest)
        try writeStateFiles(manifest: manifest, currentCommitID: currentCommitID(), error: nil)

        let changed: Bool
        do {
            try runGit(["add", ".gitignore", "study"])
            changed = try !runGit(["status", "--porcelain", "--", ".gitignore", "study"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty

            if changed {
                let commitMessage = message ?? "sync study library from \(deviceDisplayName)"
                try runGit([
                    "-c", "commit.gpgsign=false",
                    "-c", "tag.gpgSign=false",
                    "-c", "gpg.format=openpgp",
                    "-c", "user.signingkey=",
                    "-c", "gpg.program=/usr/bin/false",
                    "-c", "gpg.ssh.program=/usr/bin/false",
                    "-c", "core.hooksPath=/dev/null",
                    "commit",
                    "--no-gpg-sign",
                    "--no-verify",
                    "-m", commitMessage
                ])
            }
        } catch {
            let errorMessage = error.localizedDescription
            if Self.isSigningOrPromptFailure(errorMessage) {
                gitCommitFuseUntil = Date().addingTimeInterval(signingFailureRetryDelay)
            }
            try? writeStateFiles(manifest: manifest, currentCommitID: currentCommitID(), error: errorMessage)
            throw error
        }

        let commitID = currentCommitID()
        gitCommitFuseUntil = nil
        try writeStateFiles(manifest: manifest, currentCommitID: commitID, error: nil)
        return GitBackedStudyCommitResult(
            commitID: commitID,
            didCreateCommit: changed,
            trackedFiles: try trackedFiles()
        )
    }

    func currentCommitID() -> String? {
        guard (try? runGit(["rev-parse", "--verify", "HEAD"])) != nil else {
            return nil
        }

        guard let output = try? runGit(["rev-parse", "--verify", "HEAD"]) else {
            return nil
        }
        return nilIfEmpty(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func trackedFiles() throws -> [String] {
        try runGit(["ls-files"])
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    func trackedFilesContainingForbiddenMetadataPayloads() throws -> [String] {
        try trackedFiles().filter { path in
            forbiddenTrackedPath(path)
        }
    }

    func ensureRepository() throws {
        try fileManager.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stateURL, withIntermediateDirectories: true)
        try ensureSafeDirectory(repoURL)
        if !fileManager.fileExists(atPath: repoURL.appendingPathComponent(".git", isDirectory: true).path) {
            try runGit(["init"])
        }
        try ensureLocalGitConfig()

        try writeGitIgnore()
        try ensureStudyDirectories()
    }

    func localGitConfigValue(_ key: String) throws -> String {
        try runGit(["config", "--local", "--get", key])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeMetadataSnapshot(_ manifest: StudyLibrarySyncManifest) throws {
        try ensureStudyDirectories()
        try removeJSONFiles(in: itemsURL)
        try removeJSONFiles(in: foldersURL)
        try removeJSONFiles(in: tombstonesURL)

        let items = manifest.items.map { $0.syncSanitized(modifiedByDeviceID: manifest.deviceID) }
        let folders = manifest.folders.map { $0.syncSanitized(modifiedByDeviceID: manifest.deviceID) }
        let sanitizedManifest = StudyLibrarySyncManifest.make(
            deviceID: manifest.deviceID,
            generatedAt: manifest.generatedAt,
            libraryVersion: manifest.libraryVersion,
            items: items,
            folders: folders,
            tombstones: manifest.tombstones,
            pendingUploads: manifest.pendingUploads
        )

        for item in items {
            try writeJSON(item, to: itemsURL.appendingPathComponent("\(safeFileComponent(item.itemID)).json", isDirectory: false))
        }

        for folder in folders {
            try writeJSON(folder, to: foldersURL.appendingPathComponent("\(safeFileComponent(folder.folderID)).json", isDirectory: false))
        }

        for tombstone in manifest.tombstones {
            try writeJSON(tombstone, to: tombstonesURL.appendingPathComponent("\(safeFileComponent(tombstone.id)).json", isDirectory: false))
        }

        try writeJSON(sanitizedManifest, to: manifestURL)
        try writeJSON(["schemaVersion": "1"], to: schemaVersionURL)
    }

    private func writeStateFiles(
        manifest: StudyLibrarySyncManifest,
        currentCommitID: String?,
        error: String?
    ) throws {
        try fileManager.createDirectory(at: stateURL, withIntermediateDirectories: true)
        try writeJSON(manifest.pendingUploads, to: pendingUploadsURL)
        try writeJSON(
            GitBackedStudySyncState(
                currentCommitID: currentCommitID,
                lastAppliedDeviceID: manifest.deviceID,
                lastAppliedManifestHash: manifest.checksum,
                lastSyncAt: Date(),
                conflictCount: manifest.items.filter { $0.syncConflictStatus != nil }.count
                    + manifest.folders.filter { $0.syncConflictStatus != nil }.count,
                pendingUploadCount: manifest.pendingUploads.filter { $0.status != .uploaded }.count,
                lastError: error,
                gitCommitSuppressedUntil: gitCommitFuseUntil
            ),
            to: syncStateURL
        )
    }

    private func writeGitIgnore() throws {
        let gitIgnoreURL = repoURL.appendingPathComponent(".gitignore", isDirectory: false)
        let content = """
        # Rokurics study metadata repo: keep heavyweight content and secrets out.
        *.m4a
        *.wav
        *.mp3
        *.caf
        **/audio*
        **/transcript.md
        **/transcript.json
        **/note.md
        **/section*.md
        **/*secret*
        **/*hmac*
        **/*api_key*
        **/*apikey*
        **/*pairing*

        """
        try content.write(to: gitIgnoreURL, atomically: true, encoding: .utf8)
    }

    private func ensureLocalGitConfig() throws {
        try unsetLocalGitConfigValues([
            "include.path",
            "user.signingkey",
            "gpg.program",
            "gpg.ssh.program",
            "gpg.ssh.defaultKeyCommand",
            "gpg.ssh.allowedSignersFile",
            "credential.helper"
        ])
        try runGit(["config", "--local", "commit.gpgsign", "false"])
        try runGit(["config", "--local", "tag.gpgSign", "false"])
        try runGit(["config", "--local", "gpg.format", "openpgp"])
        try runGit(["config", "--local", "gpg.program", "/usr/bin/false"])
        try runGit(["config", "--local", "gpg.ssh.program", "/usr/bin/false"])
        try runGit(["config", "--local", "credential.helper", ""])
        try runGit(["config", "--local", "user.name", "Rokurics Sync"])
        try runGit(["config", "--local", "user.email", "rokurics-sync@local"])
        try runGit(["config", "--local", "core.hooksPath", "/dev/null"])
    }

    private func unsetLocalGitConfigValues(_ keys: [String]) throws {
        for key in keys {
            _ = try? runGit(["config", "--local", "--unset-all", key])
        }
    }

    private func ensureStudyDirectories() throws {
        try fileManager.createDirectory(at: itemsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: foldersURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tombstonesURL, withIntermediateDirectories: true)
    }

    private func removeJSONFiles(in directoryURL: URL) throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        for url in try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) {
            guard url.pathExtension == "json", isInside(url, parent: directoryURL) else {
                continue
            }
            try fileManager.removeItem(at: url)
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        guard isInside(url, parent: rootURL) else {
            throw GitBackedStudyMetadataStoreError.unsafePath
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(value).write(to: url, options: .atomic)
    }

    @discardableResult
    private func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = gitExecutableURL
        process.currentDirectoryURL = repoURL
        process.arguments = arguments
        let environment = try gitProcessEnvironment()
        process.environment = environment
        gitInvocations.append(GitBackedStudyGitInvocation(arguments: arguments, environment: environment))

        if let interceptedOutput = try gitCommandInterceptor?(arguments) {
            return interceptedOutput
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw GitBackedStudyMetadataStoreError.repositoryUnavailable(error.localizedDescription)
        }

        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = nilIfEmpty(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitBackedStudyMetadataStoreError.gitFailed(message)
        }

        return output
    }

    private func gitProcessEnvironment() throws -> [String: String] {
        try fileManager.createDirectory(at: gitHomeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: gitXDGConfigURL, withIntermediateDirectories: true)
        try controlledGitConfigContent.write(to: gitGlobalConfigURL, atomically: true, encoding: .utf8)
        let xdgGitConfigDirectoryURL = gitXDGConfigURL.appendingPathComponent("git", isDirectory: true)
        try fileManager.createDirectory(at: xdgGitConfigDirectoryURL, withIntermediateDirectories: true)
        try controlledGitConfigContent.write(to: xdgGitConfigDirectoryURL.appendingPathComponent("config", isDirectory: false), atomically: true, encoding: .utf8)

        var environment: [String: String] = [
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_SYSTEM": "/dev/null",
            "GIT_CONFIG_GLOBAL": gitGlobalConfigURL.path,
            "GIT_ASKPASS": "/usr/bin/false",
            "SSH_ASKPASS": "/usr/bin/false",
            "GCM_INTERACTIVE": "never",
            "HOME": gitHomeURL.path,
            "XDG_CONFIG_HOME": gitXDGConfigURL.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin",
            "LANG": "C",
            "LC_ALL": "C"
        ]

        if let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] {
            environment["TMPDIR"] = tmpDir
        }

        environment["GIT_CONFIG_COUNT"] = "\(Self.protectedGitConfig.count)"
        for (index, pair) in Self.protectedGitConfig.enumerated() {
            environment["GIT_CONFIG_KEY_\(index)"] = pair.key
            environment["GIT_CONFIG_VALUE_\(index)"] = pair.value
        }
        return environment
    }

    private var gitHomeURL: URL {
        stateURL
            .appendingPathComponent("git-home", isDirectory: true)
            .standardizedFileURL
    }

    private var gitGlobalConfigURL: URL {
        gitHomeURL
            .appendingPathComponent(".gitconfig", isDirectory: false)
            .standardizedFileURL
    }

    private var gitXDGConfigURL: URL {
        gitHomeURL
            .appendingPathComponent("xdg-config", isDirectory: true)
            .standardizedFileURL
    }

    private func activeGitCommitFuseMessage() -> String? {
        let persistedFuseUntil = persistedSyncState()?.gitCommitSuppressedUntil
        let activeFuseUntil = [gitCommitFuseUntil, persistedFuseUntil]
            .compactMap { $0 }
            .max()
        guard let activeFuseUntil, activeFuseUntil > Date() else {
            return nil
        }

        gitCommitFuseUntil = activeFuseUntil
        return "git_metadata_commit_temporarily_suppressed_until \(Self.fuseDateFormatter.string(from: activeFuseUntil))"
    }

    private func persistedSyncState() -> GitBackedStudySyncState? {
        guard fileManager.fileExists(atPath: syncStateURL.path),
              let data = try? Data(contentsOf: syncStateURL) else {
            return nil
        }

        return try? Self.decoder.decode(GitBackedStudySyncState.self, from: data)
    }

    private static func isSigningOrPromptFailure(_ message: String) -> Bool {
        let lowercasedMessage = message.lowercased()
        return lowercasedMessage.contains("signing")
            || lowercasedMessage.contains("gpg")
            || lowercasedMessage.contains("ssh signing")
            || lowercasedMessage.contains("keychain")
            || lowercasedMessage.contains("permission denied")
            || lowercasedMessage.contains("user interaction")
            || lowercasedMessage.contains("terminal prompts disabled")
    }

    private func safeFileComponent(_ rawValue: String) -> String {
        nilIfEmpty(StudyPathSanitizer.sanitizedPathComponent(rawValue)) ?? "metadata"
    }

    private func nilIfEmpty(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private static func defaultGitExecutableURL(fileManager: FileManager) -> URL {
        let candidatePaths = [
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git"
        ]

        for path in candidatePaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return URL(fileURLWithPath: "/usr/bin/git")
    }

    private func forbiddenTrackedPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".m4a")
            || lower.hasSuffix(".wav")
            || lower.hasSuffix(".mp3")
            || lower.hasSuffix(".caf")
            || lower.contains("sharedsecret")
            || lower.contains("shared_secret")
            || lower.contains("hmac")
            || lower.contains("apikey")
            || lower.contains("api_key")
            || lower.contains("pairing")
            || lower.hasSuffix("transcript.md")
            || lower.hasSuffix("transcript.json")
            || lower.hasSuffix("note.md")
    }

    private func ensureSafeDirectory(_ url: URL) throws {
        guard isInside(url, parent: rootURL) else {
            throw GitBackedStudyMetadataStoreError.unsafePath
        }
    }

    private func isInside(_ url: URL, parent: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        return urlPath == parentPath || urlPath.hasPrefix(parentPath + "/")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        SyncTimestampPolicy.configure(encoder)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        SyncTimestampPolicy.configure(decoder)
        return decoder
    }()

    private static let protectedGitConfig: [(key: String, value: String)] = [
        ("commit.gpgsign", "false"),
        ("tag.gpgSign", "false"),
        ("gpg.format", "openpgp"),
        ("user.signingkey", ""),
        ("gpg.program", "/usr/bin/false"),
        ("gpg.ssh.program", "/usr/bin/false"),
        ("core.hooksPath", "/dev/null"),
        ("credential.helper", "")
    ]

    private var controlledGitConfigContent: String {
        """
        [user]
            name = Rokurics Sync
            email = rokurics-sync@local
        [commit]
            gpgsign = false
        [tag]
            gpgSign = false
        [gpg]
            format = openpgp
            program = /usr/bin/false
        [gpg "ssh"]
            program = /usr/bin/false
        [core]
            hooksPath = /dev/null
        [credential]
            helper =

        """
    }

    private static let fuseDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
