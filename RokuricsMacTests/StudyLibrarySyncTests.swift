//
//  StudyLibrarySyncTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/5/21.
//

import Foundation
import Darwin
import Testing
@testable import RokuricsMac

struct StudyLibrarySyncTests {
    @Test func gitBackedStudySyncRuntimeDefaultsToDisabled() {
        #expect(!StudyLibrarySyncRuntimeConfiguration.default.gitBackedSyncEnabled)
        #expect(!StudyLibrarySyncRuntimeConfiguration.disabled.gitBackedSyncEnabled)
        #expect(StudyLibrarySyncRuntimeConfiguration.disabledReason == "Git-backed study sync is disabled")
    }

    @MainActor
    @Test func disabledSyncEndpointsSkipGitAndPreservePendingState() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let gitSpyURL = try makeGitSpyShim(rootURL: rootURL)
        let gitSpyLogURL = rootURL.appendingPathComponent("git-spy-invocations.log", isDirectory: false)
        let gitStore = GitBackedStudyMetadataStore(
            rootURL: rootURL.appendingPathComponent("disabled-git-store", isDirectory: true),
            gitExecutableURL: gitSpyURL
        )
        let syncStateStore = StudyLibrarySyncStateStore(
            rootURL: rootURL.appendingPathComponent("disabled-sync-state", isDirectory: true)
        )
        syncStateStore.replace(StudyLibrarySyncState(
            deviceID: "device-disabled",
            pendingLocalChanges: 7,
            pendingUploads: 3,
            failedChanges: 2,
            lastError: "previous_failure"
        ))
        let server = makeSyncServer(
            rootURL: rootURL,
            gitStore: gitStore,
            syncStateStore: syncStateStore,
            runtimeConfiguration: .default
        )
        let device = makePairedDevice(id: "device-disabled")

        let statusResponse = server.syncStatusResponseForVerifiedDevice(device)
        let manifestResponse = try server.syncManifestResponseForVerifiedDevice(device)
        let applyResponse = try server.syncApplyResponseForVerifiedDevice(device, requestBody: Data("not json".utf8))

        #expect(statusResponse.ok)
        #expect(statusResponse.error == StudyLibrarySyncRuntimeConfiguration.disabledReason)
        #expect(statusResponse.status?.lastSyncStatus == StudyLibrarySyncRuntimeConfiguration.disabledStatusText)
        #expect(!manifestResponse.ok)
        #expect(manifestResponse.manifest == nil)
        #expect(manifestResponse.newCommitID == nil)
        #expect(manifestResponse.error == StudyLibrarySyncRuntimeConfiguration.disabledReason)
        #expect(!applyResponse.ok)
        #expect(applyResponse.manifest == nil)
        #expect(applyResponse.error == StudyLibrarySyncRuntimeConfiguration.disabledReason)
        #expect(gitStore.gitInvocations.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: gitSpyLogURL.path))
        #expect(syncStateStore.state.pendingLocalChanges == 7)
        #expect(syncStateStore.state.pendingUploads == 3)
        #expect(syncStateStore.state.failedChanges == 2)
        #expect(syncStateStore.state.lastError == "previous_failure")
    }

    @Test func gitBackedMetadataRepoInitializesInTemporaryDirectoryAndTracksOnlyStudyMetadata() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let gitStore = GitBackedStudyMetadataStore(rootURL: rootURL)
        let item = StudyItemMetadata(
            recordingID: "git-backed-recording",
            title: "Git backed metadata",
            createdAt: Date(timeIntervalSince1970: 1_000),
            duration: 12,
            audioRelativePath: "audio/inbox/1970-01-01/git-backed-recording/audio.m4a",
            transcriptRelativePath: "transcripts/1970-01-01/git-backed-recording/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/git-backed-recording/transcript.md",
            noteRelativePath: "notes/1970-01-01/git-backed-recording/note.md",
            studyFiling: StudyFilingPath(type: "课堂", subject: "同步"),
            customProperties: [
                "apiKey": "must-not-sync",
                "sharedSecret": "must-not-sync",
                "HMAC": "must-not-sync",
                "safePreview": "可以同步"
            ],
            updatedAt: Date(timeIntervalSince1970: 1_020),
            modifiedByDeviceID: "iphone-01"
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-01",
            generatedAt: Date(timeIntervalSince1970: 1_030),
            items: [item.syncSanitized(modifiedByDeviceID: "iphone-01")],
            folders: [],
            pendingUploads: [
                PendingRecordingUpload(
                    itemID: item.itemID,
                    recordingID: "git-backed-recording",
                    localAudioRelativePath: "Recordings/git-backed-recording.m4a",
                    targetDeviceID: "mac-01"
                )
            ]
        )

        let result = try gitStore.commitManifest(manifest, deviceDisplayName: "Vita iPhone")
        let trackedFiles = result.trackedFiles

        #expect(result.commitID != nil)
        #expect(try gitStore.localGitConfigValue("commit.gpgsign") == "false")
        #expect(try gitStore.localGitConfigValue("tag.gpgSign") == "false")
        #expect(try gitStore.localGitConfigValue("gpg.format") == "openpgp")
        #expect(try gitStore.localGitConfigValue("user.name") == "Rokurics Sync")
        #expect(try gitStore.localGitConfigValue("user.email") == "rokurics-sync@local")
        #expect(try gitStore.localGitConfigValue("core.hooksPath") == "/dev/null")
        #expect(FileManager.default.fileExists(atPath: gitStore.repoURL.appendingPathComponent(".git", isDirectory: true).path))
        #expect(trackedFiles.contains("study/library_manifest.json"))
        #expect(trackedFiles.contains("study/schema_version.json"))
        #expect(trackedFiles.contains { $0.hasPrefix("study/items/") && $0.hasSuffix(".json") })
        #expect(trackedFiles.allSatisfy { path in
            path == ".gitignore"
                || path == "study/library_manifest.json"
                || path == "study/schema_version.json"
                || (path.hasPrefix("study/items/") && path.hasSuffix(".json"))
                || (path.hasPrefix("study/folders/") && path.hasSuffix(".json"))
                || (path.hasPrefix("study/tombstones/") && path.hasSuffix(".json"))
        })
        #expect(!trackedFiles.contains { $0.lowercased().contains("audio.m4a") })
        #expect(!trackedFiles.contains { $0.lowercased().contains("transcript.json") })
        #expect(!trackedFiles.contains { $0.lowercased().contains("transcript.md") })
        #expect(!trackedFiles.contains { $0.lowercased().contains("note.md") })
        #expect(try gitStore.trackedFilesContainingForbiddenMetadataPayloads().isEmpty)

        let itemFile = try #require(try FileManager.default.contentsOfDirectory(at: gitStore.itemsURL, includingPropertiesForKeys: nil).first)
        let itemJSON = try String(contentsOf: itemFile, encoding: .utf8)
        #expect(!itemJSON.contains("must-not-sync"))
        #expect(!itemJSON.contains("apiKey"))
        #expect(!itemJSON.contains("sharedSecret"))
        #expect(!itemJSON.contains("HMAC"))
        #expect(itemJSON.contains("safePreview"))
        #expect(FileManager.default.fileExists(atPath: gitStore.pendingUploadsURL.path))
        #expect(!trackedFiles.contains("state/pending_uploads.json"))
    }

    @Test func gitBackedCommitDoesNotInheritGlobalSigningConfig() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let hostileHomeURL = rootURL.appendingPathComponent("hostile-home", isDirectory: true)
        let hostileXDGConfigURL = rootURL.appendingPathComponent("hostile-xdg", isDirectory: true)
        let hostileXDGGitURL = hostileXDGConfigURL.appendingPathComponent("git", isDirectory: true)
        try FileManager.default.createDirectory(at: hostileHomeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hostileXDGGitURL, withIntermediateDirectories: true)
        let hostileGlobalConfigURL = hostileHomeURL.appendingPathComponent(".gitconfig", isDirectory: false)
        try """
        [user]
            name = User Signing Identity
            email = user@example.invalid
            signingkey = <keys>
        [commit]
            gpgsign = true
        [gpg]
            format = ssh

        """.write(to: hostileGlobalConfigURL, atomically: true, encoding: .utf8)
        try """
        [user]
            signingkey = <xdg-key>
        [commit]
            gpgsign = true
        [gpg]
            format = ssh

        """.write(to: hostileXDGGitURL.appendingPathComponent("config", isDirectory: false), atomically: true, encoding: .utf8)

        let previousGlobalConfig = getenv("GIT_CONFIG_GLOBAL").map { String(cString: $0) }
        let previousHome = getenv("HOME").map { String(cString: $0) }
        let previousXDGConfigHome = getenv("XDG_CONFIG_HOME").map { String(cString: $0) }
        let previousSSHAuthSock = getenv("SSH_AUTH_SOCK").map { String(cString: $0) }
        let previousGPGTTY = getenv("GPG_TTY").map { String(cString: $0) }
        setenv("GIT_CONFIG_GLOBAL", hostileGlobalConfigURL.path, 1)
        setenv("HOME", hostileHomeURL.path, 1)
        setenv("XDG_CONFIG_HOME", hostileXDGConfigURL.path, 1)
        setenv("SSH_AUTH_SOCK", rootURL.appendingPathComponent("fake-ssh-agent.sock", isDirectory: false).path, 1)
        setenv("GPG_TTY", "/dev/ttys999", 1)
        defer {
            restoreEnvironmentVariable("GIT_CONFIG_GLOBAL", previousGlobalConfig)
            restoreEnvironmentVariable("HOME", previousHome)
            restoreEnvironmentVariable("XDG_CONFIG_HOME", previousXDGConfigHome)
            restoreEnvironmentVariable("SSH_AUTH_SOCK", previousSSHAuthSock)
            restoreEnvironmentVariable("GPG_TTY", previousGPGTTY)
        }

        let gitStore = GitBackedStudyMetadataStore(rootURL: rootURL)
        let result = try gitStore.commitManifest(makeSyncManifest(recordingID: "global-signing"), deviceDisplayName: "Vita iPhone")
        let commitInvocation = try #require(gitStore.gitInvocations.first { $0.arguments.contains("commit") })
        let commitID = try #require(result.commitID)
        let protectedEnvironmentConfig = gitConfigPairs(from: commitInvocation.environment)

        #expect(commitID.count == 40)
        #expect(commitInvocation.arguments.contains("--no-gpg-sign"))
        #expect(commitInvocation.arguments.contains("--no-verify"))
        #expect(commitInvocation.arguments.contains("commit.gpgsign=false"))
        #expect(commitInvocation.arguments.contains("tag.gpgSign=false"))
        #expect(commitInvocation.arguments.contains("gpg.format=openpgp"))
        #expect(commitInvocation.arguments.contains("user.signingkey="))
        #expect(commitInvocation.arguments.contains("gpg.program=/usr/bin/false"))
        #expect(commitInvocation.arguments.contains("gpg.ssh.program=/usr/bin/false"))
        #expect(commitInvocation.arguments.contains("core.hooksPath=/dev/null"))
        #expect(commitInvocation.environment["GIT_TERMINAL_PROMPT"] == "0")
        #expect(commitInvocation.environment["GIT_CONFIG_NOSYSTEM"] == "1")
        #expect(commitInvocation.environment["GIT_CONFIG_SYSTEM"] == "/dev/null")
        #expect(commitInvocation.environment["GIT_CONFIG_GLOBAL"] != hostileGlobalConfigURL.path)
        #expect(commitInvocation.environment["GIT_CONFIG_GLOBAL"]?.hasPrefix(gitStore.rootURL.path) == true)
        #expect(commitInvocation.environment["HOME"] != hostileHomeURL.path)
        #expect(commitInvocation.environment["HOME"]?.hasPrefix(gitStore.rootURL.path) == true)
        #expect(commitInvocation.environment["XDG_CONFIG_HOME"] != hostileXDGConfigURL.path)
        #expect(commitInvocation.environment["XDG_CONFIG_HOME"]?.hasPrefix(gitStore.rootURL.path) == true)
        #expect(commitInvocation.environment["GIT_ASKPASS"] == "/usr/bin/false")
        #expect(commitInvocation.environment["SSH_ASKPASS"] == "/usr/bin/false")
        #expect(commitInvocation.environment["GCM_INTERACTIVE"] == "never")
        #expect(commitInvocation.environment["SSH_AUTH_SOCK"] == nil)
        #expect(commitInvocation.environment["GPG_TTY"] == nil)
        #expect(protectedEnvironmentConfig["commit.gpgsign"] == "false")
        #expect(protectedEnvironmentConfig["tag.gpgSign"] == "false")
        #expect(protectedEnvironmentConfig["gpg.format"] == "openpgp")
        #expect(protectedEnvironmentConfig["user.signingkey"] == "")
        #expect(protectedEnvironmentConfig["gpg.program"] == "/usr/bin/false")
        #expect(protectedEnvironmentConfig["gpg.ssh.program"] == "/usr/bin/false")
        #expect(protectedEnvironmentConfig["core.hooksPath"] == "/dev/null")
        #expect(protectedEnvironmentConfig["credential.helper"] == "")
        #expect(try gitStore.localGitConfigValue("commit.gpgsign") == "false")
        #expect(try gitStore.localGitConfigValue("tag.gpgSign") == "false")
        #expect(try gitStore.localGitConfigValue("user.name") == "Rokurics Sync")
        #expect(try gitStore.localGitConfigValue("user.email") == "rokurics-sync@local")
        #expect(try gitStore.localGitConfigValue("gpg.program") == "/usr/bin/false")
        #expect(try gitStore.localGitConfigValue("gpg.ssh.program") == "/usr/bin/false")
        #expect((try? gitStore.localGitConfigValue("user.signingkey")) == nil)

        let controlledGlobalConfigPath = try #require(commitInvocation.environment["GIT_CONFIG_GLOBAL"])
        let controlledGlobalConfig = try String(contentsOf: URL(fileURLWithPath: controlledGlobalConfigPath), encoding: .utf8)
        #expect(!controlledGlobalConfig.contains("<keys>"))
        #expect(!controlledGlobalConfig.contains("<xdg-key>"))
        #expect(controlledGlobalConfig.contains("gpgsign = false"))
        let forbiddenGitCommands = Set(["remote", "fetch", "pull", "push"])
        #expect(!gitStore.gitInvocations.contains { invocation in
            invocation.arguments.contains { forbiddenGitCommands.contains($0) }
        })
    }

    @Test func gitCommitFailurePreservesMetadataPendingUploadsAndWritesSyncError() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let gitShimURL = try makeCommitFailingGitShim(rootURL: rootURL)
        let gitStore = GitBackedStudyMetadataStore(rootURL: rootURL, gitExecutableURL: gitShimURL)
        let manifest = makeSyncManifest(recordingID: "commit-failure")

        var thrownMessage: String?
        do {
            _ = try gitStore.commitManifest(manifest, deviceDisplayName: "Vita iPhone")
        } catch {
            thrownMessage = error.localizedDescription
        }

        #expect(thrownMessage?.contains("simulated signing failure") == true)
        #expect(FileManager.default.fileExists(atPath: gitStore.manifestURL.path))
        #expect(FileManager.default.fileExists(atPath: gitStore.pendingUploadsURL.path))
        let itemFiles = try FileManager.default.contentsOfDirectory(at: gitStore.itemsURL, includingPropertiesForKeys: nil)
        #expect(itemFiles.contains { $0.lastPathComponent.contains("commit-failure") })
        let syncState = try decodeGitBackedSyncState(at: gitStore.syncStateURL)
        #expect(syncState.lastError?.contains("simulated signing failure") == true)
        #expect(syncState.pendingUploadCount == 1)
        #expect(syncState.gitCommitSuppressedUntil != nil)
        #expect(!gitStore.gitInvocations.filter { $0.arguments.contains("commit") }.isEmpty)
        #expect(gitStore.gitInvocations.filter { $0.arguments.contains("commit") }.count == 1)

        var retryMessage: String?
        do {
            _ = try gitStore.commitManifest(manifest, deviceDisplayName: "Vita iPhone")
        } catch {
            retryMessage = error.localizedDescription
        }

        #expect(retryMessage?.contains("git_metadata_commit_temporarily_suppressed") == true)
        #expect(gitStore.gitInvocations.filter { $0.arguments.contains("commit") }.count == 1)

        let restartedGitStore = GitBackedStudyMetadataStore(rootURL: rootURL, gitExecutableURL: gitShimURL)
        var restartedRetryMessage: String?
        do {
            _ = try restartedGitStore.commitManifest(manifest, deviceDisplayName: "Vita iPhone")
        } catch {
            restartedRetryMessage = error.localizedDescription
        }
        let suppressedState = try decodeGitBackedSyncState(at: restartedGitStore.syncStateURL)
        #expect(restartedRetryMessage?.contains("git_metadata_commit_temporarily_suppressed") == true)
        #expect(restartedGitStore.gitInvocations.filter { $0.arguments.contains("commit") }.isEmpty)
        #expect(FileManager.default.fileExists(atPath: restartedGitStore.pendingUploadsURL.path))
        #expect(suppressedState.pendingUploadCount == 1)
        #expect(suppressedState.gitCommitSuppressedUntil != nil)
    }

    @Test func iPhoneMetadataPushAppliesToMacStoreAndCreatesGitCommit() throws {
        let (fileStore, appRootURL, scratchURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let studyStore = StudyLibraryStore(rootURL: appRootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let gitStore = GitBackedStudyMetadataStore(rootURL: scratchURL.appendingPathComponent("study-sync", isDirectory: true))
        let remoteItem = StudyItemMetadata(
            recordingID: "iphone-pushed-recording",
            title: "iPhone 推送 metadata",
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 32,
            audioRelativePath: "Recordings/iphone-pushed-recording.m4a",
            studyFiling: StudyFilingPath(type: "课堂", subject: "物理"),
            updatedAt: Date(timeIntervalSince1970: 2_100),
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            modifiedByDeviceID: "iphone-01"
        )
        let incoming = StudyLibrarySyncManifest.make(
            deviceID: "iphone-01",
            generatedAt: Date(timeIntervalSince1970: 2_101),
            items: [remoteItem],
            folders: [],
            baseCommitID: nil,
            localManifestHash: "iphone-local"
        )

        let applyResult = try studyStore.applySyncManifest(incoming, localDeviceID: "mac-01")
        var merged = studyStore.makeSyncManifest(deviceID: "mac-01")
        let commit = try gitStore.commitManifest(merged, deviceDisplayName: "Vita iPhone")
        merged.commitID = commit.commitID
        let synced = try #require(studyStore.item(recordingID: "iphone-pushed-recording"))

        #expect(applyResult.appliedItemCount == 1)
        #expect(synced.title == "iPhone 推送 metadata")
        #expect(synced.customProperties["syncedMetadataOnly"] == "true")
        #expect(commit.commitID != nil)
        #expect(merged.commitID == commit.commitID)
    }

    @Test func macSnapshotPullUsesLastWriteWinsAndKeepsMissingReferencesSafe() throws {
        let (fileStore, appRootURL, scratchURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let recordingDirectory = try saveInboxRecording(
            id: "mac-pull-lww",
            title: "旧标题",
            store: fileStore,
            studyFiling: StudyFilingPath(type: "课堂", subject: "数学")
        )
        let audioURL = recordingDirectory.appendingPathComponent("audio.m4a", isDirectory: false)
        let studyStore = StudyLibraryStore(rootURL: appRootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let existing = try #require(studyStore.item(recordingID: "mac-pull-lww"))
        var remote = existing
        remote.title = "Mac 较新标题"
        remote.transcriptMarkdownRelativePath = "transcripts/missing/transcript.md"
        remote.noteRelativePath = "notes/missing/note.md"
        remote.updatedAt = existing.updatedAt.addingTimeInterval(60)
        remote.modifiedByDeviceID = "mac-01"
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "mac-01",
            generatedAt: remote.updatedAt.addingTimeInterval(1),
            items: [remote],
            folders: []
        )

        let result = try studyStore.applySyncManifest(manifest, localDeviceID: "iphone-01")
        let synced = try #require(studyStore.item(recordingID: "mac-pull-lww"))

        #expect(result.appliedItemCount == 1)
        #expect(synced.title == "Mac 较新标题")
        #expect(synced.transcriptMarkdownRelativePath == "transcripts/missing/transcript.md")
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test func deleteMetadataOnlyTombstoneDoesNotDeleteRealAudioDuringSync() throws {
        let (fileStore, appRootURL, scratchURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let recordingDirectory = try saveInboxRecording(id: "sync-tombstone-audio", title: "保留音频", store: fileStore)
        let audioURL = recordingDirectory.appendingPathComponent("audio.m4a", isDirectory: false)
        let studyStore = StudyLibraryStore(rootURL: appRootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        let item = try #require(studyStore.item(recordingID: "sync-tombstone-audio"))
        let tombstone = StudyLibrarySyncTombstone(
            id: "item:\(item.itemID)",
            entityKind: .item,
            entityID: item.itemID,
            operation: .deleteMetadataOnly,
            updatedAt: item.updatedAt.addingTimeInterval(30),
            modifiedByDeviceID: "iphone-01"
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-01",
            generatedAt: tombstone.updatedAt.addingTimeInterval(1),
            items: [],
            folders: [],
            tombstones: [tombstone]
        )

        let result = try studyStore.applySyncManifest(manifest, localDeviceID: "mac-01")

        #expect(result.tombstoneCount == 1)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }
}

private func makeSyncManifest(recordingID: String) -> StudyLibrarySyncManifest {
    let item = StudyItemMetadata(
        recordingID: recordingID,
        title: "Git signing isolation",
        createdAt: Date(timeIntervalSince1970: 3_000),
        duration: 18,
        audioRelativePath: "audio/inbox/1970-01-01/\(recordingID)/audio.m4a",
        studyFiling: StudyFilingPath(type: "课堂", subject: "同步"),
        updatedAt: Date(timeIntervalSince1970: 3_030),
        modifiedByDeviceID: "iphone-01"
    )
    return StudyLibrarySyncManifest.make(
        deviceID: "iphone-01",
        generatedAt: Date(timeIntervalSince1970: 3_040),
        items: [item.syncSanitized(modifiedByDeviceID: "iphone-01")],
        folders: [],
        pendingUploads: [
            PendingRecordingUpload(
                itemID: item.itemID,
                recordingID: recordingID,
                localAudioRelativePath: "Recordings/\(recordingID).m4a",
                targetDeviceID: "mac-01"
            )
        ]
    )
}

private func decodeGitBackedSyncState(at url: URL) throws -> GitBackedStudySyncState {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(GitBackedStudySyncState.self, from: Data(contentsOf: url))
}

private func restoreEnvironmentVariable(_ name: String, _ value: String?) {
    if let value {
        setenv(name, value, 1)
    } else {
        unsetenv(name)
    }
}

private func gitConfigPairs(from environment: [String: String]) -> [String: String] {
    guard let countText = environment["GIT_CONFIG_COUNT"],
          let count = Int(countText) else {
        return [:]
    }

    var result: [String: String] = [:]
    for index in 0..<count {
        guard let key = environment["GIT_CONFIG_KEY_\(index)"],
              let value = environment["GIT_CONFIG_VALUE_\(index)"] else {
            continue
        }
        result[key] = value
    }
    return result
}

private func makeCommitFailingGitShim(rootURL: URL) throws -> URL {
    let shimURL = rootURL.appendingPathComponent("git-commit-fails.sh", isDirectory: false)
    let script = """
    #!/bin/sh
    for arg in "$@"; do
      if [ "$arg" = "commit" ]; then
        echo "simulated signing failure" >&2
        exit 23
      fi
    done
    exec /usr/bin/git "$@"

    """
    try script.write(to: shimURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimURL.path)
    return shimURL
}

private func makeGitSpyShim(rootURL: URL) throws -> URL {
    let shimURL = rootURL.appendingPathComponent("git-spy.sh", isDirectory: false)
    let logURL = rootURL.appendingPathComponent("git-spy-invocations.log", isDirectory: false)
    let script = """
    #!/bin/sh
    echo "$@" >> "\(logURL.path)"
    exit 42

    """
    try script.write(to: shimURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimURL.path)
    return shimURL
}

@MainActor
private func makeSyncServer(
    rootURL: URL,
    gitStore: GitBackedStudyMetadataStore?,
    syncStateStore: StudyLibrarySyncStateStore,
    runtimeConfiguration: StudyLibrarySyncRuntimeConfiguration
) -> SecureLocalHTTPSServer {
    let appRootURL = rootURL.appendingPathComponent("MacApp", isDirectory: true)
    let recordingFileStore = MacRecordingFileStore(rootURL: appRootURL)
    let studyLibraryStore = StudyLibraryStore(
        rootURL: appRootURL,
        recordingFileStore: recordingFileStore,
        listenForInboxChanges: false
    )
    let pairedDeviceStore = PairedDeviceStore()
    return SecureLocalHTTPSServer(
        port: 8787,
        identityManager: MacIdentityManager(),
        pairingManager: PairingManager(pairedDeviceStore: pairedDeviceStore),
        requestVerifier: RequestVerifier(pairedDeviceProvider: { _ in nil }),
        receivedFileStore: ReceivedFileStore(),
        recordingFileStore: recordingFileStore,
        studyLibraryStore: studyLibraryStore,
        gitBackedStudyMetadataStore: gitStore,
        deviceConnectionStatusStore: DeviceConnectionStatusStore(
            rootURL: rootURL.appendingPathComponent("ConnectionStatus", isDirectory: true)
        ),
        syncStateStore: syncStateStore,
        syncRuntimeConfiguration: runtimeConfiguration,
        onReady: {},
        onFailed: { _ in },
        onPairingChanged: {},
        onUploadAccepted: { _ in },
        onRecordingAccepted: { _ in }
    )
}

private func makePairedDevice(id: String = "device-01") -> PairedDevice {
    PairedDevice(
        id: id,
        deviceName: "Vita iPhone",
        sharedSecretBase64URL: Data("sync-secret".utf8).base64URLEncodedString(),
        pairedAt: Date(timeIntervalSince1970: 1_000),
        lastSeenAt: nil
    )
}

private func makeScratchDirectory() throws -> URL {
    let scratchURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("RokuricsMacStudyLibrarySyncTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
    return scratchURL
}

private func makeMacStore() throws -> (MacRecordingFileStore, URL, URL) {
    let scratchURL = try makeScratchDirectory()
    let rootURL = scratchURL.appendingPathComponent("Rokurics", isDirectory: true)
    let store = MacRecordingFileStore(rootURL: rootURL)
    return (store, rootURL, scratchURL)
}

@discardableResult
private func saveInboxRecording(
    id: String,
    title: String,
    store: MacRecordingFileStore,
    studyFiling: StudyFilingPath? = nil
) throws -> URL {
    let sourceDevice = PairedDevice(
        id: "device-01",
        deviceName: "Vita iPhone",
        sharedSecretBase64URL: "secret",
        pairedAt: Date(timeIntervalSince1970: 1_000),
        lastSeenAt: nil
    )
    let metadata = IncomingRecordingMetadata(
        id: id,
        title: title,
        originalFileName: "\(id).m4a",
        relativeAudioPath: "Recordings/\(id).m4a",
        createdAt: Date(timeIntervalSince1970: 1_800),
        endedAt: Date(timeIntervalSince1970: 1_806),
        duration: 6,
        format: "m4a",
        codec: "AAC",
        sampleRate: 16_000,
        channels: 1,
        bitrate: 64_000,
        fileSize: 5,
        uploadStatus: "uploaded",
        transcriptionStatus: "notStarted",
        noteStatus: "notStarted",
        tags: [],
        studyFiling: studyFiling,
        sourceDeviceName: "Vita iPhone",
        sourceDeviceID: "device-01",
        uploadedAt: Date(timeIntervalSince1970: 1_807)
    )

    let receiveResult = try store.saveMetadata(metadata, sourceDevice: sourceDevice)
    _ = try store.saveAudio(body: Data("audio".utf8), recordingID: id, requestedFileName: "\(id).m4a", sourceDevice: sourceDevice)
    return receiveResult.directoryURL
}
