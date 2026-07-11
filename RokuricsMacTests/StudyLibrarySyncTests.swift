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
    @Test func macBusinessSignatureMappingMatchesSharedCrossDeviceFixtureAndIgnoresLocalState() {
        let filing = StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵")
        let mac = StudyItemMetadata(
            itemID: "item_recording_business-01",
            kind: .recordingBundle,
            title: "矩阵复习",
            createdAt: Date(timeIntervalSince1970: 8_100),
            updatedAt: Date(timeIntervalSince1970: 8_200),
            filing: filing,
            tags: [
                StudyTag(id: "mac-subject-id", namespace: "subject", value: "数学", displayName: "数学", createdAt: Date(timeIntervalSince1970: 8_102)),
                StudyTag(id: "mac-topic-id", namespace: "topic", value: "特征值", displayName: "特征值", createdAt: Date(timeIntervalSince1970: 8_101))
            ],
            folderIDs: ["mac-derived-folder"],
            customProperties: ["syncedMetadataOnly": "true"],
            recordingID: "business-01",
            sanitizedRecordingID: "mac-sanitized-id",
            duration: 84,
            audioRelativePath: "audio/inbox/business-01/audio.m4a",
            receiveRelativePath: "audio/inbox/business-01/receive.json",
            transcriptRelativePath: "mac/transcript.json",
            transcriptMarkdownRelativePath: "mac/transcript.md",
            noteRelativePath: "mac/note.md",
            transcriptionStatus: "completed",
            noteStatus: "completed",
            sourceDescription: "Mac inbox",
            modifiedByDeviceID: "mac-01",
            syncConflictStatus: "mac-warning"
        )
        var macLocalVariant = mac
        macLocalVariant.createdAt = Date(timeIntervalSince1970: 18_100)
        macLocalVariant.updatedAt = Date(timeIntervalSince1970: 18_200)
        macLocalVariant.folderIDs = ["another-derived-folder"]
        macLocalVariant.customProperties = ["local.finderBookmark": "mac-only"]
        macLocalVariant.sanitizedRecordingID = "another-local-sanitized-id"
        macLocalVariant.duration = 999
        macLocalVariant.audioRelativePath = "another/local/audio.m4a"
        macLocalVariant.receiveRelativePath = "another/local/receive.json"
        macLocalVariant.transcriptionStatus = "running"
        macLocalVariant.noteStatus = "waiting"
        macLocalVariant.modifiedByDeviceID = "another-mac"
        macLocalVariant.syncConflictStatus = "another-local-warning"

        let crossDeviceExpected = LocalNetworkStudyItemBusinessFieldsV2(
            itemID: "item_recording_business-01",
            itemKind: "recordingBundle",
            title: "矩阵复习",
            filing: LocalNetworkBusinessFilingV2(type: "课堂", subject: "线性代数", chapter: "矩阵"),
            tags: [
                LocalNetworkBusinessTagV2(namespace: "subject", value: "数学", displayName: "数学"),
                LocalNetworkBusinessTagV2(namespace: "topic", value: "特征值", displayName: "特征值")
            ],
            recordingID: "business-01",
            isTrashed: false
        )

        #expect(mac.localNetworkStudyItemBusinessFieldsV2 == crossDeviceExpected)
        #expect(mac.localNetworkStudyItemBusinessSignatureV2 == LocalNetworkBusinessSignatureV2.studyItem(crossDeviceExpected))
        #expect(mac.localNetworkStudyItemBusinessSignatureV2 == macLocalVariant.localNetworkStudyItemBusinessSignatureV2)
        #expect(mac.localNetworkRecordingBusinessSignatureV2 == macLocalVariant.localNetworkRecordingBusinessSignatureV2)
        #expect(mac.localNetworkStudyItemBusinessSignatureV2.hasPrefix(LocalNetworkBusinessSignatureV2.wirePrefix))

        let folder = StudyFolderMetadata(
            folderID: "folder-business-01",
            name: "矩阵",
            level: .chapter,
            path: filing,
            parentFolderID: "folder-parent-01",
            childFolderIDs: ["mac-child"],
            itemIDs: [mac.itemID],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            colorToken: .blue,
            customProperties: ["local.finderBookmark": "one"],
            modifiedByDeviceID: "mac-01",
            syncConflictStatus: "local-warning"
        )
        let folderLocalVariant = StudyFolderMetadata(
            folderID: folder.folderID,
            name: folder.name,
            level: folder.level,
            path: StudyFilingPath(type: "device-local-derived", subject: "path"),
            parentFolderID: folder.parentFolderID,
            childFolderIDs: ["other-child"],
            itemIDs: ["other-item"],
            createdAt: Date(timeIntervalSince1970: 101),
            updatedAt: Date(timeIntervalSince1970: 102),
            colorToken: folder.colorToken,
            customProperties: ["local.finderBookmark": "two"],
            modifiedByDeviceID: "mac-02",
            syncConflictStatus: "other-warning"
        )
        let expectedFolder = LocalNetworkFolderBusinessFieldsV2(
            folderID: "folder-business-01",
            name: "矩阵",
            level: "chapter",
            parentFolderID: "folder-parent-01",
            colorToken: "blue",
            isTrashed: false
        )
        #expect(folder.localNetworkFolderBusinessFieldsV2 == expectedFolder)
        #expect(folder.localNetworkFolderBusinessSignatureV2 == LocalNetworkBusinessSignatureV2.folder(expectedFolder))
        #expect(folder.localNetworkFolderBusinessSignatureV2 == folderLocalVariant.localNetworkFolderBusinessSignatureV2)

        var folderBusinessChange = folderLocalVariant
        folderBusinessChange.name = "矩阵（更新）"
        #expect(folder.localNetworkFolderBusinessSignatureV2 != folderBusinessChange.localNetworkFolderBusinessSignatureV2)
    }

    @Test func macBusinessMergePreservesMacLocalFilesAndProcessingState() {
        let localTagDate = Date(timeIntervalSince1970: 50)
        let local = StudyItemMetadata(
            itemID: "item_recording_mac-merge-01",
            kind: .recordingBundle,
            title: "旧标题",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            filing: StudyFilingPath(type: "课堂", subject: "旧课程"),
            tags: [StudyTag(id: "mac-local-tag", namespace: "topic", value: "矩阵", displayName: "旧显示名", createdAt: localTagDate)],
            folderIDs: ["mac-derived-folder"],
            customProperties: ["syncedMetadataOnly": "true", "business.priority": "old"],
            recordingID: "mac-merge-01",
            sanitizedRecordingID: "mac-local-sanitized",
            duration: 20,
            audioRelativePath: "audio/inbox/mac-merge-01/audio.m4a",
            receiveRelativePath: "audio/inbox/mac-merge-01/receive.json",
            transcriptRelativePath: "local/transcript.json",
            transcriptMarkdownRelativePath: "local/transcript.md",
            noteRelativePath: "local/note.md",
            transcriptionStatus: "local-completed",
            noteStatus: "local-completed",
            sourceDescription: "Mac inbox",
            modifiedByDeviceID: "mac-01",
            syncConflictStatus: "mac-local-conflict"
        )
        let remoteFiling = StudyFilingPath(type: "复习", subject: "新课程")
        let remote = StudyItemMetadata(
            itemID: local.itemID,
            kind: .recordingBundle,
            title: "新标题",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            filing: remoteFiling,
            tags: [StudyTag(id: "iphone-tag", namespace: "topic", value: "矩阵", displayName: "新显示名", createdAt: Date(timeIntervalSince1970: 101))],
            folderIDs: ["iphone-derived-folder"],
            customProperties: ["business.priority": "new", "iphone.local": "drop"],
            recordingID: "mac-merge-01",
            sanitizedRecordingID: "iphone-sanitized",
            duration: 99,
            audioRelativePath: "Recordings/mac-merge-01.m4a",
            receiveRelativePath: "Receives/mac-merge-01.json",
            transcriptRelativePath: "remote/transcript.json",
            transcriptMarkdownRelativePath: "remote/transcript.md",
            noteRelativePath: "remote/note.md",
            transcriptionStatus: "remote-running",
            noteStatus: "remote-waiting",
            sourceDescription: "iPhone microphone",
            modifiedByDeviceID: "iphone-01",
            syncConflictStatus: "iphone-conflict"
        )

        let merged = local.mergingRemoteBusinessFieldsV2(
            from: remote,
            explicitBusinessCustomPropertyKeys: ["business.priority"]
        )
        #expect(merged.title == remote.title)
        #expect(merged.filing == remoteFiling)
        #expect(merged.folderIDs == StudyItemMetadata.defaultFolderIDs(for: remoteFiling))
        #expect(merged.tags.first?.displayName == "新显示名")
        #expect(merged.tags.first?.id == "mac-local-tag")
        #expect(merged.tags.first?.createdAt == localTagDate)
        #expect(merged.customProperties == ["syncedMetadataOnly": "true", "business.priority": "new"])
        #expect(merged.updatedAt == remote.updatedAt)
        #expect(merged.modifiedByDeviceID == "iphone-01")

        #expect(merged.createdAt == local.createdAt)
        #expect(merged.sanitizedRecordingID == local.sanitizedRecordingID)
        #expect(merged.duration == local.duration)
        #expect(merged.audioRelativePath == local.audioRelativePath)
        #expect(merged.receiveRelativePath == local.receiveRelativePath)
        #expect(merged.transcriptRelativePath == local.transcriptRelativePath)
        #expect(merged.transcriptMarkdownRelativePath == local.transcriptMarkdownRelativePath)
        #expect(merged.noteRelativePath == local.noteRelativePath)
        #expect(merged.transcriptionStatus == local.transcriptionStatus)
        #expect(merged.noteStatus == local.noteStatus)
        #expect(merged.sourceDescription == local.sourceDescription)
        #expect(merged.syncConflictStatus == local.syncConflictStatus)
    }

    @Test func sharedSyncCorePlansObjectDiffsWithoutFileTypeBranches() {
        let date = Date(timeIntervalSince1970: 10)
        let localSummary = SyncObject(
            objectID: "summaryJSON:shared-core-note",
            objectKind: LocalNetworkSyncObjectKind.summaryJSON.rawValue,
            ownerID: "shared-core-note",
            displayTitle: "Shared core note",
            fileName: "summary.json",
            logicalName: "notes/shared-core-note/summary.json",
            sha256: "local-summary",
            size: 20,
            updatedAt: Date(timeIntervalSince1970: 20),
            tombstone: false,
            deleted: false,
            sourceDeviceID: "mac-01",
            logicalPathToken: "notes/shared-core-note/summary.json",
            availability: .local,
            transferState: nil,
            transferProgress: nil,
            conflictStatus: nil,
            autoDownloadAllowed: true,
            metadata: [:]
        )
        var peerSummary = localSummary
        peerSummary.sha256 = "peer-summary"
        peerSummary.size = 19
        peerSummary.updatedAt = date
        peerSummary.sourceDeviceID = "iphone-01"

        let local = SyncInventory.make(
            sourceDeviceID: "mac-01",
            sourcePlatform: "Mac",
            generatedAt: date,
            inventoryRevision: "local",
            objects: [localSummary]
        )
        let peer = SyncInventory.make(
            sourceDeviceID: "iphone-01",
            sourcePlatform: "iPhone",
            generatedAt: date,
            inventoryRevision: "peer",
            objects: [peerSummary]
        )

        let plan = SyncDiffPlanner().plan(local: local, peer: peer, lastSuccessfulSyncAt: nil)

        #expect(plan.uploadObjectActions.map(\.objectID) == ["summaryJSON:shared-core-note"])
        #expect(plan.uploadObjectActions.first?.reason == "local_object_newer")
    }

    @Test func localNetworkInventoryBridgesToSharedSyncCoreObjects() {
        let generatedAt = Date(timeIntervalSince1970: 11)
        let folder = LocalNetworkSyncFolderEntry(
            folderID: "folder-shared-core",
            parentID: nil,
            path: "Course/Chapter",
            name: "Chapter",
            colorToken: "blue",
            updatedAt: generatedAt,
            revisionHash: "folder-hash",
            deleted: false
        )
        let inventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: generatedAt,
                lastKnownPeerRevision: "peer-rev",
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            folders: [folder]
        )

        let coreInventory = inventory.syncCoreInventory
        let directory = coreInventory.directories.first
        let folderObject = coreInventory.objects.first { $0.objectID == "studyFolder:folder-shared-core" }

        #expect(coreInventory.hasValidInventoryHash)
        #expect(coreInventory.sourcePlatform == "Mac")
        #expect(directory?.pathComponents == ["Course", "Chapter"])
        #expect(folderObject?.ownerID == "folder-shared-core")
        #expect(folderObject?.sha256 == "folder-hash")
    }

    @Test func gitBackedStudySyncRuntimeDefaultsToDisabled() {
        #expect(!StudyLibrarySyncRuntimeConfiguration.default.gitBackedSyncEnabled)
        #expect(!StudyLibrarySyncRuntimeConfiguration.disabled.gitBackedSyncEnabled)
        #expect(StudyLibrarySyncRuntimeConfiguration.disabledReason == "Git-backed study sync is disabled")
    }

    @MainActor
    @Test func disabledSyncEndpointsSkipGitAndPreservePendingState() async throws {
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
        let applyResponse = try await server.syncApplyResponseForVerifiedDevice(device, requestBody: Data("not json".utf8))

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
        let gitStore = GitBackedStudyMetadataStore(
            rootURL: rootURL,
            gitCommandInterceptor: { arguments in
                guard arguments.contains("commit") else {
                    return nil
                }
                throw GitBackedStudyMetadataStoreError.gitFailed("simulated signing failure")
            }
        )
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

        let restartedGitStore = GitBackedStudyMetadataStore(
            rootURL: rootURL,
            gitCommandInterceptor: { arguments in
                guard arguments.contains("commit") else {
                    return nil
                }
                throw GitBackedStudyMetadataStoreError.gitFailed("simulated signing failure")
            }
        )
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

    @Test func iPhoneMetadataPushAppliesToMacStoreAndCreatesGitCommit() async throws {
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

        let applyResult = try await studyStore.applySyncManifest(incoming, localDeviceID: "mac-01")
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

    @Test func macBusinessEqualMetadataOnlyMarkerPersistsAndClearsAcrossRefresh() async throws {
        let (fileStore, appRootURL, scratchURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let studyStore = StudyLibraryStore(
            rootURL: appRootURL,
            recordingFileStore: fileStore,
            listenForInboxChanges: false
        )
        let item = StudyItemMetadata(
            itemID: "iphone-stable-metadata-only-item",
            kind: .recordingBundle,
            title: "仅元数据录音",
            createdAt: Date(timeIntervalSince1970: 2_200),
            updatedAt: Date(timeIntervalSince1970: 2_210),
            recordingID: "mac-marker-roundtrip",
            duration: 6,
            modifiedByDeviceID: "iphone-01"
        )
        try studyStore.save(item)
        studyStore.refresh()

        // A recording bundle without local audio is hidden until its local
        // metadata-only receipt marker has been persisted.
        #expect(studyStore.item(itemID: item.itemID) == nil)

        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-01",
            generatedAt: Date(timeIntervalSince1970: 2_220),
            items: [item],
            folders: []
        )
        let metadataOnlyResult = try await studyStore.applySyncManifest(
            manifest,
            localDeviceID: "mac-01"
        )
        studyStore.refresh()
        let metadataOnlyItem = try #require(studyStore.item(itemID: item.itemID))

        #expect(metadataOnlyResult.appliedItemCount == 1)
        #expect(metadataOnlyItem.customProperties["syncedMetadataOnly"] == "true")

        _ = try await saveInboxRecording(
            id: try #require(item.recordingID),
            title: item.title,
            store: fileStore
        )
        let audioAvailableResult = try await studyStore.applySyncManifest(
            manifest,
            localDeviceID: "mac-01"
        )
        studyStore.refresh()
        let audioAvailableItem = try #require(studyStore.item(itemID: item.itemID))
        let reloadedStore = StudyLibraryStore(
            rootURL: appRootURL,
            recordingFileStore: fileStore,
            listenForInboxChanges: false
        )
        let reloadedItem = try #require(reloadedStore.item(itemID: item.itemID))

        #expect(audioAvailableResult.appliedItemCount == 1)
        #expect(audioAvailableItem.customProperties["syncedMetadataOnly"] == nil)
        #expect(reloadedItem.customProperties["syncedMetadataOnly"] == nil)
        #expect(reloadedItem.recordingID == item.recordingID)
    }

    @Test func macSnapshotPullUsesLastWriteWinsAndKeepsMissingReferencesSafe() async throws {
        let (fileStore, appRootURL, scratchURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let recordingDirectory = try await saveInboxRecording(
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

        let result = try await studyStore.applySyncManifest(manifest, localDeviceID: "iphone-01")
        let synced = try #require(studyStore.item(recordingID: "mac-pull-lww"))

        #expect(result.appliedItemCount == 1)
        #expect(synced.title == "Mac 较新标题")
        // A peer-owned path is not portable and the referenced file does not
        // exist in this receiver's storage. LWW applies the business title,
        // while the receiver keeps its local processing/resource facts.
        #expect(synced.transcriptMarkdownRelativePath == nil)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test func deleteMetadataOnlyTombstoneDoesNotDeleteRealAudioDuringSync() async throws {
        let (fileStore, appRootURL, scratchURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let recordingDirectory = try await saveInboxRecording(id: "sync-tombstone-audio", title: "保留音频", store: fileStore)
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

        let result = try await studyStore.applySyncManifest(manifest, localDeviceID: "mac-01")

        #expect(result.tombstoneCount == 1)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @MainActor
    @Test func localNetworkSyncInventoryRequiresPairedSignedRequest() throws {
        let device = makePairedDevice(id: "sync-device-01")
        let body = try JSONEncoder().encode(LocalNetworkSyncInventoryRequest(deviceID: "iphone-01", generatedAt: Date(timeIntervalSince1970: 1), localInventoryHash: nil))
        let verifier = RequestVerifier(pairedDeviceProvider: { id in id == device.id ? device : nil })
        let accepted = verifier.verify(
            method: "POST",
            path: "/sync/inventory",
            headers: try signedSyncHeaders(device: device, path: "/sync/inventory", body: body, nonce: "nonce-inventory-good"),
            body: body,
            now: Date(timeIntervalSince1970: 1_000)
        )
        var badHeaders = try signedSyncHeaders(device: device, path: "/sync/inventory", body: body, nonce: "nonce-inventory-bad")
        badHeaders["X-Rokurics-Signature"] = "bad-signature"
        let badSignature = verifier.verify(method: "POST", path: "/sync/inventory", headers: badHeaders, body: body, now: Date(timeIntervalSince1970: 1_000))
        let unpairedVerifier = RequestVerifier(pairedDeviceProvider: { _ in nil })
        let unpaired = unpairedVerifier.verify(
            method: "POST",
            path: "/sync/inventory",
            headers: try signedSyncHeaders(device: device, path: "/sync/inventory", body: body, nonce: "nonce-inventory-unpaired"),
            body: body,
            now: Date(timeIntervalSince1970: 1_000)
        )

        if case .accepted = accepted {
        } else {
            Issue.record("Expected signed inventory request to be accepted")
        }
        if case .rejected("signature_mismatch") = badSignature {
        } else {
            Issue.record("Expected bad signature to be rejected")
        }
        if case .rejected("unknown_device") = unpaired {
        } else {
            Issue.record("Expected unpaired inventory request to be rejected")
        }
    }

    @MainActor
    @Test func localNetworkSyncArtifactPutRequiresPairedSignedRequest() throws {
        let device = makePairedDevice(id: "sync-artifact-put-device")
        let request = LocalNetworkSyncArtifactPutRequest(
            artifactID: LocalNetworkSyncArtifactID.make(
                kind: .transcriptMarkdown,
                ownerID: "artifact-put-recording",
                logicalPathToken: "transcripts/artifact-put-recording/transcript.md"
            ),
            kind: .transcriptMarkdown,
            ownerID: "artifact-put-recording",
            checksum: MacSecurityUtilities.sha256Hex(Data("artifact put".utf8)),
            size: Int64(Data("artifact put".utf8).count),
            updatedAt: Date(timeIntervalSince1970: 2_500),
            logicalPathToken: "transcripts/artifact-put-recording/transcript.md",
            dataBase64: Data("artifact put".utf8).base64EncodedString()
        )
        let body = try JSONEncoder.syncTestEncoder.encode(request)
        let verifier = RequestVerifier(pairedDeviceProvider: { id in id == device.id ? device : nil })

        let accepted = verifier.verify(
            method: "POST",
            path: "/sync/artifact-put",
            headers: try signedSyncHeaders(device: device, path: "/sync/artifact-put", body: body, nonce: "nonce-artifact-put-good"),
            body: body,
            now: Date(timeIntervalSince1970: 1_000)
        )
        var badHeaders = try signedSyncHeaders(device: device, path: "/sync/artifact-put", body: body, nonce: "nonce-artifact-put-bad")
        badHeaders["X-Rokurics-Signature"] = "bad-signature"
        let badSignature = verifier.verify(
            method: "POST",
            path: "/sync/artifact-put",
            headers: badHeaders,
            body: body,
            now: Date(timeIntervalSince1970: 1_000)
        )
        var missingBodyHashHeaders = try signedSyncHeaders(device: device, path: "/sync/artifact-put", body: body, nonce: "nonce-artifact-put-missing-hash")
        missingBodyHashHeaders.removeValue(forKey: "X-Rokurics-Body-SHA256")
        let missingBodyHash = verifier.verify(
            method: "POST",
            path: "/sync/artifact-put",
            headers: missingBodyHashHeaders,
            body: body,
            now: Date(timeIntervalSince1970: 1_000)
        )
        let unpairedVerifier = RequestVerifier(pairedDeviceProvider: { _ in nil })
        let unpaired = unpairedVerifier.verify(
            method: "POST",
            path: "/sync/artifact-put",
            headers: try signedSyncHeaders(device: device, path: "/sync/artifact-put", body: body, nonce: "nonce-artifact-put-unpaired"),
            body: body,
            now: Date(timeIntervalSince1970: 1_000)
        )

        if case .accepted = accepted {
        } else {
            Issue.record("Expected signed artifact-put request to be accepted")
        }
        if case .rejected("signature_mismatch") = badSignature {
        } else {
            Issue.record("Expected bad artifact-put signature to be rejected")
        }
        if case .rejected("missing_security_headers") = missingBodyHash {
        } else {
            Issue.record("Expected artifact-put without body hash to be rejected")
        }
        if case .rejected("unknown_device") = unpaired {
        } else {
            Issue.record("Expected unpaired artifact-put request to be rejected")
        }
        #expect(verifier.lastTrace?.verifierFailedReason != device.sharedSecretBase64URL)
    }

    @MainActor
    @Test func localNetworkSyncInventoryReturnsReceiveAndTranscriptMetadataWithoutSecretsOrPaths() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let fileStore = MacRecordingFileStore(rootURL: appRootURL)
        _ = try await saveInboxRecording(id: "inventory-recording", title: "已转写", store: fileStore)
        let transcriptRelativePath = "transcripts/inventory-recording/transcript.md"
        let transcriptURL = appRootURL.appendingPathComponent(transcriptRelativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: transcriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("mac transcript".utf8).write(to: transcriptURL)
        try fileStore.updateTranscriptionStatus(
            recordingID: "inventory-recording",
            status: "transcribed",
            transcriptRelativePath: nil,
            transcriptMarkdownRelativePath: transcriptRelativePath,
            providerID: "whisper.cpp",
            modelName: "small",
            startedAt: nil,
            completedAt: Date(timeIntervalSince1970: 2_000),
            errorMessage: nil
        )
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default
        )

        let response = await server.localNetworkSyncInventoryResponseForVerifiedDevice(makePairedDevice())
        let inventory = try #require(response.inventory)
        let encoded = String(data: try JSONEncoder().encode(inventory), encoding: .utf8) ?? ""

        #expect(response.ok)
        #expect(inventory.schemaVersion == LocalNetworkSyncInventory.appSchemaVersion)
        #expect(inventory.sourcePlatform == .Mac)
        #expect(inventory.sourceDeviceID == inventory.device.deviceID)
        #expect(inventory.recordings.first { $0.recordingID == "inventory-recording" }?.receiveStatus == "completed")
        #expect(inventory.artifacts.contains { $0.kind == .receiveJSON })
        #expect(inventory.artifacts.contains { $0.kind == .transcriptMarkdown && $0.logicalPathToken == transcriptRelativePath })
        #expect(inventory.objects.contains { $0.objectKind == .transcriptMarkdown && $0.fileName == "transcript.md" && $0.size != nil && $0.updatedAt >= Date(timeIntervalSince1970: 0) })
        #expect(!encoded.contains(appRootURL.path))
        #expect(!encoded.lowercased().contains("sharedsecret"))
    }

    @MainActor
    @Test func localNetworkSyncInventoryBuildsMetadataJobsAndHashesOffMain() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let fileStore = MacRecordingFileStore(rootURL: appRootURL)
        _ = try await saveInboxRecording(id: "off-main-inventory", title: "Off Main", store: fileStore)
        let diagnostics = LockedConnectionDiagnostics()
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default,
            onConnectionDiagnostic: diagnostics.append
        )

        let response = await server.localNetworkSyncInventoryResponseForVerifiedDevice(
            makePairedDevice(),
            syncRunID: "mac-off-main-inventory"
        )
        let report = try #require(diagnostics.events().last { $0.phase == "canonicalInventoryRuntimeReportWritten" }?.errorMessage)
        let manifestOffMain = try #require(diagnostics.events().last { $0.phase == "macInventoryManifestBuildOffMain" }?.errorMessage)
        let manifestCompleted = try #require(diagnostics.events().last { $0.phase == "macInventoryManifestBuildCompleted" }?.errorMessage)

        #expect(response.ok)
        #expect(diagnostics.events().contains { $0.phase == "inventoryBuildDurationMs" && $0.errorMessage?.isEmpty == false })
        #expect(manifestOffMain.contains("offMain=true"))
        #expect(manifestCompleted.contains("manifestBuildDurationMs="))
        #expect(report.contains("metadataLoadDurationMs="))
        #expect(report.contains("jobsLoadDurationMs="))
        #expect(report.contains("manifestBuildDurationMs="))
        #expect(report.contains("hashSkippedByCacheHitCount="))
        #expect(report.contains("mainActorMetadataLoadAttemptCount=0"))
        #expect(report.contains("mainActorJobsLoadAttemptCount=0"))
        #expect(report.contains("mainActorManifestBuildAttemptCount=0"))
        #expect(report.contains("mainActorHashAttemptCount=0"))
        #expect(report.contains("duplicateSnapshotBuildCount=0"))
    }

    @MainActor
    @Test func oldKernelMacInventorySkipsCanonicalBuildAndPreservesLegacySchema() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let fileStore = MacRecordingFileStore(rootURL: appRootURL)
        _ = try await saveInboxRecording(id: "old-kernel-inventory", title: "Old Kernel", store: fileStore)
        let diagnostics = LockedConnectionDiagnostics()
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default,
            canonicalKernelMode: .oldKernel,
            onConnectionDiagnostic: diagnostics.append
        )

        let response = await server.localNetworkSyncInventoryResponseForVerifiedDevice(
            makePairedDevice(),
            syncRunID: "old-kernel-skip"
        )
        let inventory = try #require(response.inventory)
        let events = diagnostics.events()
        let phases = Set(events.map(\.phase))
        let routeCompleted = try #require(events.last { $0.phase == "macInventoryRouteCompleted" }?.errorMessage)
        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(LocalNetworkSyncInventoryResponse.self, from: encoded)
        let encodedText = String(data: encoded, encoding: .utf8) ?? ""

        #expect(response.ok)
        #expect(decoded.ok)
        #expect(inventory.canonicalManifest == nil)
        #expect(decoded.inventory?.canonicalManifest == nil)
        #expect(inventory.schemaVersion == LocalNetworkSyncInventory.appSchemaVersion)
        #expect(inventory.recordings.contains { $0.recordingID == "old-kernel-inventory" })
        #expect(!encodedText.contains("canonicalManifest"))
        #expect(phases.contains("macInventoryCanonicalBuildSkippedBecauseOldKernel"))
        #expect(!phases.contains("macInventoryCanonicalBuildStarted"))
        #expect(!phases.contains("canonicalInventoryCoverageReportWritten"))
        #expect(!phases.contains("canonicalFileKernelSnapshotBuilt"))
        #expect(!phases.contains("canonicalFileKernelManifestBuilt"))
        #expect(!phases.contains("macInventorySeamUsedSharedSnapshot"))
        #expect(routeCompleted.contains("canonicalBuildSkippedCount=1"))
        #expect(routeCompleted.contains("mainActorCanonicalBuildAttemptCount=0"))
    }

    @MainActor
    @Test func canonicalShadowMacInventoryBuildsCanonicalFactsOffMainAndReusesSnapshot() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let fileStore = MacRecordingFileStore(rootURL: appRootURL)
        _ = try await saveInboxRecording(id: "shadow-inventory", title: "Shadow", store: fileStore)
        let diagnostics = LockedConnectionDiagnostics()
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default,
            canonicalKernelMode: .canonicalShadow,
            onConnectionDiagnostic: diagnostics.append
        )

        let response = await server.localNetworkSyncInventoryResponseForVerifiedDevice(
            makePairedDevice(),
            syncRunID: "shadow-off-main"
        )
        let inventory = try #require(response.inventory)
        let events = diagnostics.events()
        let phases = Set(events.map(\.phase))
        let offMain = try #require(events.last { $0.phase == "macInventoryCanonicalBuildOffMain" }?.errorMessage)
        let fileSnapshot = try #require(events.last { $0.phase == "canonicalFileKernelSnapshotBuilt" }?.errorMessage)
        let fileManifest = try #require(events.last { $0.phase == "canonicalFileKernelManifestBuilt" }?.errorMessage)
        let completed = try #require(events.last { $0.phase == "macInventoryRouteCompleted" }?.errorMessage)

        #expect(response.ok)
        #expect(inventory.canonicalManifest != nil)
        #expect(phases.contains("macInventoryCanonicalBuildStarted"))
        #expect(phases.contains("macInventoryCanonicalBuildCompleted"))
        #expect(phases.contains("macInventoryCanonicalBuildReused"))
        #expect(phases.contains("macInventoryCanonicalDuplicateBuildPrevented"))
        #expect(phases.contains("macInventorySeamUsedSharedSnapshot"))
        #expect(!phases.contains("macInventoryCanonicalBuildSkippedBecauseOldKernel"))
        #expect(offMain.contains("offMain=true"))
        #expect(offMain.contains("mainActorCanonicalBuildAttemptCount=0"))
        #expect(fileSnapshot.contains("builtOffMain=true"))
        #expect(fileSnapshot.contains("mainActorFileTreeAttemptCount=0"))
        #expect(fileSnapshot.contains("requestBuildCount=1"))
        #expect(fileManifest.contains("builtOffMain=true"))
        #expect(fileManifest.contains("cacheKeyPrefix="))
        #expect(completed.contains("canonicalBuildSkippedCount=0"))
        #expect(completed.contains("canonicalBuildReusedCount=1"))
        #expect(completed.contains("duplicateCanonicalBuildPreventedCount=1"))
        #expect(completed.contains("mainActorCanonicalBuildAttemptCount=0"))
    }

    @MainActor
    @Test func canonicalFullSyncMacInventoryBuildsCanonicalSnapshotOncePerRequest() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let fileStore = MacRecordingFileStore(rootURL: appRootURL)
        _ = try await saveInboxRecording(id: "full-sync-inventory", title: "Full Sync", store: fileStore)
        let diagnostics = LockedConnectionDiagnostics()
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default,
            canonicalKernelMode: .canonicalFullSync,
            onConnectionDiagnostic: diagnostics.append
        )

        let response = await server.localNetworkSyncInventoryResponseForVerifiedDevice(
            makePairedDevice(),
            syncRunID: "full-sync-once"
        )
        let events = diagnostics.events()
        let routeCompleted = try #require(events.last { $0.phase == "macInventoryRouteCompleted" }?.errorMessage)
        let runtimeReuse = try #require(events.last { $0.phase == "canonicalInventoryRuntimeSnapshotReused" }?.errorMessage)

        #expect(response.ok)
        #expect(response.inventory?.canonicalManifest != nil)
        #expect(events.filter { $0.phase == "macInventoryCanonicalBuildStarted" }.count == 1)
        #expect(events.filter { $0.phase == "macInventoryCanonicalBuildCompleted" }.count == 1)
        #expect(events.filter { $0.phase == "macInventoryCanonicalBuildReused" }.count == 1)
        #expect(events.filter { $0.phase == "macInventoryCanonicalDuplicateBuildPrevented" }.count == 1)
        #expect(events.filter { $0.phase == "canonicalFileKernelSnapshotBuilt" }.count == 1)
        #expect(events.filter { $0.phase == "canonicalFileKernelManifestBuilt" }.count == 1)
        #expect(routeCompleted.contains("canonicalBuildReusedCount=1"))
        #expect(routeCompleted.contains("duplicateCanonicalBuildPreventedCount=1"))
        #expect(runtimeReuse.contains("reused=true"))
    }

    @MainActor
    @Test func localNetworkSyncArtifactRequestRejectsTraversalAndServesApprovedTranscript() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let fileStore = MacRecordingFileStore(rootURL: appRootURL)
        _ = try await saveInboxRecording(id: "artifact-recording", title: "Artifact", store: fileStore)
        let transcriptRelativePath = "transcripts/artifact-recording/transcript.md"
        let transcriptURL = appRootURL.appendingPathComponent(transcriptRelativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: transcriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("approved transcript".utf8).write(to: transcriptURL)
        try fileStore.updateTranscriptionStatus(
            recordingID: "artifact-recording",
            status: "transcribed",
            transcriptRelativePath: nil,
            transcriptMarkdownRelativePath: transcriptRelativePath,
            providerID: "whisper.cpp",
            modelName: "small",
            startedAt: nil,
            completedAt: Date(timeIntervalSince1970: 2_000),
            errorMessage: nil
        )
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default
        )
        let inventory = try #require(await server.localNetworkSyncInventoryResponseForVerifiedDevice(makePairedDevice()).inventory)
        let artifact = try #require(inventory.artifacts.first { $0.kind == .transcriptMarkdown })
        let requestBody = try JSONEncoder().encode(LocalNetworkSyncArtifactRequest(artifactID: artifact.artifactID))

        let response = await server.localNetworkSyncArtifactResponseForVerifiedDevice(makePairedDevice(), requestBody: requestBody)
        let traversal = await server.localNetworkSyncArtifactResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder().encode(LocalNetworkSyncArtifactRequest(artifactID: "../secret"))
        )
        let unknown = await server.localNetworkSyncArtifactResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder().encode(LocalNetworkSyncArtifactRequest(artifactID: LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "missing", logicalPathToken: "transcripts/missing.md")))
        )

        let expectedChecksum = await CanonicalChecksumRuntime().checksum(
            fileURL: transcriptURL,
            logicalToken: "transcripts/artifact-recording/transcript.md",
            nodeRole: .mac,
            cacheDirectoryURL: scratchURL.appendingPathComponent("checksum-cache", isDirectory: true),
            configuration: CanonicalInventoryRuntimeConfiguration(persistentChecksumCacheEnabled: false)
        ).sha256

        #expect(response.ok)
        #expect(response.checksum == expectedChecksum)
        #expect(response.size == Int64(Data("approved transcript".utf8).count))
        #expect(String(data: Data(base64Encoded: try #require(response.dataBase64)) ?? Data(), encoding: .utf8) == "approved transcript")
        #expect(!traversal.ok)
        #expect(traversal.error == "invalid_artifact_id")
        #expect(!unknown.ok)
        #expect(unknown.error == "artifact_not_found")
    }

    @MainActor
    @Test func localNetworkSyncArtifactPutStoresApprovedSmallArtifactAndRejectsUnsafePaths() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default
        )
        let transcriptPath = "transcripts/incoming-recording/transcript.md"
        let transcriptData = Data("incoming transcript".utf8)
        let transcriptArtifactID = LocalNetworkSyncArtifactID.make(
            kind: .transcriptMarkdown,
            ownerID: "incoming-recording",
            logicalPathToken: transcriptPath
        )
        let request = LocalNetworkSyncArtifactPutRequest(
            artifactID: transcriptArtifactID,
            kind: .transcriptMarkdown,
            ownerID: "incoming-recording",
            checksum: MacSecurityUtilities.sha256Hex(transcriptData),
            size: Int64(transcriptData.count),
            updatedAt: Date(timeIntervalSince1970: 2_500),
            logicalPathToken: transcriptPath,
            dataBase64: transcriptData.base64EncodedString()
        )

        let response = await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(request)
        )
        let storedURL = appRootURL.appendingPathComponent(transcriptPath, isDirectory: false)
        let repeated = await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(request)
        )
        let traversalPath = "transcripts/../secret.md"
        let traversal = await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactPutRequest(
                artifactID: LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "incoming-recording", logicalPathToken: traversalPath),
                kind: .transcriptMarkdown,
                ownerID: "incoming-recording",
                checksum: MacSecurityUtilities.sha256Hex(transcriptData),
                size: Int64(transcriptData.count),
                updatedAt: Date(timeIntervalSince1970: 2_500),
                logicalPathToken: traversalPath,
                dataBase64: transcriptData.base64EncodedString()
            ))
        )
        let absolutePath = "/tmp/rokurics-escape/transcript.md"
        let absolute = await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactPutRequest(
                artifactID: LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "incoming-recording", logicalPathToken: absolutePath),
                kind: .transcriptMarkdown,
                ownerID: "incoming-recording",
                checksum: MacSecurityUtilities.sha256Hex(transcriptData),
                size: Int64(transcriptData.count),
                updatedAt: Date(timeIntervalSince1970: 2_500),
                logicalPathToken: absolutePath,
                dataBase64: transcriptData.base64EncodedString()
            ))
        )
        let wrongKindPath = "notes/incoming-recording/transcript.md"
        let wrongKind = await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactPutRequest(
                artifactID: LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "incoming-recording", logicalPathToken: wrongKindPath),
                kind: .transcriptMarkdown,
                ownerID: "incoming-recording",
                checksum: MacSecurityUtilities.sha256Hex(transcriptData),
                size: Int64(transcriptData.count),
                updatedAt: Date(timeIntervalSince1970: 2_500),
                logicalPathToken: wrongKindPath,
                dataBase64: transcriptData.base64EncodedString()
            ))
        )
        let audioPath = "audio/inbox/incoming-recording/audio.m4a"
        let audio = await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactPutRequest(
                artifactID: LocalNetworkSyncArtifactID.make(kind: .audio, ownerID: "incoming-recording", logicalPathToken: audioPath),
                kind: .audio,
                ownerID: "incoming-recording",
                checksum: MacSecurityUtilities.sha256Hex(transcriptData),
                size: Int64(transcriptData.count),
                updatedAt: Date(timeIntervalSince1970: 2_500),
                logicalPathToken: audioPath,
                dataBase64: transcriptData.base64EncodedString()
            ))
        )

        #expect(response.ok)
        #expect(response.disposition == "acceptedNew")
        #expect(response.checksum == MacSecurityUtilities.sha256Hex(transcriptData))
        #expect(String(data: try Data(contentsOf: storedURL), encoding: .utf8) == "incoming transcript")
        #expect(repeated.ok)
        #expect(repeated.disposition == "acceptedExisting")
        #expect(!traversal.ok)
        #expect(traversal.error == "artifact_path_traversal")
        #expect(!absolute.ok)
        #expect(absolute.error == "artifact_absolute_path")
        #expect(!wrongKind.ok)
        #expect(wrongKind.error == "unsupported_artifact_kind")
        #expect(!audio.ok)
        #expect(audio.error == "unsupported_artifact_kind")
    }

    @MainActor
    @Test func localNetworkSyncArtifactPutStoresLargeArtifactInChunks() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default
        )
        let transcriptPath = "transcripts/chunked-recording/transcript.md"
        let transcriptData = Data(repeating: 0x42, count: 4 * 1024 * 1024 + 23)
        let artifactID = LocalNetworkSyncArtifactID.make(
            kind: .transcriptMarkdown,
            ownerID: "chunked-recording",
            logicalPathToken: transcriptPath
        )
        let checksum = MacSecurityUtilities.sha256Hex(transcriptData)
        let chunkSize = 2 * 1024 * 1024
        var offset = 0
        var responses: [LocalNetworkSyncArtifactPutResponse] = []
        while offset < transcriptData.count {
            let end = min(offset + chunkSize, transcriptData.count)
            let chunk = transcriptData.subdata(in: offset..<end)
            let request = LocalNetworkSyncArtifactPutRequest(
                artifactID: artifactID,
                kind: .transcriptMarkdown,
                ownerID: "chunked-recording",
                checksum: checksum,
                size: Int64(transcriptData.count),
                updatedAt: Date(timeIntervalSince1970: 2_500),
                logicalPathToken: transcriptPath,
                dataBase64: chunk.base64EncodedString(),
                offset: Int64(offset),
                chunkSize: chunk.count,
                totalSize: Int64(transcriptData.count),
                isFinalChunk: end == transcriptData.count
            )
            responses.append(await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
                makePairedDevice(),
                requestBody: try JSONEncoder.syncTestEncoder.encode(request)
            ))
            offset = end
        }

        let storedURL = appRootURL.appendingPathComponent(transcriptPath, isDirectory: false)

        #expect(responses.count > 1)
        #expect(responses.dropLast().allSatisfy { $0.ok && $0.disposition == "acceptedChunk" })
        #expect(responses.last?.ok == true)
        #expect(responses.last?.disposition == "acceptedNew")
        #expect(responses.last?.confirmedBytes == Int64(transcriptData.count))
        #expect(try Data(contentsOf: storedURL) == transcriptData)
    }

    @MainActor
    @Test func localNetworkSyncArtifactStatusReportsIncomingTempOffsetAndPutRejectsOffsetMismatch() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default
        )
        let transcriptPath = "transcripts/status-recording/transcript.md"
        let transcriptData = Data(repeating: 0x53, count: 3 * 1024 * 1024 + 9)
        let artifactID = LocalNetworkSyncArtifactID.make(
            kind: .transcriptMarkdown,
            ownerID: "status-recording",
            logicalPathToken: transcriptPath
        )
        let checksum = MacSecurityUtilities.sha256Hex(transcriptData)
        let firstChunk = transcriptData.subdata(in: 0..<(2 * 1024 * 1024))
        let firstPut = await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactPutRequest(
                artifactID: artifactID,
                kind: .transcriptMarkdown,
                ownerID: "status-recording",
                checksum: checksum,
                size: Int64(transcriptData.count),
                updatedAt: Date(timeIntervalSince1970: 2_500),
                logicalPathToken: transcriptPath,
                dataBase64: firstChunk.base64EncodedString(),
                offset: 0,
                chunkSize: firstChunk.count,
                totalSize: Int64(transcriptData.count),
                isFinalChunk: false,
                syncRunID: "mac-status-run"
            ))
        )
        let status = await server.localNetworkSyncArtifactStatusResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactStatusRequest(
                artifactID: artifactID,
                kind: .transcriptMarkdown,
                ownerID: "status-recording",
                logicalPathToken: transcriptPath,
                checksum: checksum,
                size: Int64(transcriptData.count),
                syncRunID: "mac-status-run"
            ))
        )
        let badOffset = await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactPutRequest(
                artifactID: artifactID,
                kind: .transcriptMarkdown,
                ownerID: "status-recording",
                checksum: checksum,
                size: Int64(transcriptData.count),
                updatedAt: Date(timeIntervalSince1970: 2_500),
                logicalPathToken: transcriptPath,
                dataBase64: Data("bad".utf8).base64EncodedString(),
                offset: Int64(firstChunk.count + 1),
                chunkSize: 3,
                totalSize: Int64(transcriptData.count),
                isFinalChunk: false,
                syncRunID: "mac-status-run"
            ))
        )

        #expect(firstPut.ok)
        #expect(firstPut.confirmedBytes == Int64(firstChunk.count))
        #expect(status.ok)
        #expect(status.nextOffset == Int64(firstChunk.count))
        #expect(status.state == .resuming)
        #expect(!badOffset.ok)
        #expect(badOffset.error == "sync_artifact_offset_mismatch")
        #expect(!FileManager.default.fileExists(atPath: appRootURL.appendingPathComponent(transcriptPath, isDirectory: false).path))
    }

    @MainActor
    @Test func localNetworkSyncArtifactResumeIsBoundToContentVersionAndChecksumFailureDeletesTemp() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(
                rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)
            ),
            runtimeConfiguration: .default
        )
        let ownerID = "versioned-resume-recording"
        let logicalPath = "transcripts/\(ownerID)/transcript.md"
        let artifactID = LocalNetworkSyncArtifactID.make(
            kind: .transcriptMarkdown,
            ownerID: ownerID,
            logicalPathToken: logicalPath
        )
        let totalCount = 3 * 1024 * 1024 + 17
        let chunkCount = 2 * 1024 * 1024
        let versionA = Data(repeating: 0x41, count: totalCount)
        let versionB = Data(repeating: 0x42, count: totalCount)
        let checksumA = MacSecurityUtilities.sha256Hex(versionA)
        let checksumB = MacSecurityUtilities.sha256Hex(versionB)
        let firstA = versionA.prefix(chunkCount)
        let firstPutA = await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactPutRequest(
                artifactID: artifactID,
                kind: .transcriptMarkdown,
                ownerID: ownerID,
                checksum: checksumA,
                size: Int64(totalCount),
                updatedAt: Date(timeIntervalSince1970: 2_500),
                logicalPathToken: logicalPath,
                dataBase64: Data(firstA).base64EncodedString(),
                offset: 0,
                chunkSize: firstA.count,
                totalSize: Int64(totalCount),
                isFinalChunk: false
            ))
        )
        let statusForB = await server.localNetworkSyncArtifactStatusResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactStatusRequest(
                artifactID: artifactID,
                kind: .transcriptMarkdown,
                ownerID: ownerID,
                logicalPathToken: logicalPath,
                checksum: checksumB,
                size: Int64(totalCount)
            ))
        )

        let firstB = versionB.prefix(chunkCount)
        let firstPutB = await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactPutRequest(
                artifactID: artifactID,
                kind: .transcriptMarkdown,
                ownerID: ownerID,
                checksum: checksumB,
                size: Int64(totalCount),
                updatedAt: Date(timeIntervalSince1970: 2_501),
                logicalPathToken: logicalPath,
                dataBase64: Data(firstB).base64EncodedString(),
                offset: 0,
                chunkSize: firstB.count,
                totalSize: Int64(totalCount),
                isFinalChunk: false
            ))
        )
        let statusForAAfterBStarted = await server.localNetworkSyncArtifactStatusResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactStatusRequest(
                artifactID: artifactID,
                kind: .transcriptMarkdown,
                ownerID: ownerID,
                logicalPathToken: logicalPath,
                checksum: checksumA,
                size: Int64(totalCount)
            ))
        )

        let intentionallyWrongChecksum = MacSecurityUtilities.sha256Hex(Data(repeating: 0x43, count: totalCount))
        let badFirstPut = await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactPutRequest(
                artifactID: artifactID,
                kind: .transcriptMarkdown,
                ownerID: ownerID,
                checksum: intentionallyWrongChecksum,
                size: Int64(totalCount),
                updatedAt: Date(timeIntervalSince1970: 2_502),
                logicalPathToken: logicalPath,
                dataBase64: Data(firstB).base64EncodedString(),
                offset: 0,
                chunkSize: firstB.count,
                totalSize: Int64(totalCount),
                isFinalChunk: false
            ))
        )
        let remainingB = versionB.suffix(from: chunkCount)
        let badFinalPut = await server.localNetworkSyncArtifactPutResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactPutRequest(
                artifactID: artifactID,
                kind: .transcriptMarkdown,
                ownerID: ownerID,
                checksum: intentionallyWrongChecksum,
                size: Int64(totalCount),
                updatedAt: Date(timeIntervalSince1970: 2_502),
                logicalPathToken: logicalPath,
                dataBase64: Data(remainingB).base64EncodedString(),
                offset: Int64(chunkCount),
                chunkSize: remainingB.count,
                totalSize: Int64(totalCount),
                isFinalChunk: true
            ))
        )
        let statusAfterChecksumFailure = await server.localNetworkSyncArtifactStatusResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: try JSONEncoder.syncTestEncoder.encode(LocalNetworkSyncArtifactStatusRequest(
                artifactID: artifactID,
                kind: .transcriptMarkdown,
                ownerID: ownerID,
                logicalPathToken: logicalPath,
                checksum: intentionallyWrongChecksum,
                size: Int64(totalCount)
            ))
        )

        #expect(firstPutA.ok)
        #expect(firstPutA.confirmedBytes == Int64(chunkCount))
        #expect(statusForB.state == .pending)
        #expect(statusForB.confirmedBytes == 0)
        #expect(firstPutB.ok)
        #expect(statusForAAfterBStarted.state == .pending)
        #expect(statusForAAfterBStarted.confirmedBytes == 0)
        #expect(badFirstPut.ok)
        #expect(!badFinalPut.ok)
        #expect(badFinalPut.error == "sync_artifact_checksum_mismatch")
        #expect(statusAfterChecksumFailure.state == .pending)
        #expect(statusAfterChecksumFailure.confirmedBytes == 0)
    }

    @MainActor
    @Test func localNetworkSyncApplyMetadataMergesStudyMetadataWithoutTouchingAudio() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let fileStore = MacRecordingFileStore(rootURL: appRootURL)
        let recordingDirectory = try await saveInboxRecording(id: "apply-metadata-recording", title: "旧标题", store: fileStore)
        let audioURL = recordingDirectory.appendingPathComponent("audio.m4a", isDirectory: false)
        let studyStore = StudyLibraryStore(rootURL: appRootURL, recordingFileStore: fileStore, listenForInboxChanges: false)
        var item = try #require(studyStore.item(recordingID: "apply-metadata-recording"))
        item.title = "同步后的标题"
        item.updatedAt = item.updatedAt.addingTimeInterval(90)
        item.modifiedByDeviceID = "iphone-01"
        let manifest = StudyLibrarySyncManifest.make(deviceID: "iphone-01", items: [item], folders: [])
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default
        )
        let response = try await server.localNetworkSyncApplyMetadataResponseForVerifiedDevice(
            makePairedDevice(),
            requestBody: JSONEncoder.syncTestEncoder.encode(StudyLibrarySyncManifestRequest(manifest: manifest))
        )
        let reloaded = StudyLibraryStore(rootURL: appRootURL, recordingFileStore: fileStore, listenForInboxChanges: false)

        #expect(response.ok)
        #expect(response.applyResult?.appliedItemCount == 1)
        #expect(reloaded.item(recordingID: "apply-metadata-recording")?.title == "同步后的标题")
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }
}

struct CanonicalManifestRecordingsApplyTests {
    @MainActor
    @Test func canonicalFullSyncServerApplyConsumesManifestRecordingsAndInventoryExposesMetadataOnly() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let canonical = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve().effectiveConfiguration
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default,
            canonicalSyncRuntimeConfiguration: canonical.syncRuntimeConfiguration,
            canonicalApplyRuntimeConfiguration: canonical.applyRuntimeConfiguration,
            canonicalExistenceApplyRuntimeConfiguration: canonical.existenceApplyRuntimeConfiguration
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-device",
            generatedAt: Date(timeIntervalSince1970: 8_480),
            items: [],
            folders: [],
            recordings: [Self.recordingFact()]
        )

        let response = try await server.localNetworkSyncApplyMetadataResponseForVerifiedDevice(
            makePairedDevice(id: "iphone-device"),
            requestBody: JSONEncoder.syncTestEncoder.encode(StudyLibrarySyncManifestRequest(manifest: manifest))
        )
        let port = MacCanonicalRecordingExistenceLedgerPort(rootURL: appRootURL)
        let ledgerRecord = try port.readRecord(objectID: "manifest-recording-01")
        let record = try #require(ledgerRecord)
        let inventoryResponse = await server.localNetworkSyncInventoryResponseForVerifiedDevice(
            makePairedDevice(id: "iphone-device"),
            syncRunID: "v8-48-inventory"
        )
        let inventory = try #require(inventoryResponse.inventory)
        let inventoryRecording = try #require(inventory.recordings.first { $0.recordingID == "manifest-recording-01" })
        let inboxAudioURL = appRootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .appendingPathComponent("manifest-recording-01", isDirectory: true)
            .appendingPathComponent("audio.m4a", isDirectory: false)
        let receiveJSONURL = inboxAudioURL
            .deletingLastPathComponent()
            .appendingPathComponent("receive.json", isDirectory: false)

        #expect(response.ok)
        #expect(response.applyResult?.failedChanges == 0)
        #expect(record.objectID == "manifest-recording-01")
        #expect(record.metadataHash == "manifest-recording-metadata-hash")
        #expect(record.audioAvailable == false)
        #expect(record.audioHash == nil)
        #expect(record.audioByteSize == nil)
        #expect(FileManager.default.fileExists(atPath: inboxAudioURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: receiveJSONURL.path) == false)
        #expect(inventoryRecording.audioAvailable == false)
        #expect(inventoryRecording.audioChecksum == nil)
        #expect(inventoryRecording.audioSize == nil)
        #expect(inventoryRecording.audioLogicalPathToken == nil)
        #expect(inventoryRecording.receiveStatus == "canonicalMetadataOnly")
    }

    @MainActor
    @Test func defaultServerApplyDoesNotConsumeManifestRecordings() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-device",
            generatedAt: Date(timeIntervalSince1970: 8_480),
            items: [],
            folders: [],
            recordings: [Self.recordingFact()]
        )

        let response = try await server.localNetworkSyncApplyMetadataResponseForVerifiedDevice(
            makePairedDevice(id: "iphone-device"),
            requestBody: JSONEncoder.syncTestEncoder.encode(StudyLibrarySyncManifestRequest(manifest: manifest))
        )
        let port = MacCanonicalRecordingExistenceLedgerPort(rootURL: appRootURL)

        #expect(response.ok)
        #expect(try port.loadRecords().isEmpty)
    }

    @MainActor
    @Test func malformedRecordingFactIsBlockedWithoutPreventingValidFacts() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let canonical = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve().effectiveConfiguration
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default,
            canonicalSyncRuntimeConfiguration: canonical.syncRuntimeConfiguration,
            canonicalApplyRuntimeConfiguration: canonical.applyRuntimeConfiguration,
            canonicalExistenceApplyRuntimeConfiguration: canonical.existenceApplyRuntimeConfiguration
        )
        let malformed = Self.recordingFact(recordingID: "malformed-recording", metadataHash: nil)
        let valid = Self.recordingFact(recordingID: "valid-recording", metadataHash: "valid-metadata-hash")
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-device",
            generatedAt: Date(timeIntervalSince1970: 8_481),
            items: [],
            folders: [],
            recordings: [malformed, valid]
        )

        let response = try await server.localNetworkSyncApplyMetadataResponseForVerifiedDevice(
            makePairedDevice(id: "iphone-device"),
            requestBody: JSONEncoder.syncTestEncoder.encode(StudyLibrarySyncManifestRequest(manifest: manifest))
        )
        let port = MacCanonicalRecordingExistenceLedgerPort(rootURL: appRootURL)

        #expect(!response.ok)
        #expect((response.applyResult?.failedChanges ?? 0) > 0)
        #expect(response.error == "sync_apply_metadata_partial_failure")
        let malformedRecord = try port.readRecord(objectID: "malformed-recording")
        let validRecord = try port.readRecord(objectID: "valid-recording")
        #expect(malformedRecord == nil)
        #expect(validRecord?.metadataHash == "valid-metadata-hash")
    }

    @MainActor
    @Test func repeatedApplyNoOpsAndMetadataHashChangeUpdatesRecord() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let canonical = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve().effectiveConfiguration
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default,
            canonicalSyncRuntimeConfiguration: canonical.syncRuntimeConfiguration,
            canonicalApplyRuntimeConfiguration: canonical.applyRuntimeConfiguration,
            canonicalExistenceApplyRuntimeConfiguration: canonical.existenceApplyRuntimeConfiguration
        )
        let first = StudyLibrarySyncManifest.make(
            deviceID: "iphone-device",
            generatedAt: Date(timeIntervalSince1970: 8_482),
            items: [],
            folders: [],
            recordings: [Self.recordingFact(metadataHash: "first-metadata-hash")]
        )
        let second = StudyLibrarySyncManifest.make(
            deviceID: "iphone-device",
            generatedAt: Date(timeIntervalSince1970: 8_483),
            items: [],
            folders: [],
            recordings: [Self.recordingFact(metadataHash: "second-metadata-hash")]
        )

        _ = try await server.localNetworkSyncApplyMetadataResponseForVerifiedDevice(
            makePairedDevice(id: "iphone-device"),
            requestBody: JSONEncoder.syncTestEncoder.encode(StudyLibrarySyncManifestRequest(manifest: first))
        )
        _ = try await server.localNetworkSyncApplyMetadataResponseForVerifiedDevice(
            makePairedDevice(id: "iphone-device"),
            requestBody: JSONEncoder.syncTestEncoder.encode(StudyLibrarySyncManifestRequest(manifest: first))
        )
        _ = try await server.localNetworkSyncApplyMetadataResponseForVerifiedDevice(
            makePairedDevice(id: "iphone-device"),
            requestBody: JSONEncoder.syncTestEncoder.encode(StudyLibrarySyncManifestRequest(manifest: second))
        )
        let port = MacCanonicalRecordingExistenceLedgerPort(rootURL: appRootURL)

        let record = try port.readRecord(objectID: "manifest-recording-01")
        #expect(record?.metadataHash == "second-metadata-hash")
    }

    @MainActor
    @Test func recordingTombstoneDoesNotReturnConflictOrReappearFromExistenceLedger() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let appRootURL = scratchURL.appendingPathComponent("MacApp", isDirectory: true)
        let canonical = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve().effectiveConfiguration
        let server = makeSyncServer(
            rootURL: scratchURL,
            gitStore: nil,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: scratchURL.appendingPathComponent("SyncState", isDirectory: true)),
            runtimeConfiguration: .default,
            canonicalSyncRuntimeConfiguration: canonical.syncRuntimeConfiguration,
            canonicalApplyRuntimeConfiguration: canonical.applyRuntimeConfiguration,
            canonicalExistenceApplyRuntimeConfiguration: canonical.existenceApplyRuntimeConfiguration
        )
        let recordingID = "tombstoned-recording"
        var activeItem = StudyItemMetadata(
            recordingID: recordingID,
            title: "Active metadata",
            createdAt: Date(timeIntervalSince1970: 8_500),
            duration: 12,
            updatedAt: Date(timeIntervalSince1970: 8_510),
            modifiedByDeviceID: "iphone-device"
        )
        let activeManifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-device",
            generatedAt: Date(timeIntervalSince1970: 8_511),
            items: [activeItem],
            folders: [],
            recordings: [Self.recordingFact(recordingID: recordingID, metadataHash: "active-hash")]
        )
        let activeResponse = try await server.localNetworkSyncApplyMetadataResponseForVerifiedDevice(
            makePairedDevice(id: "iphone-device"),
            requestBody: JSONEncoder.syncTestEncoder.encode(StudyLibrarySyncManifestRequest(manifest: activeManifest))
        )
        let port = MacCanonicalRecordingExistenceLedgerPort(rootURL: appRootURL)
        #expect(activeResponse.ok)
        #expect(try port.readRecord(objectID: recordingID) != nil)

        activeItem.isTrashed = true
        activeItem.trashedAt = Date(timeIntervalSince1970: 8_520)
        activeItem.updatedAt = Date(timeIntervalSince1970: 8_520)
        var tombstoneRecording = Self.recordingFact(recordingID: recordingID, metadataHash: nil)
        tombstoneRecording.deleted = true
        tombstoneRecording.tombstone = true
        tombstoneRecording.updatedAt = activeItem.updatedAt
        let tombstoneManifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-device",
            generatedAt: Date(timeIntervalSince1970: 8_521),
            items: [activeItem],
            folders: [],
            tombstones: [
                StudyLibrarySyncTombstone(
                    id: "item:\(activeItem.itemID)",
                    entityKind: .item,
                    entityID: activeItem.itemID,
                    operation: .trash,
                    updatedAt: activeItem.updatedAt,
                    modifiedByDeviceID: "iphone-device"
                )
            ],
            recordings: [tombstoneRecording]
        )

        let firstTombstoneResponse = try await server.localNetworkSyncApplyMetadataResponseForVerifiedDevice(
            makePairedDevice(id: "iphone-device"),
            requestBody: JSONEncoder.syncTestEncoder.encode(StudyLibrarySyncManifestRequest(manifest: tombstoneManifest))
        )
        let secondTombstoneResponse = try await server.localNetworkSyncApplyMetadataResponseForVerifiedDevice(
            makePairedDevice(id: "iphone-device"),
            requestBody: JSONEncoder.syncTestEncoder.encode(StudyLibrarySyncManifestRequest(manifest: tombstoneManifest))
        )
        let inventoryResponse = await server.localNetworkSyncInventoryResponseForVerifiedDevice(
            makePairedDevice(id: "iphone-device"),
            syncRunID: "tombstone-inventory"
        )
        let inventoryRecording = try #require(inventoryResponse.inventory?.recordings.first { $0.recordingID == recordingID })

        #expect(firstTombstoneResponse.ok)
        #expect(firstTombstoneResponse.applyResult?.failedChanges == 0)
        #expect(firstTombstoneResponse.error == nil)
        #expect(secondTombstoneResponse.ok)
        #expect(secondTombstoneResponse.applyResult?.failedChanges == 0)
        #expect(try port.readRecord(objectID: recordingID) == nil)
        #expect(inventoryRecording.deleted)
        #expect(inventoryRecording.tombstone == true)
        #expect(inventoryRecording.metadataHash != "active-hash")
    }

    private static func recordingFact(
        recordingID: String = "manifest-recording-01",
        metadataHash: String? = "manifest-recording-metadata-hash"
    ) -> LocalNetworkSyncRecordingEntry {
        LocalNetworkSyncRecordingEntry(
            recordingID: recordingID,
            metadataHash: metadataHash,
            audioAvailable: true,
            audioChecksum: String(repeating: "a", count: 64),
            audioSize: 16,
            uploadLedgerState: nil,
            receiveStatus: nil,
            processingStatus: nil,
            updatedAt: Date(timeIntervalSince1970: 8_480),
            deleted: false,
            title: "Manifest Recording",
            createdAt: Date(timeIntervalSince1970: 8_470),
            tombstone: false,
            audioAvailability: .local,
            uploadStatus: nil,
            transcriptionStatus: nil,
            noteStatus: nil,
            sourceDeviceID: "iphone-device",
            artifactRefs: nil,
            audioLogicalPathToken: "Recordings/\(recordingID).m4a"
        )
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

private final class LockedConnectionDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SecureConnectionDiagnosticEvent] = []

    func append(_ event: SecureConnectionDiagnosticEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    func events() -> [SecureConnectionDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@MainActor
private func makeSyncServer(
    rootURL: URL,
    gitStore: GitBackedStudyMetadataStore?,
    syncStateStore: StudyLibrarySyncStateStore,
    runtimeConfiguration: StudyLibrarySyncRuntimeConfiguration,
    canonicalSyncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration = .disabled,
    canonicalApplyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration = .disabled,
    canonicalExistenceApplyRuntimeConfiguration: CanonicalExistenceApplyRuntimeConfiguration = .disabled,
    canonicalReadRuntimeConfiguration: CanonicalReadRuntimeConfiguration = .disabled,
    canonicalKernelMode: CanonicalKernelSwitchMode = .oldKernel,
    injectCanonicalExistenceApplyPort: Bool = true,
    onConnectionDiagnostic: @escaping SecureLocalHTTPSServer.ConnectionDiagnosticHandler = { _ in }
) -> SecureLocalHTTPSServer {
    let appRootURL = rootURL.appendingPathComponent("MacApp", isDirectory: true)
    let recordingFileStore = MacRecordingFileStore(rootURL: appRootURL)
    let existenceApplyPort = injectCanonicalExistenceApplyPort
        ? MacCanonicalRecordingExistenceLedgerPort(rootURL: appRootURL)
        : nil
    let studyLibraryStore = StudyLibraryStore(
        rootURL: appRootURL,
        recordingFileStore: recordingFileStore,
        listenForInboxChanges: false,
        canonicalExistenceApplyRuntimeConfiguration: canonicalExistenceApplyRuntimeConfiguration,
        canonicalRecordingExistenceApplyPort: existenceApplyPort
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
        onRecordingAccepted: { _, _ in },
        onConnectionDiagnostic: onConnectionDiagnostic,
        canonicalSyncRuntimeConfiguration: canonicalSyncRuntimeConfiguration,
        canonicalApplyRuntimeConfiguration: canonicalApplyRuntimeConfiguration,
        canonicalExistenceApplyRuntimeConfiguration: canonicalExistenceApplyRuntimeConfiguration,
        canonicalReadRuntimeConfiguration: canonicalReadRuntimeConfiguration,
        canonicalKernelMode: canonicalKernelMode,
        canonicalRecordingExistenceApplyPort: existenceApplyPort
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

private func signedSyncHeaders(
    device: PairedDevice,
    path: String,
    body: Data,
    nonce: String
) throws -> [String: String] {
    let bodyHash = MacSecurityUtilities.sha256Hex(body)
    let timestamp = "1000"
    let payload = ["POST", path, timestamp, nonce, bodyHash].joined(separator: "\n")
    let signature = try #require(MacSecurityUtilities.hmacSHA256Base64URL(
        message: payload,
        secretBase64URL: device.sharedSecretBase64URL
    ))

    return [
        "Content-Type": "application/json",
        "X-Rokurics-Device-ID": device.id,
        "X-Rokurics-Timestamp": timestamp,
        "X-Rokurics-Nonce": nonce,
        "X-Rokurics-Body-SHA256": bodyHash,
        "X-Rokurics-Signature": signature
    ]
}

private extension JSONEncoder {
    static var syncTestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
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
) async throws -> URL {
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
    _ = try await store.saveAudio(body: Data("audio".utf8), recordingID: id, requestedFileName: "\(id).m4a", sourceDevice: sourceDevice)
    return receiveResult.directoryURL
}
