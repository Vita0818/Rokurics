//
//  RokuricsTests.swift
//  RokuricsTests
//
//  Created by Vita on 2026/5/8.
//

import Testing
import Foundation
@testable import Rokurics

@MainActor
struct RokuricsTests {
    @Test func localNetworkBusinessSignatureV2IsNormalizedVersionedAndCustomKeyExplicit() {
        let decomposedTitle = "Cafe\u{301} lesson"
        let firstTags = [
            LocalNetworkBusinessTagV2(namespace: " Topic ", value: " MATRICES ", displayName: " Matrix lesson "),
            LocalNetworkBusinessTagV2(namespace: "Subject", value: "MATH", displayName: "Mathematics")
        ]
        let secondTags = [
            LocalNetworkBusinessTagV2(namespace: "subject", value: "math", displayName: "Mathematics"),
            LocalNetworkBusinessTagV2(namespace: "topic", value: "matrices", displayName: "Matrix lesson")
        ]
        let first = LocalNetworkRecordingBusinessFieldsV2(
            recordingID: " recording-01 ",
            title: decomposedTitle,
            filing: LocalNetworkBusinessFilingV2(type: " Class ", subject: " Algebra "),
            tags: firstTags,
            isDeleted: false,
            customProperties: LocalNetworkBusinessSignatureV2.filteredBusinessCustomProperties([
                "local.audioPath": "Recordings/recording-01.m4a",
                "sync.status": "uploading"
            ])
        )
        let second = LocalNetworkRecordingBusinessFieldsV2(
            recordingID: "recording-01",
            title: "Caf\u{e9} lesson",
            filing: LocalNetworkBusinessFilingV2(type: "Class", subject: "Algebra"),
            tags: secondTags,
            isDeleted: false,
            customProperties: []
        )

        let firstSignature = LocalNetworkBusinessSignatureV2.recording(first)
        let secondSignature = LocalNetworkBusinessSignatureV2.recording(second)
        #expect(first == second)
        #expect(firstSignature == secondSignature)
        #expect(firstSignature.hasPrefix(LocalNetworkBusinessSignatureV2.wirePrefix))
        #expect(LocalNetworkBusinessSignatureV2.isCurrentVersion(firstSignature))

        let admittedKeys: Set<String> = ["business.priority"]
        let highPriority = LocalNetworkRecordingBusinessFieldsV2(
            recordingID: "recording-01",
            title: "Caf\u{e9} lesson",
            filing: second.filing,
            tags: second.tags,
            isDeleted: false,
            customProperties: LocalNetworkBusinessSignatureV2.filteredBusinessCustomProperties(
                ["BUSINESS.PRIORITY": " high ", "local.audioPath": "one"],
                explicitBusinessKeys: admittedKeys
            )
        )
        let sameHighPriority = LocalNetworkRecordingBusinessFieldsV2(
            recordingID: "recording-01",
            title: "Caf\u{e9} lesson",
            filing: second.filing,
            tags: second.tags,
            isDeleted: false,
            customProperties: LocalNetworkBusinessSignatureV2.filteredBusinessCustomProperties(
                ["business.priority": "high", "local.audioPath": "two"],
                explicitBusinessKeys: admittedKeys
            )
        )
        let lowPriority = LocalNetworkRecordingBusinessFieldsV2(
            recordingID: "recording-01",
            title: "Caf\u{e9} lesson",
            filing: second.filing,
            tags: second.tags,
            isDeleted: false,
            customProperties: [LocalNetworkBusinessCustomPropertyV2(key: "business.priority", value: "low")]
        )
        #expect(LocalNetworkBusinessSignatureV2.recording(highPriority) == LocalNetworkBusinessSignatureV2.recording(sameHighPriority))
        #expect(LocalNetworkBusinessSignatureV2.recording(highPriority) != LocalNetworkBusinessSignatureV2.recording(lowPriority))
    }

    @Test func iphoneBusinessSignatureMappingIgnoresDeviceLocalVariants() {
        let filing = StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵")
        let local = StudyItemMetadata(
            itemID: "item_recording_business-01",
            kind: .recordingBundle,
            title: "矩阵复习",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            filing: filing,
            tags: [
                StudyTag(id: "iphone-topic-id", namespace: "topic", value: "特征值", displayName: "特征值", createdAt: Date(timeIntervalSince1970: 101)),
                StudyTag(id: "iphone-subject-id", namespace: "subject", value: "数学", displayName: "数学", createdAt: Date(timeIntervalSince1970: 102))
            ],
            folderIDs: ["iphone-derived-folder"],
            customProperties: ["local.audioBookmark": "iphone-only"],
            recordingID: "business-01",
            sanitizedRecordingID: "iphone-sanitized-id",
            duration: 42,
            audioRelativePath: "Recordings/business-01.m4a",
            receiveRelativePath: "Receives/business-01.json",
            transcriptRelativePath: "Transcripts/business-01.json",
            transcriptMarkdownRelativePath: "Transcripts/business-01.md",
            noteRelativePath: "Notes/business-01.md",
            transcriptionStatus: "running",
            noteStatus: "waiting",
            sourceDescription: "iPhone microphone",
            modifiedByDeviceID: "iphone-01",
            syncConflictStatus: "local-warning"
        )
        let peerLocalVariant = StudyItemMetadata(
            itemID: "item_recording_business-01",
            kind: .recordingBundle,
            title: "矩阵复习",
            createdAt: Date(timeIntervalSince1970: 9_100),
            updatedAt: Date(timeIntervalSince1970: 9_200),
            filing: filing,
            tags: [
                StudyTag(id: "mac-subject-id", namespace: "SUBJECT", value: "数学", displayName: "数学", createdAt: Date(timeIntervalSince1970: 9_102)),
                StudyTag(id: "mac-topic-id", namespace: "TOPIC", value: "特征值", displayName: "特征值", createdAt: Date(timeIntervalSince1970: 9_101))
            ],
            folderIDs: ["mac-derived-folder-a", "mac-derived-folder-b"],
            customProperties: ["syncedMetadataOnly": "true"],
            recordingID: "business-01",
            sanitizedRecordingID: "mac-sanitized-id",
            duration: 43,
            audioRelativePath: "audio/inbox/business-01/audio.m4a",
            receiveRelativePath: "audio/inbox/business-01/receive.json",
            transcriptRelativePath: "mac/transcript.json",
            transcriptMarkdownRelativePath: "mac/transcript.md",
            noteRelativePath: "mac/note.md",
            transcriptionStatus: "completed",
            noteStatus: "completed",
            sourceDescription: "Mac inbox",
            modifiedByDeviceID: "mac-01",
            syncConflictStatus: "remote-warning"
        )
        let expected = LocalNetworkStudyItemBusinessFieldsV2(
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

        #expect(local.localNetworkStudyItemBusinessFieldsV2 == expected)
        #expect(peerLocalVariant.localNetworkStudyItemBusinessFieldsV2 == expected)
        #expect(local.localNetworkStudyItemBusinessSignatureV2 == peerLocalVariant.localNetworkStudyItemBusinessSignatureV2)
        #expect(local.localNetworkRecordingBusinessSignatureV2 == peerLocalVariant.localNetworkRecordingBusinessSignatureV2)
        #expect(local.localNetworkStudyItemBusinessSignatureV2 == LocalNetworkBusinessSignatureV2.studyItem(expected))

        var businessChange = peerLocalVariant
        businessChange.title = "矩阵复习（更新）"
        #expect(local.localNetworkStudyItemBusinessSignatureV2 != businessChange.localNetworkStudyItemBusinessSignatureV2)
        #expect(local.localNetworkRecordingBusinessSignatureV2 != businessChange.localNetworkRecordingBusinessSignatureV2)
    }

    @Test func iphoneBusinessMergeOverlaysPeerBusinessFieldsAndPreservesLocalState() throws {
        let localTagDate = Date(timeIntervalSince1970: 111)
        let local = StudyItemMetadata(
            itemID: "item_recording_merge-01",
            kind: .recordingBundle,
            title: "旧标题",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            filing: StudyFilingPath(type: "课堂", subject: "旧课程"),
            tags: [StudyTag(id: "local-tag-id", namespace: "topic", value: "矩阵", displayName: "旧显示名", createdAt: localTagDate)],
            folderIDs: ["local-derived-folder"],
            customProperties: ["local.audioBookmark": "keep", "business.priority": "old"],
            recordingID: "merge-01",
            sanitizedRecordingID: "local-sanitized",
            duration: 12,
            audioRelativePath: "Recordings/merge-01.m4a",
            receiveRelativePath: "Receives/merge-01.json",
            transcriptRelativePath: "Transcripts/merge-01.json",
            transcriptMarkdownRelativePath: "Transcripts/merge-01.md",
            noteRelativePath: "Notes/merge-01.md",
            transcriptionStatus: "local-running",
            noteStatus: "local-waiting",
            noteSections: [RecordingNoteSectionRecord(index: 0, sourceStart: 0, sourceEnd: 5, status: "local", sectionNoteRelativePath: "Notes/section.md")],
            sourceDescription: "local microphone",
            modifiedByDeviceID: "iphone-01",
            syncConflictStatus: "keep-local-conflict"
        )
        let remoteFiling = StudyFilingPath(type: "复习", subject: "新课程", chapter: "新章节")
        let remoteUpdatedAt = Date(timeIntervalSince1970: 500)
        let remote = StudyItemMetadata(
            itemID: local.itemID,
            kind: .recordingBundle,
            title: "新标题",
            createdAt: Date(timeIntervalSince1970: 400),
            updatedAt: remoteUpdatedAt,
            filing: remoteFiling,
            tags: [
                StudyTag(id: "remote-tag-id", namespace: "topic", value: "矩阵", displayName: "新显示名", createdAt: Date(timeIntervalSince1970: 401)),
                StudyTag(id: "remote-new-id", namespace: "level", value: "重点", displayName: "重点", createdAt: Date(timeIntervalSince1970: 402))
            ],
            folderIDs: ["remote-derived-folder"],
            customProperties: ["business.priority": "new", "remote.localKey": "drop"],
            recordingID: "merge-01",
            sanitizedRecordingID: "remote-sanitized",
            duration: 99,
            audioRelativePath: "audio/inbox/merge-01/audio.m4a",
            receiveRelativePath: "audio/inbox/merge-01/receive.json",
            transcriptRelativePath: "remote/transcript.json",
            transcriptMarkdownRelativePath: "remote/transcript.md",
            noteRelativePath: "remote/note.md",
            transcriptionStatus: "remote-completed",
            noteStatus: "remote-completed",
            sourceDescription: "remote inbox",
            isTrashed: true,
            trashedAt: Date(timeIntervalSince1970: 490),
            modifiedByDeviceID: "mac-01",
            syncConflictStatus: "remote-conflict"
        )

        let merged = local.mergingRemoteBusinessFieldsV2(
            from: remote,
            explicitBusinessCustomPropertyKeys: ["business.priority"]
        )
        #expect(merged.title == remote.title)
        #expect(merged.filing == remoteFiling)
        #expect(merged.folderIDs == StudyItemMetadata.defaultFolderIDs(for: remoteFiling))
        #expect(merged.tags.first { $0.namespace == "topic" }?.displayName == "新显示名")
        #expect(merged.tags.first { $0.namespace == "topic" }?.id == "local-tag-id")
        #expect(merged.tags.first { $0.namespace == "topic" }?.createdAt == localTagDate)
        #expect(merged.tags.first { $0.namespace == "level" }?.createdAt == nil)
        #expect(merged.customProperties == ["local.audioBookmark": "keep", "business.priority": "new"])
        #expect(merged.isTrashed)
        #expect(merged.trashedAt == remote.trashedAt)
        #expect(merged.updatedAt == remoteUpdatedAt)
        #expect(merged.modifiedByDeviceID == "mac-01")

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
        #expect(merged.noteSections == local.noteSections)
        #expect(merged.sourceDescription == local.sourceDescription)
        #expect(merged.syncConflictStatus == local.syncConflictStatus)

        let localFolder = StudyFolderMetadata(
            folderID: "folder-merge-01",
            name: "旧文件夹",
            level: .subject,
            path: StudyFilingPath(type: "课堂", subject: "旧课程"),
            parentFolderID: "local-parent",
            childFolderIDs: ["local-child"],
            itemIDs: [local.itemID],
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            colorToken: .blue,
            customProperties: ["local.finderBookmark": "keep", "business.priority": "old"],
            modifiedByDeviceID: "iphone-01",
            syncConflictStatus: "local-folder-conflict"
        )
        let remoteFolder = StudyFolderMetadata(
            folderID: localFolder.folderID,
            name: "新文件夹",
            level: .chapter,
            path: remoteFiling,
            parentFolderID: "remote-parent",
            childFolderIDs: ["remote-child"],
            itemIDs: ["remote-item"],
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: remoteUpdatedAt,
            colorToken: .green,
            isTrashed: true,
            trashedAt: Date(timeIntervalSince1970: 490),
            customProperties: ["business.priority": "new", "remote.localKey": "drop"],
            modifiedByDeviceID: "mac-01",
            syncConflictStatus: "remote-folder-conflict"
        )
        let mergedFolder = localFolder.mergingRemoteBusinessFieldsV2(
            from: remoteFolder,
            explicitBusinessCustomPropertyKeys: ["business.priority"]
        )
        #expect(mergedFolder.name == remoteFolder.name)
        #expect(mergedFolder.level == remoteFolder.level)
        #expect(mergedFolder.path == remoteFolder.path)
        #expect(mergedFolder.parentFolderID == remoteFolder.parentFolderID)
        #expect(mergedFolder.colorToken == remoteFolder.colorToken)
        #expect(mergedFolder.isTrashed)
        #expect(mergedFolder.trashedAt == remoteFolder.trashedAt)
        #expect(mergedFolder.updatedAt == remoteUpdatedAt)
        #expect(mergedFolder.modifiedByDeviceID == "mac-01")
        #expect(mergedFolder.createdAt == localFolder.createdAt)
        #expect(mergedFolder.childFolderIDs == localFolder.childFolderIDs)
        #expect(mergedFolder.itemIDs == localFolder.itemIDs)
        #expect(mergedFolder.customProperties == ["local.finderBookmark": "keep", "business.priority": "new"])
        #expect(mergedFolder.syncConflictStatus == localFolder.syncConflictStatus)
    }

    @Test func sharedSyncCorePlansObjectDiffsWithoutFileTypeBranches() {
        let date = Date(timeIntervalSince1970: 10)
        let localAudio = SyncObject(
            objectID: "recordingAudio:shared-core-audio",
            objectKind: LocalNetworkSyncObjectKind.recordingAudio.rawValue,
            ownerID: "shared-core-audio",
            displayTitle: "Shared core audio",
            fileName: "audio.m4a",
            logicalName: "audio.m4a",
            sha256: nil,
            size: 5,
            updatedAt: date,
            tombstone: false,
            deleted: false,
            sourceDeviceID: "iphone-01",
            logicalPathToken: nil,
            availability: .local,
            transferState: nil,
            transferProgress: nil,
            conflictStatus: nil,
            autoDownloadAllowed: false,
            metadata: [:]
        )
        var peerMissingAudio = localAudio
        peerMissingAudio.size = nil
        peerMissingAudio.availability = .missing
        peerMissingAudio.sourceDeviceID = "mac-01"

        let local = SyncInventory.make(
            sourceDeviceID: "iphone-01",
            sourcePlatform: "iPhone",
            generatedAt: date,
            inventoryRevision: "local",
            objects: [localAudio]
        )
        let peer = SyncInventory.make(
            sourceDeviceID: "mac-01",
            sourcePlatform: "Mac",
            generatedAt: date,
            inventoryRevision: "peer",
            objects: [peerMissingAudio]
        )

        let plan = SyncDiffPlanner().plan(local: local, peer: peer, lastSuccessfulSyncAt: nil)

        #expect(plan.uploadObjectActions.map(\.objectID) == ["recordingAudio:shared-core-audio"])
        #expect(plan.uploadObjectActions.first?.reason == "local_object_more_complete")
    }

    @Test func localNetworkInventoryBridgesToSharedSyncCoreObjects() {
        let generatedAt = Date(timeIntervalSince1970: 11)
        let recording = LocalNetworkSyncRecordingEntry(
            recordingID: "shared-core-recording",
            metadataHash: "metadata-hash",
            audioAvailable: true,
            audioChecksum: nil,
            audioSize: 128,
            uploadLedgerState: nil,
            receiveStatus: nil,
            processingStatus: nil,
            updatedAt: generatedAt,
            deleted: false,
            title: "Shared core recording",
            createdAt: generatedAt,
            tombstone: false,
            audioAvailability: .local,
            uploadStatus: "localOnly",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            sourceDeviceID: "iphone-01",
            artifactRefs: nil
        )
        let inventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-01",
                deviceName: "iPhone",
                platform: .iPhone,
                generatedAt: generatedAt,
                lastKnownPeerRevision: "peer-rev",
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [recording]
        )

        let coreInventory = inventory.syncCoreInventory
        let metadataObject = coreInventory.objects.first { $0.objectKind == LocalNetworkSyncObjectKind.recordingMetadata.rawValue }
        let audioObject = coreInventory.objects.first { $0.objectID == "recordingAudio:shared-core-recording" }

        #expect(coreInventory.hasValidInventoryHash)
        #expect(coreInventory.lastKnownPeerRevision == "peer-rev")
        #expect(metadataObject?.ownerID == "shared-core-recording")
        #expect(audioObject?.size == 128)
        #expect(audioObject?.autoDownloadAllowed == false)
    }

    @Test func uploadDecisionBlockersAreNotSilentNoOps() {
        let localSignature = RecordingAudioSignature(
            sha256: String(repeating: "a", count: 64),
            size: 128
        )
        let sourceUnavailable = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .missing,
            peerAudioState: .unknown,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .manualUploadButton,
            syncRunID: nil,
            objectID: "recordingAudio:decision-audio",
            recordingID: "decision-audio"
        )
        #expect(sourceUnavailable.kind == .fail)
        #expect(sourceUnavailable.reasonCode == "local_audio_missing")
        #expect(sourceUnavailable.displayState == .failed("local_audio_missing"))

        let activeTransfer = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .available(localSignature),
            peerAudioState: .unknown,
            transferJobState: .inFlight,
            ledgerState: .none,
            triggerSource: .manualUploadButton,
            syncRunID: nil,
            objectID: "recordingAudio:decision-audio",
            recordingID: "decision-audio"
        )
        #expect(activeTransfer.kind == .suppress)
        #expect(activeTransfer.reasonCode == "transfer_in_flight")
        #expect(activeTransfer.displayState.shouldAnimateTransfer)

        let retryPending = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .available(localSignature),
            peerAudioState: .unknown,
            transferJobState: .none,
            ledgerState: .retryPending,
            triggerSource: .periodicSync,
            syncRunID: "sync-periodic",
            objectID: "recordingAudio:decision-audio",
            recordingID: "decision-audio"
        )
        #expect(retryPending.kind == .suppress)
        #expect(retryPending.reasonCode == "ledger_retry_pending")
        #expect(retryPending.displayState.shouldAnimateTransfer)

        let peerUnknownDeferred = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .available(localSignature),
            peerAudioState: .unknown,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .manualSyncIPhone,
            syncRunID: "sync-manual",
            objectID: "recordingAudio:decision-audio",
            recordingID: "decision-audio"
        )
        #expect(peerUnknownDeferred.kind == .suppress)
        #expect(peerUnknownDeferred.reasonCode == "peer_audio_unknown_deferred")
        #expect(peerUnknownDeferred.displayState == .waiting)

        let triggerCannotCreate = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .available(localSignature),
            peerAudioState: .metadataOnly,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .studyLibraryRefresh,
            syncRunID: nil,
            objectID: "recordingAudio:decision-audio",
            recordingID: "decision-audio"
        )
        #expect(triggerCannotCreate.kind == .suppress)
        #expect(triggerCannotCreate.reasonCode == "view_refresh_only")
        #expect(triggerCannotCreate.shouldCreateUploadJob == false)
    }

    @Test func iphoneTypographyTokensExistAndChatStylesStaySeparate() {
        #expect(RokuricsTypographyToken.allCases == [
            .pageTitle,
            .pageSubtitle,
            .sectionTitle,
            .cardTitle,
            .body,
            .secondary,
            .chatGreeting,
            .chatMessage,
            .chatInput,
            .technical
        ])
        #expect(RokuricsTypographyToken.chatGreeting != .pageTitle)
        #expect(RokuricsTypographyToken.chatMessage != .pageTitle)
        #expect(RokuricsTypographyToken.chatInput != .pageTitle)
    }

    @Test func iphoneCircleIconButtonConfigurationUsesSystemGlassButton() {
        #expect(RokuricsIconCircleButtonConfiguration.size >= 44)
        #expect(RokuricsIconCircleButtonConfiguration.iconSize > 0)
        #expect(RokuricsIconCircleButtonConfiguration.borderWidth == 1)
        #expect(RokuricsIconCircleButtonConfiguration.usesGlassBackground)
        #expect(RokuricsIconCircleButtonConfiguration.usesSystemSymbols)
    }

    @Test func lowPowerDisplayMinuteTextUsesCumulativeClockMinutes() {
        #expect(RecordingLowPowerDisplayPolicy.minuteText(elapsedSeconds: 7) == "00")
        #expect(RecordingLowPowerDisplayPolicy.minuteText(elapsedSeconds: 3 * 60 + 42) == "03")
        #expect(RecordingLowPowerDisplayPolicy.minuteText(elapsedSeconds: 37 * 60 + 24) == "37")
        #expect(RecordingLowPowerDisplayPolicy.minuteText(elapsedSeconds: 81 * 60 + 40) == "81")
    }

    @Test func lowPowerDisplayOnlyEntersForActiveForegroundRecording() {
        #expect(RecordingLowPowerDisplayPolicy.canEnter(
            state: .recording,
            isAppActive: true,
            isFilingOverlayPresented: false,
            hasBlockingPresentation: false
        ))
        #expect(!RecordingLowPowerDisplayPolicy.canEnter(
            state: .paused,
            isAppActive: true,
            isFilingOverlayPresented: false,
            hasBlockingPresentation: false
        ))
        #expect(!RecordingLowPowerDisplayPolicy.canEnter(
            state: .recording,
            isAppActive: false,
            isFilingOverlayPresented: false,
            hasBlockingPresentation: false
        ))
        #expect(!RecordingLowPowerDisplayPolicy.canEnter(
            state: .recording,
            isAppActive: true,
            isFilingOverlayPresented: true,
            hasBlockingPresentation: false
        ))
        #expect(!RecordingLowPowerDisplayPolicy.canEnter(
            state: .recording,
            isAppActive: true,
            isFilingOverlayPresented: false,
            hasBlockingPresentation: true
        ))
    }

    @Test func lowPowerElapsedRefreshDoesNotChangeRecordingManagerState() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let manager = RecordingManager(fileStore: store)

        manager.setLowPowerElapsedRefreshEnabled(true)

        #expect(manager.state == .idle)
    }

    @Test func recordingLiveActivityStateKeepsMinimalStatusText() {
        let recordingState = RecordingLiveActivityAttributes.ContentState(
            title: "课堂录音",
            elapsedMinutes: 81,
            isPaused: false,
            isSavingLocally: false
        )
        let savingState = RecordingLiveActivityAttributes.ContentState(
            title: "课堂录音",
            elapsedMinutes: 3,
            isPaused: false,
            isSavingLocally: true
        )

        #expect(recordingState.elapsedMinuteText == "81")
        #expect(recordingState.statusText == "录音中")
        #expect(savingState.elapsedMinuteText == "03")
        #expect(savingState.statusText == "本地保存中")
    }

    @Test func iphoneTechnicalInlineFragmentsDoNotPromoteWholeStringsToMonospace() {
        let fragments: [RokuricsInlineTextFragment] = [
            .text("路径 "),
            .technical("transcripts/2026-05-16/transcript.md"),
            .text(" 已保存")
        ]

        #expect(fragments[0].kind == .normal(.body))
        #expect(fragments[1].kind == .technical)
        #expect(fragments[2].kind == .normal(.body))
    }

    @Test func renameRecordingUpdatesMetadataTitle() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-01", title: "旧名称", store: store)

        let updated = try store.updateTitle(recordingID: metadata.id, rawTitle: " 新名称 ")

        #expect(updated.title == "新名称")
        #expect(try store.loadMetadata(id: metadata.id).title == "新名称")
    }

    @Test func renameRecordingTrimsWhitespaceAndNewlines() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-02", title: "旧名称", store: store)

        let updated = try store.updateTitle(recordingID: metadata.id, rawTitle: "  第一行\n第二行  ")

        #expect(updated.title == "第一行 第二行")
    }

    @Test func recordingManagerRenameAdvancesStudyItemBusinessTimestamp() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-rename-clock", title: "旧名称", store: store)
        let manager = RecordingManager(fileStore: store)
        let before = try #require(manager.studyLibraryStore.item(recordingID: metadata.id))

        try manager.renameRecording(recordingID: metadata.id, rawTitle: "新名称")

        let after = try #require(manager.studyLibraryStore.item(recordingID: metadata.id))
        #expect(after.title == "新名称")
        #expect(after.updatedAt > before.updatedAt)
    }

    @Test func emptyRenameDoesNotSaveEmptyTitle() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-03", title: "保留名称", store: store)

        let updated = try store.updateTitle(recordingID: metadata.id, rawTitle: "   ")

        #expect(updated.title == "保留名称")
        #expect(try store.loadMetadata(id: metadata.id).title == "保留名称")
    }

    @Test func recordingMetadataMissingDeletedFieldsDefaultsToActive() throws {
        let metadata = makeMetadata(
            id: "recording-legacy",
            title: "旧录音",
            relativeAudioPath: "Recordings/recording-legacy.m4a",
            relativeMetadataPath: "Metadata/recording-legacy.json",
            uploadStatus: "localOnly"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: try encoder.encode(metadata)) as? [String: Any])
        object.removeValue(forKey: "isDeleted")
        object.removeValue(forKey: "deletedAt")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RecordingMetadata.self, from: data)

        #expect(decoded.isDeleted == false)
        #expect(decoded.deletedAt == nil)
    }

    @Test func recordingMetadataMissingStudyFilingDecodesAsUnfiled() throws {
        let metadata = makeMetadata(
            id: "recording-legacy-filing",
            title: "旧录音",
            relativeAudioPath: "Recordings/recording-legacy-filing.m4a",
            relativeMetadataPath: "Metadata/recording-legacy-filing.json",
            uploadStatus: "localOnly"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: try encoder.encode(metadata)) as? [String: Any])
        object.removeValue(forKey: "studyFiling")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RecordingMetadata.self, from: data)

        #expect(decoded.studyFiling == nil)
    }

    @Test func directSaveUsesDefaultTitleAndEmptyFiling() {
        let title = RecordingSaveTitleResolver.title(
            defaultTitle: "录音 2026-05-18 12:00",
            pendingTitle: "课堂标题",
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数"),
            directSave: true
        )

        #expect(title == "录音 2026-05-18 12:00")
    }

    @Test func filingSaveCanGenerateFriendlyTitle() {
        let title = RecordingSaveTitleResolver.title(
            defaultTitle: "录音 2026-05-18 12:00",
            pendingTitle: nil,
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法"),
            directSave: false
        )

        #expect(title == "线性代数 · 矩阵 · 矩阵乘法")
    }

    @Test func uploadMetadataPayloadIncludesStudyFiling() {
        let filing = StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        let metadata = makeMetadata(
            id: "recording-upload-filing",
            title: "矩阵乘法",
            relativeAudioPath: "Recordings/recording-upload-filing.m4a",
            relativeMetadataPath: "Metadata/recording-upload-filing.json",
            uploadStatus: "localOnly",
            studyFiling: filing
        )

        let payload = RecordingUploadMetadataPayload(
            metadata: metadata,
            sourceDeviceName: "iPhone",
            sourceDeviceID: "device-01",
            uploadedAt: Date(timeIntervalSince1970: 2_000)
        )

        #expect(payload.studyFiling == filing)
    }

    @Test func iphoneUploadActionAreaPresentationMapsUploadStates() throws {
        let metadata = makeMetadata(
            id: "recording-upload-ui-state",
            title: "上传状态",
            relativeAudioPath: "Recordings/recording-upload-ui-state.m4a",
            relativeMetadataPath: "Metadata/recording-upload-ui-state.json",
            uploadStatus: "localOnly",
            fileSize: 100
        )
        let localMissing = makeMetadata(
            id: "recording-upload-missing",
            title: "缺失音频",
            relativeAudioPath: "",
            relativeMetadataPath: "Metadata/recording-upload-missing.json",
            uploadStatus: "localOnly",
            fileSize: 0
        )
        let preparing = metadata
            .updatingUploadStatus(.uploading)
            .updatingUploadProgress(
                fraction: nil,
                confirmedBytes: nil,
                totalBytes: 100,
                phase: "preparing",
                description: "准备上传"
            )
        let uploading = metadata
            .updatingUploadStatus(.uploading)
            .updatingUploadProgress(
                fraction: 0.36,
                confirmedBytes: 36,
                totalBytes: 100,
                phase: "uploading",
                description: nil
            )

        let missingPresentation = try #require(RecordingUploadActionAreaPresentation.resolve(
            metadata: localMissing,
            status: .localOnly,
            isMacPaired: true
        ))
        let waitingPresentation = try #require(RecordingUploadActionAreaPresentation.resolve(
            metadata: metadata,
            status: .localOnly,
            isMacPaired: true
        ))
        let preparingPresentation = try #require(RecordingUploadActionAreaPresentation.resolve(
            metadata: preparing,
            status: .uploading,
            isMacPaired: true
        ))
        let uploadingPresentation = try #require(RecordingUploadActionAreaPresentation.resolve(
            metadata: uploading,
            status: .uploading,
            isMacPaired: true
        ))
        let failedPresentation = try #require(RecordingUploadActionAreaPresentation.resolve(
            metadata: metadata.updatingUploadStatus(.failed),
            status: .failed,
            isMacPaired: true
        ))

        #expect(missingPresentation.layout == .statusWithActions)
        #expect(missingPresentation.statusText == "本地音频缺失")
        #expect(waitingPresentation.layout == .statusWithActions)
        #expect(waitingPresentation.statusText == "等待上传")
        #expect(preparingPresentation.layout == .progressOnly)
        #expect(preparingPresentation.transferProgress?.state == .pending)
        #expect(preparingPresentation.transferProgress?.statusText == "准备上传")
        #expect(uploadingPresentation.layout == .progressOnly)
        #expect(uploadingPresentation.transferProgress?.state == .transferring)
        #expect(uploadingPresentation.transferProgress?.progressFraction == 0.36)
        #expect(uploadingPresentation.transferProgress?.receivedBytes == 36)
        #expect(uploadingPresentation.transferProgress?.totalBytes == 100)
        #expect(uploadingPresentation.transferProgress?.statusText == "上传中 36%")
        #expect(RecordingUploadActionAreaPresentation.resolve(
            metadata: metadata.updatingUploadStatus(.uploaded),
            status: .uploaded,
            isMacPaired: true
        ) == nil)
        #expect(failedPresentation.layout == .statusWithActions)
        #expect(failedPresentation.statusText == "上传失败")
    }

    @Test func unfiledRecordingAppearsUnderUncategorizedStudyTree() {
        let metadata = makeMetadata(
            id: "recording-unfiled",
            title: "未分类",
            relativeAudioPath: "Recordings/recording-unfiled.m4a",
            relativeMetadataPath: "Metadata/recording-unfiled.json",
            uploadStatus: "localOnly"
        )

        let tree = RecordingStudyTreeBuilder.build(recordings: [metadata])

        #expect(tree.first?.title == StudyFilingPath.uncategorizedTitle)
        #expect(tree.first?.children.first?.title == StudyFilingPath.missingTitle)
        #expect(tree.first?.children.first?.children.first?.title == StudyFilingPath.missingTitle)
        #expect(tree.first?.children.first?.children.first?.children.first?.recordings.map(\.id) == ["recording-unfiled"])
    }

    @Test func filingCandidatesCollectExistingValues() {
        let first = makeMetadata(
            id: "candidate-iphone-01",
            title: "A",
            relativeAudioPath: "Recordings/a.m4a",
            relativeMetadataPath: "Metadata/a.json",
            uploadStatus: "localOnly",
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )
        let second = makeMetadata(
            id: "candidate-iphone-02",
            title: "B",
            relativeAudioPath: "Recordings/b.m4a",
            relativeMetadataPath: "Metadata/b.json",
            uploadStatus: "localOnly",
            studyFiling: StudyFilingPath(type: "复习", subject: "高等数学", chapter: "矩阵", topic: "格林公式")
        )

        let candidates = StudyFilingCandidates.collect(from: [first, second])

        #expect(Set(candidates.types) == Set(["课堂", "复习"]))
        #expect(Set(candidates.subjects) == Set(["线性代数", "高等数学"]))
        #expect(candidates.chapters == ["矩阵"])
        #expect(Set(candidates.topics) == Set(["矩阵乘法", "格林公式"]))
    }

    @Test func iphoneStudyBrowserRootLevelBuildsTypeFolders() {
        let recordings = [
            makeMetadata(
                id: "iphone-browser-root-01",
                title: "课堂",
                relativeAudioPath: "Recordings/a.m4a",
                relativeMetadataPath: "Metadata/a.json",
                uploadStatus: "localOnly",
                studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
            ),
            makeMetadata(
                id: "iphone-browser-root-02",
                title: "复习",
                relativeAudioPath: "Recordings/b.m4a",
                relativeMetadataPath: "Metadata/b.json",
                uploadStatus: "localOnly",
                studyFiling: StudyFilingPath(type: "复习", subject: "高等数学", chapter: "积分", topic: "格林公式")
            )
        ]

        let content = RecordingStudyBrowser.content(recordings: recordings, path: RecordingStudyBrowsePath())

        #expect(Set(content.folders.map(\.title)) == Set(["课堂", "复习"]))
        #expect(Set(content.folders.map(\.itemCount)) == Set([1]))
        #expect(content.recordings.isEmpty)
    }

    @Test func iphoneStudyBrowserBuildsNestedFoldersAndFinalRecordings() {
        let recording = makeMetadata(
            id: "iphone-browser-levels-01",
            title: "矩阵乘法",
            relativeAudioPath: "Recordings/matrix.m4a",
            relativeMetadataPath: "Metadata/matrix.json",
            uploadStatus: "localOnly",
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )

        let subjectContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂"]))
        let chapterContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂", "线性代数"]))
        let topicContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂", "线性代数", "矩阵"]))
        let recordingContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"]))

        #expect(subjectContent.folders.map(\.title) == ["线性代数"])
        #expect(chapterContent.folders.map(\.title) == ["矩阵"])
        #expect(topicContent.folders.map(\.title) == ["矩阵乘法"])
        #expect(recordingContent.recordings.map(\.id) == ["iphone-browser-levels-01"])
        #expect(recordingContent.folders.isEmpty)
    }

    @Test func iphoneStudyBrowserUncategorizedRecordingsAreDirectlyVisible() {
        let recording = makeMetadata(
            id: "iphone-browser-unfiled",
            title: "未分类",
            relativeAudioPath: "Recordings/unfiled.m4a",
            relativeMetadataPath: "Metadata/unfiled.json",
            uploadStatus: "localOnly"
        )

        let rootContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath())
        let uncategorizedContent = RecordingStudyBrowser.content(
            recordings: [recording],
            path: RecordingStudyBrowsePath(components: [StudyFilingPath.uncategorizedTitle])
        )

        #expect(rootContent.folders.map(\.title) == [StudyFilingPath.uncategorizedTitle])
        #expect(uncategorizedContent.recordings.map(\.id) == ["iphone-browser-unfiled"])
        #expect(uncategorizedContent.folders.isEmpty)
    }

    @Test func iphoneStudyBrowserMissingLowerFieldsDoNotHideRecordings() {
        let recording = makeMetadata(
            id: "iphone-browser-missing",
            title: "缺下层",
            relativeAudioPath: "Recordings/missing.m4a",
            relativeMetadataPath: "Metadata/missing.json",
            uploadStatus: "localOnly",
            studyFiling: StudyFilingPath(type: "课堂")
        )

        let subjectContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂"]))
        let chapterContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂", StudyFilingPath.missingTitle]))
        let topicContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂", StudyFilingPath.missingTitle, StudyFilingPath.missingTitle]))
        let recordingContent = RecordingStudyBrowser.content(recordings: [recording], path: RecordingStudyBrowsePath(components: ["课堂", StudyFilingPath.missingTitle, StudyFilingPath.missingTitle, StudyFilingPath.missingTitle]))

        #expect(subjectContent.folders.map(\.title) == [StudyFilingPath.missingTitle])
        #expect(chapterContent.folders.map(\.title) == [StudyFilingPath.missingTitle])
        #expect(topicContent.folders.map(\.title) == [StudyFilingPath.missingTitle])
        #expect(recordingContent.recordings.map(\.id) == ["iphone-browser-missing"])
    }

    @Test func iphoneStudyBrowserBreadcrumbsNavigateByDepth() {
        let path = RecordingStudyBrowsePath(components: ["课堂", "线性代数", "矩阵"])
        let breadcrumbs = RecordingStudyBrowser.breadcrumbs(for: path)

        #expect(breadcrumbs.map(\.title) == ["学习库", "课堂", "线性代数", "矩阵"])
        #expect(breadcrumbs[1].path.components == ["课堂"])
        #expect(breadcrumbs[2].path.components == ["课堂", "线性代数"])
        #expect(path.parent.components == ["课堂", "线性代数"])
    }

    @Test func iphoneStudyFilingUpdateMovesRecordingToNewVirtualPath() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "iphone-browser-update", title: "路径更新", store: store)
        let manager = RecordingManager(fileStore: store)

        #expect(RecordingStudyBrowser.content(recordings: manager.recordings, path: RecordingStudyBrowsePath()).folders.map(\.title) == [StudyFilingPath.uncategorizedTitle])

        try manager.updateStudyFiling(
            recordingID: "iphone-browser-update",
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )

        let rootContent = RecordingStudyBrowser.content(recordings: manager.recordings, path: RecordingStudyBrowsePath())
        let finalContent = RecordingStudyBrowser.content(
            recordings: manager.recordings,
            path: RecordingStudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"])
        )

        #expect(rootContent.folders.map(\.title) == ["课堂"])
        #expect(finalContent.recordings.map(\.id) == ["iphone-browser-update"])
    }

    @Test func studyFilingSelectionClearsDescendantLevels() {
        var draft = StudyFilingSelectionDraft(
            path: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "乘法")
        )

        draft.select(.subject, value: "高等数学")

        #expect(draft.type == "课堂")
        #expect(draft.subject == "高等数学")
        #expect(draft.chapter.isEmpty)
        #expect(draft.topic.isEmpty)

        draft.select(.type, value: "复习")

        #expect(draft.type == "复习")
        #expect(draft.subject.isEmpty)
        #expect(draft.chapter.isEmpty)
        #expect(draft.topic.isEmpty)
    }

    @Test func studyFilingCandidatesFilterByParentPath() {
        let first = StudyItemMetadata(
            recordingID: "candidate-filter-01",
            title: "A",
            createdAt: Date(timeIntervalSince1970: 10),
            duration: 12,
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵")
        )
        let second = StudyItemMetadata(
            recordingID: "candidate-filter-02",
            title: "B",
            createdAt: Date(timeIntervalSince1970: 20),
            duration: 12,
            studyFiling: StudyFilingPath(type: "复习", subject: "高等数学", chapter: "积分")
        )
        let folder = StudyFolderMetadata(
            name: "离散数学",
            level: .subject,
            path: StudyFilingPath(type: "课堂", subject: "离散数学")
        )

        let subjects = StudyFilingCandidateResolver.candidates(
            for: .subject,
            current: StudyFilingPath(type: "课堂"),
            items: [first, second],
            folders: [folder]
        )

        #expect(Set(subjects) == Set(["线性代数", "离散数学"]))
        #expect(!subjects.contains("高等数学"))
    }

    @Test func studyLibraryStoreWritesRecordingBundleAndFolderIndex() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(
            id: "study-store-recording",
            title: "矩阵乘法",
            store: audioStore,
            studyFiling: StudyFilingPath(type: "课堂", subject: "线性代数", chapter: "矩阵", topic: "矩阵乘法")
        )
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)

        let item = try studyStore.upsertRecordingMetadata(metadata)
        let content = StudyLibraryBrowser.content(
            items: studyStore.allStudyItems,
            folders: studyStore.allStudyFolders,
            path: StudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"])
        )

        #expect(item.kind == .recordingBundle)
        #expect(content.items.map(\.itemID) == [item.itemID])
        #expect(studyStore.allStudyFolders.contains { folder in
            folder.itemIDs.contains(item.itemID)
        })
    }

    @Test func iphoneUploadProgressUpdateRefreshesStudyLibraryItemSnapshot() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(
            id: "study-store-upload-progress",
            title: "上传进度",
            store: audioStore,
            audioData: Data(repeating: 7, count: 100)
        )
        let manager = RecordingManager(fileStore: audioStore)

        #expect(manager.studyLibraryStore.item(recordingID: metadata.id)?.localNetworkTransferProgress == nil)

        try manager.updateUploadStatus(recordingID: metadata.id, status: .uploading)
        try manager.updateUploadProgress(
            recordingID: metadata.id,
            fraction: 0.36,
            confirmedBytes: 36,
            totalBytes: 100,
            phase: "uploading",
            description: nil
        )

        let item = try #require(manager.studyLibraryStore.item(recordingID: metadata.id))
        let progress = try #require(item.localNetworkTransferProgress)
        #expect(progress.objectID == "recordingAudio:\(metadata.id)")
        #expect(progress.objectKind == LocalNetworkSyncObjectKind.recordingAudio.rawValue)
        #expect(progress.state == .transferring)
        #expect(progress.progressFraction == 0.36)
        #expect(progress.receivedBytes == 36)
        #expect(progress.totalBytes == 100)
        #expect(progress.statusText == "上传中 36%")
    }

    @Test func studyLibraryStoreRepairsMissingFolderItemReferences() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let item = StudyItemMetadata(
            kind: .standaloneNote,
            title: "独立笔记",
            createdAt: Date(timeIntervalSince1970: 30),
            filing: StudyFilingPath(type: "课堂")
        )
        try studyStore.save(item)
        let folder = StudyFolderMetadata(
            name: "课堂",
            level: .type,
            path: StudyFilingPath(type: "课堂"),
            itemIDs: ["missing-item-id", item.itemID]
        )
        try studyStore.save(folder)

        studyStore.refresh()

        let repaired = try #require(studyStore.allStudyFolders.first { $0.folderID == folder.folderID })
        #expect(repaired.itemIDs == [item.itemID])
    }

    @Test func studyLibraryStoreReadsLegacyReceiveJSONWithMissingFields() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let receiveDirectory = rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .appendingPathComponent("2026-05-21", isDirectory: true)
            .appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: receiveDirectory, withIntermediateDirectories: true)
        let receiveURL = receiveDirectory.appendingPathComponent("receive.json", isDirectory: false)
        let receiveObject: [String: Any] = [
            "recordingID": "legacy-receive",
            "normalizedTitle": "旧接收录音",
            "createdAt": "2026-05-21T00:00:00Z",
            "duration": 42,
            "studyFiling": [
                "type": "课堂",
                "subject": "物理"
            ],
            "audioRelativePath": "audio/inbox/2026-05-21/legacy/audio.m4a"
        ]
        try JSONSerialization.data(withJSONObject: receiveObject, options: [.prettyPrinted])
            .write(to: receiveURL, options: .atomic)

        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)

        #expect(studyStore.allStudyItems.first?.recordingID == "legacy-receive")
        #expect(studyStore.allStudyItems.first?.filing.subject == "物理")
    }

    @Test func softDeleteRecordingUpdatesMetadataButKeepsFiles() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-04", title: "要删除", store: store)
        let audioURL = try store.audioURL(for: metadata)
        let metadataURL = try store.makeMetadataURL(id: metadata.id)

        try store.deleteRecording(metadata)

        let updated = try store.loadMetadata(id: metadata.id)
        #expect(updated.isDeleted)
        #expect(updated.deletedAt != nil)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(FileManager.default.fileExists(atPath: metadataURL.path))
        #expect(try store.loadAllMetadata().isEmpty)
        #expect(try store.loadTrashedMetadata().map(\.id) == [metadata.id])
    }

    @Test func permanentDeleteRecordingRemovesAudioAndMetadata() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-permanent", title: "永久删除", store: store)
        let audioURL = try store.audioURL(for: metadata)
        let metadataURL = try store.makeMetadataURL(id: metadata.id)

        try store.permanentlyDeleteRecording(metadata)

        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        #expect(!FileManager.default.fileExists(atPath: metadataURL.path))
    }

    @Test func permanentDeleteRejectsAudioPathOutsideRokuricsRoot() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let outsideURL = rootURL
            .deletingLastPathComponent()
            .appendingPathComponent("outside.m4a", isDirectory: false)
        try Data("outside".utf8).write(to: outsideURL)
        let metadataURL = try store.makeMetadataURL(id: "recording-05")
        let metadata = makeMetadata(
            id: "recording-05",
            title: "越界",
            relativeAudioPath: "../outside.m4a",
            relativeMetadataPath: try store.relativePath(for: metadataURL),
            uploadStatus: "localOnly"
        )
        try store.saveMetadata(metadata)

        do {
            try store.permanentlyDeleteRecording(metadata)
            Issue.record("Expected delete to reject path outside Rokurics root")
        } catch AudioFileStoreError.pathOutsideRokuricsDirectory {
            #expect(FileManager.default.fileExists(atPath: outsideURL.path))
        }
    }

    @Test func softDeleteUploadedRecordingDoesNotRemoveLocalFilesOrRemoteState() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-06", title: "已上传", store: store, uploadStatus: "uploaded")
        let audioURL = try store.audioURL(for: metadata)

        try store.deleteRecording(metadata)

        #expect(try store.loadAllMetadata().isEmpty)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == "uploaded")
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test func restoreRecordingBringsItemBackFromTrash() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-restore", title: "恢复", store: store)

        try store.deleteRecording(metadata)
        let restored = try store.restoreRecording(id: metadata.id)

        #expect(restored.isDeleted == false)
        #expect(restored.deletedAt == nil)
        #expect(try store.loadAllMetadata().map(\.id) == [metadata.id])
        #expect(try store.loadTrashedMetadata().isEmpty)
    }

    @Test func recordingManagerRestoreClearsStudyItemTombstone() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "recording-restore-tombstone", title: "恢复", store: store)
        let manager = RecordingManager(fileStore: store)
        _ = try manager.studyLibraryStore.upsertRecordingMetadata(metadata)

        try manager.deleteRecording(recordingID: metadata.id)
        let trashed = try #require(
            manager.studyLibraryStore
                .makeSyncManifest(deviceID: "iphone-test")
                .items
                .first { $0.recordingID == metadata.id }
        )
        #expect(trashed.isTrashed)
        #expect(trashed.trashedAt != nil)

        try manager.restoreRecording(recordingID: metadata.id)

        let restored = try #require(manager.studyLibraryStore.item(recordingID: metadata.id))
        #expect(restored.isTrashed == false)
        #expect(restored.trashedAt == nil)
        #expect(restored.updatedAt > trashed.updatedAt)
    }

    @Test func loadAllMetadataFiltersDeletedRecordingsByDefault() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "recording-active", title: "保留", store: store)
        let deleted = try saveRecording(id: "recording-deleted", title: "废纸篓", store: store)

        try store.deleteRecording(deleted)

        #expect(try store.loadAllMetadata().map(\.id) == ["recording-active"])
        #expect(Set(try store.loadAllMetadata(includeDeleted: true).map(\.id)) == ["recording-active", "recording-deleted"])
    }

    @MainActor
    @Test func deletingRecordingUpdatesManagerListCount() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "recording-07", title: "第一条", store: store)
        _ = try saveRecording(id: "recording-08", title: "第二条", store: store)
        let manager = RecordingManager(fileStore: store)

        try manager.deleteRecording(recordingID: "recording-07")

        #expect(manager.recordings.count == 1)
        #expect(!manager.recordings.map(\.id).contains("recording-07"))
        #expect(manager.trashedRecordings.map(\.id) == ["recording-07"])
    }

    @MainActor
    @Test func homepageRecordingCountExcludesDeletedItems() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "recording-home-active", title: "首页显示", store: store)
        let deleted = try saveRecording(id: "recording-home-deleted", title: "首页隐藏", store: store)
        try store.deleteRecording(deleted)

        let manager = RecordingManager(fileStore: store)

        #expect(manager.recordings.count == 1)
        #expect(manager.recordings.first?.id == "recording-home-active")
        #expect(manager.pendingUploadCount == 1)
    }

    @Test func uploadCapsulePresentationKeepsStatusMapping() {
        #expect(RecordingUploadCapsulePresentation.resolve(status: .localOnly, isMacPaired: true).label == "上传")
        #expect(RecordingUploadCapsulePresentation.resolve(status: .uploading, isMacPaired: true).label == "上传中")
        #expect(RecordingUploadCapsulePresentation.resolve(status: .uploaded, isMacPaired: true).label == "已上传")
        #expect(RecordingUploadCapsulePresentation.resolve(status: .failed, isMacPaired: true).label == "重试")
        #expect(RecordingUploadCapsulePresentation.resolve(status: .localOnly, isMacPaired: true).isEnabled)
        #expect(RecordingUploadCapsulePresentation.resolve(status: .failed, isMacPaired: true).isEnabled)
        #expect(!RecordingUploadCapsulePresentation.resolve(status: .uploading, isMacPaired: true).isEnabled)
        #expect(RecordingUploadCapsulePresentation.resolve(status: .uploaded, isMacPaired: true).isEnabled)
        #expect(!RecordingUploadCapsulePresentation.resolve(status: .localOnly, isMacPaired: false).isEnabled)
        #expect(!RecordingUploadCapsulePresentation.resolve(status: .uploaded, isMacPaired: false).isEnabled)
    }

    @Test func uploadFlightRecorderWritesSanitizedJSONLines() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsUploadTraceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            UploadFlightRecorder.configureLogURL(nil)
            try? FileManager.default.removeItem(at: rootURL)
        }
        let traceURL = rootURL.appendingPathComponent("upload-trace.jsonl", isDirectory: false)
        UploadFlightRecorder.configureLogURL(traceURL)

        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "manualUploadActionFired",
            traceID: "upl-test-trace-iphone",
            recordingID: "recording-sensitive-full-id",
            eventResult: "begin",
            httpPath: "/upload-recording-audio?token=secret",
            fileExists: true,
            fileSize: 5,
            resolvedRelativePathToken: "/Users/vita/private/audio.m4a",
            safeErrorMessage: "/Users/vita/private/audio.m4a"
        )

        UploadFlightRecorder.flushForTests()
        let events = try UploadFlightRecorder.loadEvents(from: traceURL)
        let event = try #require(events.first)
        let rawText = try String(contentsOf: traceURL, encoding: .utf8)

        #expect(event.traceID == "upl-test-trace-iphone")
        #expect(event.side == .iPhone)
        #expect(event.recordingIDPrefix == "recording-se")
        #expect(event.httpPath == "/upload-recording-audio")
        #expect(event.resolvedRelativePathToken == "absolute_path_redacted")
        #expect(event.safeErrorMessage == "private_path_redacted")
        #expect(rawText.contains(UploadFlightRecorder.logPrefix))
        #expect(!rawText.contains("/Users/vita"))
        #expect(!rawText.contains("recording-sensitive-full-id"))
    }

    @Test func staleUploadingStatusRecoversToFailedOnRecordingManagerLoad() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "stale-uploading-01", title: "卡住上传", store: store, uploadStatus: "uploading")

        let manager = RecordingManager(fileStore: store)

        #expect(manager.recordings.map(\.id) == ["stale-uploading-01"])
        #expect(manager.recordings.first?.uploadStatus == RecordingUploadStatus.failed.rawValue)
        #expect(try store.loadMetadata(id: "stale-uploading-01").uploadStatus == RecordingUploadStatus.failed.rawValue)
    }

    @Test func uploadJobStoreCreatesSavesAndLoadsJobWithVersion() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "upload-job-01", title: "任务账本", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 100)

        let job = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now)
        let loadedJob = try #require(try jobStore.loadJob(recordingID: metadata.id))
        let ledgerData = try Data(contentsOf: jobStore.ledgerURL())
        let ledgerJSON = try #require(JSONSerialization.jsonObject(with: ledgerData) as? [String: Any])

        #expect(job.recordingID == metadata.id)
        #expect(loadedJob.recordingID == metadata.id)
        #expect(loadedJob.metadataStage == .pending)
        #expect(loadedJob.audioStage == .pending)
        #expect(ledgerJSON["version"] as? Int == RecordingUploadJobLedger.currentVersion)
    }

    @Test func uploadJobStoreAtomicUpdatePreservesSingleActiveJob() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "upload-job-single", title: "唯一任务", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 100)

        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now)
        _ = try jobStore.markAttemptStarted(recordingID: metadata.id, now: now.addingTimeInterval(1))
        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now.addingTimeInterval(2))
        let jobs = try jobStore.loadJobs()
        let loadedJob = try #require(jobs.first)

        #expect(jobs.count == 1)
        #expect(loadedJob.recordingID == metadata.id)
        #expect(loadedJob.attemptCount == 1)
        #expect(loadedJob.lastAttemptAt == now.addingTimeInterval(1))
    }

    @Test func uploadJobStoreResetsCompletedStagesWhenPairingTargetChanges() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "upload-job-new-target", title: "换 Mac", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let firstTarget = makePairedMacSnapshot()
        _ = try jobStore.ensureJob(for: metadata, settings: firstTarget, now: Date(timeIntervalSince1970: 100))
        _ = try jobStore.markAttemptStarted(recordingID: metadata.id, now: Date(timeIntervalSince1970: 101))
        _ = try jobStore.applyProgress(
            recordingID: metadata.id,
            event: .metadataSucceeded(disposition: "acceptedNew"),
            now: Date(timeIntervalSince1970: 102)
        )
        let secondTarget = SecureMacConnectionSnapshot(
            macHost: firstTarget.macHost,
            macPort: firstTarget.macPort,
            macFingerprint: firstTarget.macFingerprint,
            macName: "Second Mac",
            macModel: firstTarget.macModel,
            deviceID: "mac-second",
            sharedSecretBase64URL: firstTarget.sharedSecretBase64URL,
            pairedAt: firstTarget.pairedAt
        )

        let replaced = try jobStore.ensureJob(
            for: metadata,
            settings: secondTarget,
            now: Date(timeIntervalSince1970: 200)
        )

        #expect(replaced.targetDeviceID == "mac-second")
        #expect(replaced.metadataStage == .pending)
        #expect(replaced.audioStage == .pending)
        #expect(replaced.overallState == .pending)
        #expect(replaced.resumableSessionID == nil)
        #expect(replaced.attemptCount == 0)
        #expect(try jobStore.loadJobs().count == 1)
    }

    @Test func corruptedUploadLedgerDoesNotCrashOrDeleteRecordings() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "upload-job-corrupt", title: "损坏账本", store: store)
        let audioURL = try store.audioURL(for: metadata)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        try "not-json".data(using: .utf8)?.write(to: jobStore.ledgerURL(), options: .atomic)

        let jobs = try jobStore.loadJobs()

        #expect(jobs.isEmpty)
        #expect(jobStore.lastReadError?.contains("upload ledger read failed") == true)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(try store.loadMetadata(id: metadata.id).id == metadata.id)
    }

    @Test func uploadJobLedgerDoesNotPersistSharedSecret() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "upload-job-secret", title: "敏感信息", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let snapshot = makePairedMacSnapshot()

        _ = try jobStore.ensureJob(for: metadata, settings: snapshot, now: Date(timeIntervalSince1970: 100))
        let ledgerText = try String(contentsOf: jobStore.ledgerURL(), encoding: .utf8)

        #expect(!ledgerText.contains(snapshot.sharedSecretBase64URL))
        #expect(!ledgerText.contains("sharedSecret"))
        #expect(!ledgerText.contains("HMAC"))
        #expect(!ledgerText.contains("certificate"))
    }

    @Test func retryPolicyBackoffGrowsAndCaps() {
        let policy = RecordingUploadRetryPolicy.standard

        #expect(policy.delay(forAttemptCount: 1) == 5)
        #expect(policy.delay(forAttemptCount: 2) == 30)
        #expect(policy.delay(forAttemptCount: 3) == 120)
        #expect(policy.delay(forAttemptCount: 10) == 600)
    }

    @Test func retryQueueStopsAutomaticRetriesAtConfiguredAttemptLimit() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "upload-retry-limit", title: "重试上限", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let policy = RecordingUploadRetryPolicy(delays: [0], maximumDelay: 0, maximumAutomaticAttempts: 2)
        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: Date(timeIntervalSince1970: 1))
        _ = try jobStore.markAttemptStarted(recordingID: metadata.id, now: Date(timeIntervalSince1970: 2))
        _ = try jobStore.markRetryableFailure(
            recordingID: metadata.id,
            classification: RecordingUploadFailureClassification(code: "network", message: "offline", isFatal: false),
            retryPolicy: policy,
            now: Date(timeIntervalSince1970: 3)
        )
        _ = try jobStore.markAttemptStarted(recordingID: metadata.id, now: Date(timeIntervalSince1970: 4))
        let failed = try jobStore.markRetryableFailure(
            recordingID: metadata.id,
            classification: RecordingUploadFailureClassification(code: "network", message: "offline", isFatal: false),
            retryPolicy: policy,
            now: Date(timeIntervalSince1970: 5)
        )

        let queue = RecordingUploadQueue(jobStore: jobStore, retryPolicy: policy)
        #expect(failed.isRetryable)
        #expect(queue.isEligible(failed, now: Date(timeIntervalSince1970: 10)) == false)
    }

    @Test func retryQueueEligibilityAndDrainOnlyProcessesEligibleRetryableJobs() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 1_000)
        let eligibleMetadata = try saveRecording(id: "retry-eligible", title: "可重试", store: store)
        let futureMetadata = try saveRecording(id: "retry-future", title: "稍后重试", store: store)
        let fatalMetadata = try saveRecording(id: "retry-fatal", title: "致命失败", store: store)
        let succeededMetadata = try saveRecording(id: "retry-succeeded", title: "已成功", store: store)

        var eligibleJob = RecordingUploadJob.make(metadata: eligibleMetadata, settings: makePairedMacSnapshot(), now: now)
        eligibleJob.overallState = .retryableFailed
        eligibleJob.audioStage = .failed
        eligibleJob.nextRetryAfter = now
        try jobStore.saveJob(eligibleJob)

        var futureJob = RecordingUploadJob.make(metadata: futureMetadata, settings: makePairedMacSnapshot(), now: now)
        futureJob.overallState = .retryableFailed
        futureJob.audioStage = .failed
        futureJob.nextRetryAfter = now.addingTimeInterval(30)
        try jobStore.saveJob(futureJob)

        var fatalJob = RecordingUploadJob.make(metadata: fatalMetadata, settings: makePairedMacSnapshot(), now: now)
        fatalJob.overallState = .fatalFailed
        fatalJob.isFatal = true
        fatalJob.metadataStage = .failed
        try jobStore.saveJob(fatalJob)

        var succeededJob = RecordingUploadJob.make(metadata: succeededMetadata, settings: makePairedMacSnapshot(), now: now)
        succeededJob.overallState = .succeeded
        succeededJob.metadataStage = .succeeded
        succeededJob.audioStage = .succeeded
        try jobStore.saveJob(succeededJob)

        let queue = RecordingUploadQueue(jobStore: jobStore, retryPolicy: .standard)
        var drainedIDs: [String] = []
        let drainedJobs = try await queue.drainEligibleJobs(now: now) { job in
            drainedIDs.append(job.recordingID)
        }

        #expect(try queue.retryableJobs(now: now).map(\.recordingID).sorted() == ["retry-eligible", "retry-future"])
        #expect(try queue.eligibleRetryableJobs(now: now).map(\.recordingID) == ["retry-eligible"])
        #expect(drainedJobs.map(\.recordingID) == ["retry-eligible"])
        #expect(drainedIDs == ["retry-eligible"])
        #expect(!queue.isEligible(futureJob, now: now))
        #expect(queue.isEligible(futureJob, now: now.addingTimeInterval(30)))
        #expect(!queue.isEligible(fatalJob, now: now))
        #expect(!queue.isEligible(succeededJob, now: now))
    }

    @Test func retryDrainerEligibleJobRunsMainUploadPathAndSkipsBackoff() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let eligibleMetadata = try saveRecording(id: "retry-drainer-eligible", title: "到期重试", store: store)
        let futureMetadata = try saveRecording(id: "retry-drainer-future", title: "未到期重试", store: store)
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 2_000)

        var eligibleJob = RecordingUploadJob.make(metadata: eligibleMetadata, settings: makePairedMacSnapshot(), now: now.addingTimeInterval(-20))
        eligibleJob.overallState = .retryableFailed
        eligibleJob.metadataStage = .failed
        eligibleJob.attemptCount = 1
        eligibleJob.nextRetryAfter = now.addingTimeInterval(-1)
        try jobStore.saveJob(eligibleJob)

        var futureJob = RecordingUploadJob.make(metadata: futureMetadata, settings: makePairedMacSnapshot(), now: now.addingTimeInterval(-20))
        futureJob.overallState = .retryableFailed
        futureJob.metadataStage = .failed
        futureJob.attemptCount = 1
        futureJob.nextRetryAfter = now.addingTimeInterval(60)
        try jobStore.saveJob(futureJob)

        let fakeClient = FakeRecordingUploadClient(
            result: .success(RecordingUploadResult(
                recordingID: eligibleMetadata.id,
                metadataFileName: "metadata.json",
                audioFileName: "audio.m4a",
                metadataDisposition: "acceptedExisting",
                audioDisposition: "acceptedNew"
            )),
            events: [
                .metadataStarted,
                .metadataSucceeded(disposition: "acceptedExisting"),
                .audioStarted,
                .audioSucceeded(disposition: "acceptedNew")
            ]
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let drained = await coordinator.drainEligibleRetryJobs(
            settings: makePairedMacSnapshot(),
            recordingManager: manager,
            now: now,
            syncRunID: "retry-drainer-test"
        )

        let eligibleAfter = try #require(try jobStore.loadJob(recordingID: eligibleMetadata.id))
        let futureAfter = try #require(try jobStore.loadJob(recordingID: futureMetadata.id))
        #expect(drained == [eligibleMetadata.id])
        #expect(fakeClient.uploadRequestCount == 1)
        #expect(eligibleAfter.overallState == .succeeded)
        #expect(futureAfter.overallState == .retryableFailed)
        #expect(futureAfter.nextRetryAfter == futureJob.nextRetryAfter)
    }

    @Test func newUploadCreatesJobAndMarksSucceededWithMetadataUploaded() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "job-success-new", title: "新上传", store: store)
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let fakeClient = FakeRecordingUploadClient(
            result: .success(RecordingUploadResult(
                recordingID: metadata.id,
                metadataFileName: "metadata.json",
                audioFileName: "audio.m4a",
                metadataDisposition: "acceptedNew",
                audioDisposition: "acceptedNew"
            )),
            events: [
                .metadataStarted,
                .metadataSucceeded(disposition: "acceptedNew"),
                .audioStarted,
                .audioSucceeded(disposition: "acceptedNew")
            ]
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .uploaded)
        #expect(job.overallState == .succeeded)
        #expect(job.metadataStage == .succeeded)
        #expect(job.audioStage == .succeeded)
        #expect(job.metadataDisposition == .acceptedNew)
        #expect(job.audioDisposition == .acceptedNew)
        #expect(job.attemptCount == 1)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.uploaded.rawValue)
    }

    @Test func metadataAcceptedExistingAndAudioSuccessMarksLocalRecordingUploaded() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "retry-after-metadata-only", title: "重试录音", store: store)
        let manager = RecordingManager(fileStore: store)
        let fakeClient = FakeRecordingUploadClient(result: .success(RecordingUploadResult(
            recordingID: metadata.id,
            metadataFileName: "metadata.json",
            audioFileName: "audio.m4a",
            metadataDisposition: "acceptedExisting",
            audioDisposition: "acceptedNew"
        )), events: [
            .metadataStarted,
            .metadataSucceeded(disposition: "acceptedExisting"),
            .audioStarted,
            .audioSucceeded(disposition: "acceptedNew")
        ])
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(
            metadata: metadata,
            settings: makePairedMacSnapshot(),
            recordingManager: manager
        )
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .uploaded)
        #expect(job.overallState == .succeeded)
        #expect(job.metadataDisposition == .acceptedExisting)
        #expect(job.audioDisposition == .acceptedNew)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.uploaded.rawValue)
        #expect(coordinator.errorMessage(for: metadata) == nil)
        #expect(fakeClient.lastMetadata?.id == metadata.id)
    }

    @Test func uploadedLocalStatusStillRunsMainAudioUploadWhenLedgerDidNotCompleteAudio() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(
            id: "uploaded-but-mac-awaiting-audio",
            title: "状态已上传但 Mac 缺音频",
            store: store,
            uploadStatus: RecordingUploadStatus.uploaded.rawValue
        )
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let fakeClient = FakeRecordingUploadClient(result: .success(RecordingUploadResult(
            recordingID: metadata.id,
            metadataFileName: "metadata.json",
            audioFileName: "audio.m4a",
            metadataDisposition: "acceptedExisting",
            audioDisposition: "acceptedNew"
        )), events: [
            .metadataStarted,
            .metadataSucceeded(disposition: "acceptedExisting"),
            .audioStarted,
            .audioSucceeded(disposition: "acceptedNew")
        ])
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(
            metadata: metadata,
            settings: makePairedMacSnapshot(),
            recordingManager: manager
        )
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .uploaded)
        #expect(fakeClient.uploadRequestCount == 1)
        #expect(fakeClient.lastMetadata?.id == metadata.id)
        #expect(job.overallState == .succeeded)
        #expect(job.metadataDisposition == .acceptedExisting)
        #expect(job.audioDisposition == .acceptedNew)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.uploaded.rawValue)
    }

    @Test func uploadedLocalStatusUploadEmitsFlightRecorderStages() async throws {
        let (store, rootURL) = try makeStore()
        defer {
            UploadFlightRecorder.configureLogURL(nil)
            try? FileManager.default.removeItem(at: rootURL)
        }
        let traceURL = rootURL.appendingPathComponent("upload-trace.jsonl", isDirectory: false)
        UploadFlightRecorder.configureLogURL(traceURL)
        let metadata = try saveRecording(
            id: "uploaded-trace-redrive",
            title: "状态已上传但需要重传",
            store: store,
            uploadStatus: RecordingUploadStatus.uploaded.rawValue
        )
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let fakeClient = FakeRecordingUploadClient(result: .success(RecordingUploadResult(
            recordingID: metadata.id,
            metadataFileName: "metadata.json",
            audioFileName: "audio.m4a",
            metadataDisposition: "acceptedExisting",
            audioDisposition: "acceptedNew"
        )), events: [
            .metadataStarted,
            .metadataSucceeded(disposition: "acceptedExisting"),
            .audioStarted,
            .audioSucceeded(disposition: "acceptedNew")
        ])
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(
            metadata: metadata,
            settings: makePairedMacSnapshot(),
            recordingManager: manager,
            traceID: "upl-test-uploaded-redrive"
        )
        UploadFlightRecorder.flushForTests()
        let stages = Set(try UploadFlightRecorder.loadEvents(from: traceURL).map(\.stage))

        #expect(status == .uploaded)
        #expect(fakeClient.uploadRequestCount == 1)
        #expect(stages.contains("uploadCoordinatorEntered"))
        #expect(stages.contains("uploadCoordinatorLedgerLoaded"))
        #expect(stages.contains("uploadCoordinatorLedgerCompletedDetected"))
        #expect(stages.contains("uploadCoordinatorAudioResolved"))
        #expect(stages.contains("uploadCoordinatorFileSizeChecked"))
        #expect(stages.contains("metadataUploadStarted"))
        #expect(stages.contains("metadataUploadCompleted"))
        #expect(stages.contains("audioUploadStarted"))
        #expect(stages.contains("audioUploadCompleted"))
        #expect(stages.contains("uploadCoordinatorClientCallCompleted"))
    }

    @Test func preparedSignedJSONRequestCarriesTraceHeaderWithoutChangingSignatureInputs() throws {
        let traceID = "upl-test-prepared-json"
        let client = SecureMacUploadClient()
        let body = ResumableAudioUploadStartRequest(
            recordingID: "prepared-json-recording",
            fileName: "audio.m4a",
            totalBytes: 5,
            totalSHA256: String(repeating: "b", count: 64),
            chunkSize: 3,
            metadataHash: nil,
            uploadJobID: "prepared-json-recording"
        )

        let prepared = try UploadFlightRecorder.$currentTraceID.withValue(traceID) {
            try client.prepareSignedJSONRequest(
                settings: makePairedMacSnapshot(),
                path: "/upload-recording-audio-session/start",
                body: body,
                now: Date(timeIntervalSince1970: 2_000)
            )
        }
        let bodyHash = SecureUploadUtilities.sha256Hex(prepared.body)
        let timestamp = try #require(prepared.headers["X-Rokurics-Timestamp"])
        let nonce = try #require(prepared.headers["X-Rokurics-Nonce"])
        let payload = [
            "POST",
            "/upload-recording-audio-session/start",
            timestamp,
            nonce,
            bodyHash
        ].joined(separator: "\n")
        let expectedSignature = try #require(SecureUploadUtilities.hmacSHA256Base64URL(
            message: payload,
            secretBase64URL: makePairedMacSnapshot().sharedSecretBase64URL
        ))
        let bodyText = String(data: prepared.body, encoding: .utf8) ?? ""

        #expect(prepared.headers[UploadFlightRecorder.traceHeaderName] == traceID)
        #expect(prepared.headers["X-Rokurics-Body-SHA256"] == bodyHash)
        #expect(prepared.headers["X-Rokurics-Signature"] == expectedSignature)
        #expect(prepared.url.path == "/upload-recording-audio-session/start")
        #expect(!bodyText.contains(traceID))
        #expect(!bodyText.localizedCaseInsensitiveContains("sharedSecret"))
    }

    @Test func metadataSuccessAndAudioTemporaryFailureLeavesRetryableJob() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "audio-temp-failure", title: "音频临时失败", store: store)
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let fakeClient = FakeRecordingUploadClient(
            result: .failure(RecordingUploadError.audioUploadFailed("network timeout")),
            events: [
                .metadataStarted,
                .metadataSucceeded(disposition: "acceptedNew"),
                .audioStarted
            ]
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .failed)
        #expect(job.overallState == .retryableFailed)
        #expect(job.metadataStage == .succeeded)
        #expect(job.audioStage == .failed)
        #expect(job.metadataDisposition == .acceptedNew)
        #expect(job.attemptCount == 1)
        #expect(job.nextRetryAfter != nil)
        #expect(job.lastErrorCode == "audio_upload_failed")
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.failed.rawValue)
    }

    @Test func retryAfterMetadataSuccessAndAudioFailureCanCompleteUpload() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "audio-retry-complete", title: "重试完成", store: store)
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let failingClient = FakeRecordingUploadClient(
            result: .failure(RecordingUploadError.audioUploadFailed("network timeout")),
            events: [
                .metadataStarted,
                .metadataSucceeded(disposition: "acceptedNew"),
                .audioStarted
            ]
        )
        let firstCoordinator = RecordingUploadCoordinator(uploadClient: failingClient, jobStore: jobStore)

        _ = await firstCoordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)

        let retryClient = FakeRecordingUploadClient(
            result: .success(RecordingUploadResult(
                recordingID: metadata.id,
                metadataFileName: "metadata.json",
                audioFileName: "audio.m4a",
                metadataDisposition: "acceptedExisting",
                audioDisposition: "acceptedNew"
            )),
            events: [
                .metadataStarted,
                .metadataSucceeded(disposition: "acceptedExisting"),
                .audioStarted,
                .audioSucceeded(disposition: "acceptedNew")
            ]
        )
        let retryCoordinator = RecordingUploadCoordinator(uploadClient: retryClient, jobStore: jobStore)
        let failedMetadata = try store.loadMetadata(id: metadata.id)

        let status = await retryCoordinator.uploadAndWait(metadata: failedMetadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .uploaded)
        #expect(job.overallState == .succeeded)
        #expect(job.metadataStage == .succeeded)
        #expect(job.audioStage == .succeeded)
        #expect(job.attemptCount == 2)
        #expect(job.metadataDisposition == .acceptedExisting)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.uploaded.rawValue)
    }

    @Test func metadataConflictMarksLocalRecordingFailedWithReadableError() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "metadata-conflict-iphone", title: "冲突录音", store: store)
        let manager = RecordingManager(fileStore: store)
        let fakeClient = FakeRecordingUploadClient(result: .failure(
            RecordingUploadError.metadataUploadFailed("recording_metadata_conflict")
        ), events: [.metadataStarted])
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(
            metadata: metadata,
            settings: makePairedMacSnapshot(),
            recordingManager: manager
        )
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))
        let queue = RecordingUploadQueue(jobStore: jobStore, retryPolicy: .standard)

        #expect(status == .failed)
        #expect(job.overallState == .fatalFailed)
        #expect(job.metadataStage == .failed)
        #expect(job.isFatal)
        #expect(try queue.retryableJobs().isEmpty)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.failed.rawValue)
        #expect(coordinator.errorMessage(for: metadata)?.contains("recording_metadata_conflict") == true)
    }

    @Test func audioConflictMarksLocalRecordingFailedWithReadableError() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "audio-conflict-iphone", title: "音频冲突", store: store)
        let manager = RecordingManager(fileStore: store)
        let fakeClient = FakeRecordingUploadClient(result: .failure(
            RecordingUploadError.audioUploadFailed("recording_audio_conflict")
        ), events: [
            .metadataStarted,
            .metadataSucceeded(disposition: "acceptedNew"),
            .audioStarted
        ])
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let coordinator = RecordingUploadCoordinator(uploadClient: fakeClient, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(
            metadata: metadata,
            settings: makePairedMacSnapshot(),
            recordingManager: manager
        )
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))
        let queue = RecordingUploadQueue(jobStore: jobStore, retryPolicy: .standard)

        #expect(status == .failed)
        #expect(job.overallState == .fatalFailed)
        #expect(job.metadataStage == .succeeded)
        #expect(job.audioStage == .failed)
        #expect(job.isFatal)
        #expect(try queue.retryableJobs().isEmpty)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.failed.rawValue)
        #expect(coordinator.errorMessage(for: metadata)?.contains("recording_audio_conflict") == true)
    }

    @Test func staleInProgressUploadJobRecoversOnRecordingManagerLoad() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "stale-job-recovery", title: "中断任务", store: store, uploadStatus: "uploading")
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 100)
        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now)
        _ = try jobStore.markAttemptStarted(recordingID: metadata.id, now: now.addingTimeInterval(1))
        _ = try jobStore.applyProgress(recordingID: metadata.id, event: .metadataStarted, now: now.addingTimeInterval(2))

        let manager = RecordingManager(fileStore: store)
        let recoveredJob = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(manager.recordings.first?.uploadStatus == RecordingUploadStatus.failed.rawValue)
        #expect(recoveredJob.overallState == .retryableFailed)
        #expect(recoveredJob.metadataStage == .failed)
        #expect(recoveredJob.lastErrorCode == "upload_interrupted")
        #expect(recoveredJob.nextRetryAfter != nil)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.failed.rawValue)
    }

    @Test func resumableUploadProgressPersistsInLedger() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-ledger-progress", title: "进度任务", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 1_000)
        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now)

        let job = try jobStore.applyProgress(
            recordingID: metadata.id,
            event: .audioResumableSessionStarted(
                sessionID: "session-1",
                totalBytes: 10,
                chunkSize: 4,
                totalSHA256: "abc123",
                confirmedBytes: 4
            ),
            now: now.addingTimeInterval(1)
        )
        let loadedJob = try #require(try jobStore.loadJob(recordingID: metadata.id))
        let ledgerData = try Data(contentsOf: jobStore.ledgerURL())
        let ledgerText = String(data: ledgerData, encoding: .utf8) ?? ""

        #expect(job.uploadMode == .resumableChunks)
        #expect(loadedJob.resumableSessionID == "session-1")
        #expect(loadedJob.audioConfirmedBytes == 4)
        #expect(loadedJob.audioTotalBytes == 10)
        #expect(loadedJob.audioChunkCount == 3)
        #expect(loadedJob.audioCompletedChunkCount == 1)
        #expect(loadedJob.currentProgressFraction == 0.4)
        #expect(ledgerText.contains(#""version" : 2"#) || ledgerText.contains(#""version":2"#))
        #expect(!ledgerText.localizedCaseInsensitiveContains("sharedSecret"))
        #expect(!ledgerText.localizedCaseInsensitiveContains("hmac"))
    }

    @Test func resumableRetryableFailurePreservesSessionAndConfirmedBytes() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-failure-preserve", title: "失败保留", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 2_000)
        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now)
        _ = try jobStore.applyProgress(
            recordingID: metadata.id,
            event: .audioResumableSessionStarted(
                sessionID: "session-preserve",
                totalBytes: 12,
                chunkSize: 4,
                totalSHA256: "sha",
                confirmedBytes: 8
            ),
            now: now
        )

        let failed = try jobStore.markFailure(
            recordingID: metadata.id,
            classification: RecordingUploadFailureClassification(code: "network_failed", message: "network lost", isFatal: false),
            retryPolicy: .standard,
            now: now.addingTimeInterval(1)
        )

        #expect(failed.overallState == .retryableFailed)
        #expect(failed.resumableSessionID == "session-preserve")
        #expect(failed.audioConfirmedBytes == 8)
        #expect(failed.resumableState == .retryableFailed)
        #expect(failed.nextRetryAfter != nil)
    }

    @Test func staleResumableInProgressJobRecoversToPausedRetryable() throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "stale-resumable-job", title: "续传中断", store: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 3_000)
        _ = try jobStore.ensureJob(for: metadata, settings: makePairedMacSnapshot(), now: now)
        _ = try jobStore.markAttemptStarted(recordingID: metadata.id, now: now)
        _ = try jobStore.applyProgress(
            recordingID: metadata.id,
            event: .audioResumableSessionStarted(
                sessionID: "session-stale",
                totalBytes: 20,
                chunkSize: 5,
                totalSHA256: "sha",
                confirmedBytes: 10
            ),
            now: now
        )

        let recovered = try #require(try jobStore.recoverStaleInProgressJobs(now: now.addingTimeInterval(10)).first)

        #expect(recovered.overallState == .retryableFailed)
        #expect(recovered.audioStage == .failed)
        #expect(recovered.resumableState == .paused)
        #expect(recovered.resumableSessionID == "session-stale")
        #expect(recovered.audioConfirmedBytes == 10)
    }

    @Test func smallFileBelowThresholdUsesExistingSingleRequestUpload() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "single-request-small", title: "小文件", store: store, audioData: Data("small".utf8))
        let transport = FakeRecordingSecureUploadTransport()
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 64,
            resumableChunkSize: 4
        )

        let result = try await client.uploadRecording(metadata: metadata, settings: makePairedMacSnapshot())

        #expect(result.audioDisposition == "acceptedNew")
        #expect(transport.metadataUploadCount == 1)
        #expect(transport.singleFileUploadCount == 1)
        #expect(transport.resumableStartCount == 0)
        #expect(transport.chunkOffsets.isEmpty)
    }

    @Test func largeFileAboveThresholdUsesResumableStartChunksFinalize() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-large", title: "大文件", store: store, audioData: Data("abcdefghi".utf8))
        let transport = FakeRecordingSecureUploadTransport()
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 4,
            resumableChunkSize: 3
        )
        var events: [RecordingUploadProgressEvent] = []

        let result = try await client.uploadRecording(
            metadata: metadata,
            settings: makePairedMacSnapshot(),
            progress: { event in events.append(event) }
        )

        #expect(result.audioDisposition == "acceptedNew")
        #expect(transport.metadataUploadCount == 1)
        #expect(transport.singleFileUploadCount == 0)
        #expect(transport.resumableStartCount == 1)
        #expect(transport.chunkOffsets == [0, 3, 6])
        #expect(transport.finalizeCount == 1)
        #expect(events.contains(.audioResumableProgress(sessionID: "session-1", confirmedBytes: 9, totalBytes: 9, nextOffset: 9)))
    }

    @Test func resumableNetworkFailurePreservesProgressInCoordinatorLedger() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-network-failure", title: "网络中断", store: store, audioData: Data("abcdefghi".utf8))
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let transport = FakeRecordingSecureUploadTransport()
        transport.failChunkAtOffset = 3
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 4,
            resumableChunkSize: 3
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: client, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))
        let storedMetadata = try store.loadMetadata(id: metadata.id)

        #expect(status == .failed)
        #expect(job.overallState == .retryableFailed)
        #expect(job.metadataStage == .succeeded)
        #expect(job.audioStage == .failed)
        #expect(job.resumableSessionID == "session-1")
        #expect(job.audioConfirmedBytes == 3)
        #expect(storedMetadata.uploadStatus == RecordingUploadStatus.failed.rawValue)
        #expect(storedMetadata.uploadProgressConfirmedBytes == 3)
    }

    @Test func resumableRetryQueriesStatusAndResumesFromMacConfirmedOffset() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-retry-status", title: "续传恢复", store: store, audioData: Data("abcdefghi".utf8))
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let now = Date(timeIntervalSince1970: 4_000)
        var job = RecordingUploadJob.make(metadata: metadata, settings: makePairedMacSnapshot(), now: now)
        job.metadataStage = .succeeded
        job.metadataDisposition = .acceptedNew
        job.audioStage = .failed
        job.overallState = .retryableFailed
        job.uploadMode = .resumableChunks
        job.resumableState = .retryableFailed
        job.resumableSessionID = "session-1"
        job.audioConfirmedBytes = 3
        job.audioTotalBytes = 9
        job.audioChunkSize = 3
        let retryAudioChecksum = await CanonicalChecksumRuntime().checksum(
            fileURL: try store.audioURL(for: metadata),
            logicalToken: "Recordings/\(metadata.id)/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: rootURL.appendingPathComponent("Sync", isDirectory: true).appendingPathComponent("CanonicalChecksumCache", isDirectory: true)
        )
        job.audioTotalSHA256 = try #require(retryAudioChecksum.sha256)
        try jobStore.saveJob(job)
        let transport = FakeRecordingSecureUploadTransport()
        transport.statusConfirmedBytes = 6
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 4,
            resumableChunkSize: 3
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: client, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let completedJob = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .uploaded)
        #expect(transport.statusCount == 1)
        #expect(transport.metadataUploadCount == 0)
        #expect(transport.chunkOffsets == [6])
        #expect(completedJob.overallState == .succeeded)
        #expect(completedJob.audioConfirmedBytes == 9)
        #expect(try store.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.uploaded.rawValue)
    }

    @Test func resumableMissingServerSessionRestartsInsteadOfFailingForever() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(
            id: "resumable-restart-missing-session",
            title: "会话重建",
            store: store,
            audioData: Data("abcdefghi".utf8)
        )
        let audioURL = try store.audioURL(for: metadata)
        let checksum = try #require(await CanonicalChecksumRuntime().checksum(
            fileURL: audioURL,
            logicalToken: "Recordings/\(metadata.id)/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: rootURL
                .appendingPathComponent("Sync", isDirectory: true)
                .appendingPathComponent("CanonicalChecksumCache", isDirectory: true)
        ).sha256)
        let transport = FakeRecordingSecureUploadTransport()
        transport.statusError = SecureMacUploadError.serverRejected("upload_session_missing")
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 4,
            resumableChunkSize: 3
        )

        let result = try await client.uploadRecording(
            metadata: metadata,
            settings: makePairedMacSnapshot(),
            resumeContext: RecordingUploadResumeContext(
                metadataStage: .succeeded,
                metadataDisposition: .acceptedNew,
                resumableSessionID: "stale-session",
                audioConfirmedBytes: 3,
                audioTotalBytes: 9,
                audioChunkSize: 3,
                audioTotalSHA256: checksum
            )
        )

        #expect(result.audioDisposition == "acceptedNew")
        #expect(transport.statusCount == 1)
        #expect(transport.resumableStartCount == 1)
        #expect(transport.chunkOffsets == [0, 3, 6])
        #expect(transport.finalizeCount == 1)
    }

    @Test func resumableFinalizeAcceptedExistingMarksUploaded() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-finalize-existing", title: "重复完成", store: store, audioData: Data("abcdefghi".utf8))
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let transport = FakeRecordingSecureUploadTransport()
        transport.finalizeDisposition = "acceptedExisting"
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 4,
            resumableChunkSize: 3
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: client, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let completedJob = try #require(try jobStore.loadJob(recordingID: metadata.id))

        #expect(status == .uploaded)
        #expect(completedJob.audioDisposition == .acceptedExisting)
        #expect(completedJob.currentProgressFraction == 1)
    }

    @Test func resumableAudioConflictMarksFatalFailed() async throws {
        let (store, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "resumable-audio-conflict", title: "续传冲突", store: store, audioData: Data("abcdefghi".utf8))
        let manager = RecordingManager(fileStore: store)
        let jobStore = RecordingUploadJobStore(audioFileStore: store)
        let transport = FakeRecordingSecureUploadTransport()
        transport.chunkErrorAtOffset = (3, RecordingUploadError.audioUploadFailed("recording_audio_conflict"))
        let client = RecordingUploadClient(
            secureClient: transport,
            audioFileStore: store,
            resumableThresholdBytes: 4,
            resumableChunkSize: 3
        )
        let coordinator = RecordingUploadCoordinator(uploadClient: client, jobStore: jobStore)

        let status = await coordinator.uploadAndWait(metadata: metadata, settings: makePairedMacSnapshot(), recordingManager: manager)
        let job = try #require(try jobStore.loadJob(recordingID: metadata.id))
        let queue = RecordingUploadQueue(jobStore: jobStore, retryPolicy: .standard)

        #expect(status == .failed)
        #expect(job.overallState == .fatalFailed)
        #expect(job.resumableState == .fatalFailed)
        #expect(job.audioStage == .failed)
        #expect(job.audioConfirmedBytes == 3)
        #expect(try queue.retryableJobs().isEmpty)
    }

    @Test func secureUploadClientAudioMainPathUsesFileUploadNotWholeAudioData() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Rokurics", isDirectory: true)
            .appendingPathComponent("SecureMacUploadClient.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("upload(for: request, fromFile: fileURL)"))
        #expect(!source.contains("Data(contentsOf: audioURL)"))
        #expect(!source.contains("Data(contentsOf: fileURL)"))
    }

    @Test func iPhoneSyncButtonKeepsRecentTerminalControlPlaneStatusVisible() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Rokurics/MacConnectionView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("state.isSyncProgressActive || shouldShowRecentTerminalSyncState(state)"))
        #expect(source.contains("syncControlPlaneUpdatedAt"))
        #expect(source.contains("case .completed, .failed, .cancelled:"))
    }

    @Test func doubleTapRecordingIconResolvesMoveToTrashIntent() {
        #expect(RecordingRowIconInteraction.intent(for: .singleTap) == .none)
        #expect(RecordingRowIconInteraction.intent(for: .doubleTap) == .moveToTrash)
        #expect(RecordingRowIconInteraction.deletionTapCount == 2)
    }

    @Test func studyItemMetadataMissingSyncFieldsDefaultsSafely() throws {
        let metadata = StudyItemMetadata(
            recordingID: "legacy-sync-fields",
            title: "旧 metadata",
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 1,
            studyFiling: StudyFilingPath(type: "课堂")
        )
        var object = try #require(JSONSerialization.jsonObject(with: try Self.studyEncoder.encode(metadata)) as? [String: Any])
        object.removeValue(forKey: "isTrashed")
        object.removeValue(forKey: "trashedAt")
        object.removeValue(forKey: "modifiedByDeviceID")
        object.removeValue(forKey: "syncConflictStatus")
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try Self.studyDecoder.decode(StudyItemMetadata.self, from: data)

        #expect(decoded.isTrashed == false)
        #expect(decoded.trashedAt == nil)
        #expect(decoded.modifiedByDeviceID == nil)
        #expect(decoded.syncConflictStatus == nil)
    }

    @Test func studyLibraryManifestFiltersSensitiveCustomProperties() {
        let item = StudyItemMetadata(
            recordingID: "manifest-sensitive",
            title: "敏感字段",
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 1,
            customProperties: [
                "apiKey": "should-not-sync",
                "rawProviderResponse": "{}",
                "safePreview": "保留"
            ]
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-01",
            generatedAt: Date(timeIntervalSince1970: 2),
            items: [item.syncSanitized(modifiedByDeviceID: "iphone-01")],
            folders: []
        )

        #expect(manifest.hasValidChecksum)
        #expect(manifest.items.first?.customProperties == ["safePreview": "保留"])
    }

    @Test func applyingNewerMacBusinessMetadataPreservesIPhoneProcessingStateAndAudio() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let recording = try saveRecording(id: "sync-lww-iphone", title: "iPhone 标题", store: audioStore)
        let audioURL = try audioStore.audioURL(for: recording)
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let baseItem = try #require(studyStore.item(recordingID: recording.id))
        var macItem = baseItem
        macItem.title = "Mac 标题"
        macItem.transcriptionStatus = "transcribed"
        macItem.noteStatus = "generated"
        macItem.updatedAt = baseItem.updatedAt.addingTimeInterval(60)
        macItem.modifiedByDeviceID = "mac-01"
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "mac-01",
            generatedAt: macItem.updatedAt.addingTimeInterval(1),
            items: [macItem],
            folders: []
        )

        let result = try await studyStore.applySyncManifest(manifest, localDeviceID: "iphone-01")
        let updatedRecording = try audioStore.loadMetadata(id: recording.id)

        #expect(result.appliedItemCount == 1)
        #expect(updatedRecording.title == "Mac 标题")
        #expect(updatedRecording.transcriptionStatus == recording.transcriptionStatus)
        #expect(updatedRecording.noteStatus == recording.noteStatus)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test func applyingBusinessEqualMetadataOnlyItemPersistsLocalReceiptMarkerAcrossRefresh() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let item = StudyItemMetadata(
            itemID: "peer-owned-item-metadata-only",
            kind: .recordingBundle,
            title: "仅元数据录音",
            createdAt: Date(timeIntervalSince1970: 1_900),
            updatedAt: Date(timeIntervalSince1970: 1_910),
            recordingID: "metadata-only-existing-recording",
            duration: 6,
            modifiedByDeviceID: "mac-01"
        )
        try studyStore.save(item)

        // Without the local receipt marker an item that has no local audio is
        // intentionally omitted from the refreshed library projection.
        #expect(studyStore.item(itemID: item.itemID) == nil)

        let result = try await studyStore.applySyncManifest(
            StudyLibrarySyncManifest.make(
                deviceID: "mac-01",
                generatedAt: Date(timeIntervalSince1970: 1_920),
                items: [item],
                folders: []
            ),
            localDeviceID: "iphone-01"
        )
        studyStore.refresh()
        let persisted = try #require(studyStore.item(itemID: item.itemID))

        #expect(result.appliedItemCount == 1)
        #expect(persisted.customProperties["syncedMetadataOnly"] == "true")
        #expect(persisted.itemID == item.itemID)
        #expect(persisted.recordingID == item.recordingID)
    }

    @Test func applyingTrashTombstoneDoesNotDeleteRealFiles() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let recording = try saveRecording(id: "sync-trash-safe", title: "保留文件", store: audioStore)
        let audioURL = try audioStore.audioURL(for: recording)
        let metadataURL = try audioStore.makeMetadataURL(id: recording.id)
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let item = try #require(studyStore.item(recordingID: recording.id))
        let tombstoneUpdatedAt = item.updatedAt.addingTimeInterval(60)
        let tombstone = StudyLibrarySyncTombstone(
            id: "item:\(item.itemID)",
            entityKind: .item,
            entityID: item.itemID,
            operation: .trash,
            updatedAt: tombstoneUpdatedAt,
            modifiedByDeviceID: "mac-01"
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "mac-01",
            generatedAt: tombstoneUpdatedAt.addingTimeInterval(1),
            items: [],
            folders: [],
            tombstones: [tombstone]
        )

        let result = try await studyStore.applySyncManifest(manifest, localDeviceID: "iphone-01")
        let updatedRecording = try audioStore.loadMetadata(id: recording.id)

        #expect(result.tombstoneCount == 1)
        #expect(updatedRecording.isDeleted)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(FileManager.default.fileExists(atPath: metadataURL.path))
    }

    @Test func iphoneSyncManifestCarriesPendingUploadsForUnuploadedRecordings() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "pending-upload-01", title: "待上传", store: audioStore, uploadStatus: "localOnly")
        _ = try saveRecording(id: "pending-upload-02", title: "已上传", store: audioStore, uploadStatus: "uploaded")
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)

        let manifest = studyStore.makeSyncManifest(deviceID: "mac-01", generatedAt: Date(timeIntervalSince1970: 4))

        #expect(manifest.hasValidChecksum)
        #expect(manifest.pendingUploads.map(\.recordingID) == ["pending-upload-01"])
        #expect(manifest.pendingUploads.first?.localAudioRelativePath.hasSuffix(".m4a") == true)
    }

    @Test func pendingUploadBuildersPreservePersistedStudyItemIDForRecording() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let recording = try saveRecording(
            id: "pending-upload-real-item-id",
            title: "真实 Item ID",
            store: audioStore,
            uploadStatus: "localOnly"
        )
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        var persistedItem = try #require(studyStore.item(recordingID: recording.id))
        persistedItem.itemID = "peer-stable-study-item-id"
        try studyStore.save(persistedItem)

        let foregroundManifest = studyStore.makeSyncManifest(
            deviceID: "mac-01",
            generatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let backgroundManifest = await studyStore.makeSyncManifestInBackground(
            deviceID: "mac-01",
            generatedAt: Date(timeIntervalSince1970: 2_001)
        )

        #expect(foregroundManifest.pendingUploads.count == 1)
        #expect(foregroundManifest.pendingUploads.first?.recordingID == recording.id)
        #expect(foregroundManifest.pendingUploads.first?.itemID == persistedItem.itemID)
        #expect(backgroundManifest.pendingUploads.count == 1)
        #expect(backgroundManifest.pendingUploads.first?.recordingID == recording.id)
        #expect(backgroundManifest.pendingUploads.first?.itemID == persistedItem.itemID)
    }

    @Test func studyLibrarySyncStateMissingPendingUploadsDefaultsSafely() throws {
        let state = StudyLibrarySyncState(
            deviceID: "mac-01",
            pendingLocalChanges: 1,
            failedChanges: 1,
            lastError: "old"
        )
        var object = try #require(JSONSerialization.jsonObject(with: try Self.studyEncoder.encode(state)) as? [String: Any])
        object.removeValue(forKey: "pendingUploads")
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try Self.studyDecoder.decode(StudyLibrarySyncState.self, from: data)

        #expect(decoded.pendingUploads == 0)
        #expect(decoded.pendingLocalChanges == 1)
        #expect(decoded.lastKnownRemoteCommitID == nil)
    }

    @Test func studyLibrarySyncStateRecordsRemoteCommitIDAfterPullAndPush() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(rootURL: rootURL)

        store.recordPull(
            deviceID: "mac-01",
            remoteManifestHash: "remote-hash-1",
            remoteCommitID: "commit-pull",
            at: Date(timeIntervalSince1970: 10)
        )
        #expect(store.state.lastKnownRemoteCommitID == "commit-pull")
        #expect(store.state.lastRemoteManifestHash == "remote-hash-1")

        store.recordPush(
            deviceID: "mac-01",
            remoteManifestHash: "remote-hash-2",
            remoteCommitID: "commit-push",
            pendingUploads: 0,
            at: Date(timeIntervalSince1970: 20)
        )

        let reloaded = StudyLibrarySyncStateStore(rootURL: rootURL)
        #expect(reloaded.state.lastKnownRemoteCommitID == "commit-push")
        #expect(reloaded.state.lastRemoteManifestHash == "remote-hash-2")
        #expect(reloaded.state.pendingLocalChanges == 0)
        #expect(reloaded.state.failedChanges == 0)
    }

    @Test func studyLibrarySyncStateClearsSuccessfulPendingUploadsAndRetainsFailures() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(rootURL: rootURL)

        store.recordPendingUploads(
            deviceID: "mac-01",
            pendingUploads: 2,
            failedChanges: 1,
            error: "upload_failed"
        )

        #expect(store.state.pendingUploads == 2)
        #expect(store.state.failedChanges == 1)
        #expect(store.state.lastError == "upload_failed")

        store.recordPush(
            deviceID: "mac-01",
            remoteManifestHash: "remote-hash",
            remoteCommitID: "commit-after-upload",
            pendingUploads: 0,
            at: Date(timeIntervalSince1970: 30)
        )

        #expect(store.state.pendingUploads == 0)
        #expect(store.state.failedChanges == 0)
        #expect(store.state.lastError == nil)
        #expect(store.state.lastKnownRemoteCommitID == "commit-after-upload")
    }

    @Test func studyLibrarySyncFailureRetainsPendingChangesAndUploads() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(rootURL: rootURL)

        store.recordFailure(
            deviceID: "mac-01",
            error: "sync_failed",
            failedChanges: 3,
            pendingUploads: 2
        )

        let reloaded = StudyLibrarySyncStateStore(rootURL: rootURL)
        #expect(reloaded.state.pendingLocalChanges == 3)
        #expect(reloaded.state.failedChanges == 3)
        #expect(reloaded.state.pendingUploads == 2)
        #expect(reloaded.state.lastError == "sync_failed")
    }

    @Test func studyLibrarySyncControlPlaneSupersedesFreshRunsAndRejectsStaleUpdates() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(
            rootURL: rootURL,
            controlPlaneInactivityTimeout: 30
        )
        let startedAt = Date(timeIntervalSince1970: 2_100)

        #expect(store.recordControlPlane(
            deviceID: "mac-control-plane",
            syncRunID: "old-run",
            state: .inventoryExchanging,
            at: startedAt
        ))
        #expect(!store.recordControlPlane(
            deviceID: "mac-control-plane",
            syncRunID: "old-run",
            state: .syncStartSignalSent,
            at: startedAt.addingTimeInterval(1)
        ))
        #expect(store.state.activeSyncRunID == "old-run")
        #expect(store.state.syncControlPlaneState == .inventoryExchanging)

        #expect(store.recordControlPlane(
            deviceID: "mac-control-plane",
            syncRunID: "new-start-run",
            state: .syncStartSignalSent,
            at: startedAt.addingTimeInterval(2)
        ))
        #expect(store.state.activeSyncRunID == "new-start-run")
        #expect(store.state.syncControlPlaneState == .syncStartSignalSent)

        #expect(store.recordControlPlane(
            deviceID: "mac-control-plane",
            syncRunID: "new-inventory-run",
            state: .inventoryExchanging,
            at: startedAt.addingTimeInterval(3)
        ))
        #expect(store.state.activeSyncRunID == "new-inventory-run")
        #expect(store.state.syncControlPlaneState == .inventoryExchanging)

        #expect(!store.recordControlPlane(
            deviceID: "mac-control-plane",
            syncRunID: "new-inventory-run",
            state: .syncStartAcked,
            at: startedAt.addingTimeInterval(4)
        ))
        #expect(!store.recordControlPlane(
            deviceID: "mac-control-plane",
            syncRunID: "old-run",
            state: .planningTransfers,
            at: startedAt.addingTimeInterval(5)
        ))
        #expect(!store.recordControlPlane(
            deviceID: "mac-control-plane",
            syncRunID: "old-run",
            state: .completed,
            at: startedAt.addingTimeInterval(6)
        ))
        #expect(!store.recordControlPlane(
            deviceID: "mac-control-plane",
            syncRunID: "new-start-run",
            state: .failed,
            at: startedAt.addingTimeInterval(7)
        ))
        #expect(!store.recordPush(
            deviceID: "mac-control-plane",
            remoteManifestHash: "stale-hash",
            remoteCommitID: "stale-commit",
            syncRunID: "old-run",
            at: startedAt.addingTimeInterval(8)
        ))
        #expect(!store.recordFailure(
            deviceID: "mac-control-plane",
            error: "unrelated failure",
            syncRunID: "never-active-run"
        ))

        #expect(store.state.activeSyncRunID == "new-inventory-run")
        #expect(store.state.syncControlPlaneState == .inventoryExchanging)
        #expect(store.state.lastSuccessfulSyncAt == nil)
        #expect(store.state.lastRemoteManifestHash == nil)
        #expect(store.state.lastError == nil)
    }

    @Test func studyLibrarySyncControlPlaneWatchdogExpiresStartAckWithoutNextRequest() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(
            rootURL: rootURL,
            controlPlaneInactivityTimeout: 0.02
        )

        store.recordControlPlane(
            deviceID: "mac-control-plane",
            syncRunID: "sync-start-ack",
            state: .syncStartAcked
        )

        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline,
              store.state.syncControlPlaneState != .failed {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(store.state.activeSyncRunID == "sync-start-ack")
        #expect(store.state.syncControlPlaneState == .failed)
        #expect(store.state.lastError == "sync_control_plane_timeout")
    }

    @Test func gitBackedStudySyncRuntimeDefaultsToDisabled() {
        #expect(!StudyLibrarySyncRuntimeConfiguration.default.gitBackedSyncEnabled)
        #expect(!StudyLibrarySyncRuntimeConfiguration.disabled.gitBackedSyncEnabled)
        #expect(StudyLibrarySyncRuntimeConfiguration.disabledReason == "Git-backed study sync is disabled")
    }

    @Test func deviceStatusResponseMissingSyncRequestedDecodesFalse() throws {
        let response = try Self.studyDecoder.decode(DeviceStatusResponse.self, from: Data(#"{"ok":true}"#.utf8))

        #expect(response.ok)
        #expect(response.syncRequested == false)
        #expect(response.syncStartSignal == nil)
    }

    @Test func deviceStatusResponseMalformedSyncRequestedDecodesFalse() throws {
        let response = try Self.studyDecoder.decode(DeviceStatusResponse.self, from: Data(#"{"ok":true,"syncRequested":"yes"}"#.utf8))

        #expect(response.ok)
        #expect(response.syncRequested == false)
    }

    @Test func disabledSyncCoordinatorDoesNotStartAutomationOrClearPendingState() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        syncStateStore.replace(StudyLibrarySyncState(
            deviceID: "mac-disabled",
            pendingLocalChanges: 5,
            pendingUploads: 2,
            failedChanges: 1,
            lastError: "previous_failure"
        ))
        let connectionProvider = FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot())
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: connectionProvider,
            studyLibraryStore: studyStore,
            statusStore: statusStore,
            syncStateStore: syncStateStore,
            runtimeConfiguration: .default,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )

        coordinator.startForegroundMonitoring()
        let manualResult = await coordinator.synchronizeNow()

        #expect(manualResult == nil)
        #expect(!coordinator.isAutomaticSyncMonitoringActive)
        #expect(coordinator.syncSummary.statusText == StudyLibrarySyncRuntimeConfiguration.disabledStatusText)
        #expect(syncStateStore.state.pendingLocalChanges == 5)
        #expect(syncStateStore.state.pendingUploads == 2)
        #expect(syncStateStore.state.failedChanges == 1)
        #expect(syncStateStore.state.lastError == "previous_failure")
        coordinator.stopMonitoring()
    }

    @Test func disabledGitBackedSyncDoesNotTurnOffSecureManualUploads() {
        #expect(!StudyLibrarySyncRuntimeConfiguration.default.gitBackedSyncEnabled)
        #expect(SecureMacUploadClient.isHTTPSUploadEnabled)
    }

    @Test func localNetworkInventoryEncodesWithoutAbsolutePathsOrSecrets() throws {
        let artifactID = LocalNetworkSyncArtifactID.make(
            kind: .transcriptMarkdown,
            ownerID: "recording-01",
            logicalPathToken: "transcripts/recording-01/transcript.md"
        )
        let inventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-01",
                deviceName: "Vita iPhone",
                platform: .iPhone,
                generatedAt: Date(timeIntervalSince1970: 1),
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            artifacts: [
                LocalNetworkSyncArtifactEntry(
                    artifactID: artifactID,
                    kind: .transcriptMarkdown,
                    ownerID: "recording-01",
                    checksum: "abc",
                    size: 12,
                    updatedAt: Date(timeIntervalSince1970: 2),
                    availability: .local,
                    logicalPathToken: "transcripts/recording-01/transcript.md"
                )
            ]
        )

        let data = try Self.studyEncoder.encode(inventory)
        let json = String(data: data, encoding: .utf8) ?? ""
        let decoded = try Self.studyDecoder.decode(LocalNetworkSyncInventory.self, from: data)

        #expect(decoded.inventoryHash == inventory.inventoryHash)
        #expect(!json.contains("/Users/"))
        #expect(!json.lowercased().contains("sharedsecret"))
        #expect(!json.lowercased().contains("hmac"))
    }

    @MainActor
    @Test func localNetworkInventoryBuilderIncludesVersionedRecordingStudyAndArtifactSchema() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "schema-recording-01", title: "Schema Recording", store: audioStore)
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let inventory = await LocalNetworkSyncInventoryBuilder(
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore
        ).buildRuntimeSnapshot(
            deviceID: "iphone-schema",
            deviceName: "Schema iPhone",
            lastKnownPeerRevision: "peer-revision",
            generatedAt: Date(timeIntervalSince1970: 4_000)
        ).inventory

        let recording = try #require(inventory.recordings.first { $0.recordingID == metadata.id })
        let studyItem = try #require(inventory.studyItems.first { $0.recordingID == metadata.id })
        let metadataArtifact = try #require(inventory.artifacts.first { $0.kind == .metadataJSON && $0.ownerID == metadata.id })
        let metadataObject = try #require(inventory.objects.first { $0.objectID == metadataArtifact.artifactID })
        let studyItemObject = try #require(inventory.objects.first { $0.objectID == "studyItem:\(studyItem.itemID)" })
        let encoded = String(data: try Self.studyEncoder.encode(inventory), encoding: .utf8) ?? ""

        #expect(inventory.schemaVersion == LocalNetworkSyncInventory.appSchemaVersion)
        #expect(inventory.sourceDeviceID == "iphone-schema")
        #expect(inventory.sourcePlatform == .iPhone)
        #expect(recording.title == metadata.title)
        #expect(recording.createdAt == metadata.createdAt)
        #expect(recording.tombstone == false)
        #expect(recording.audioAvailability == .local)
        #expect(recording.audioChecksum == SecureUploadUtilities.sha256Hex(Data("audio".utf8)))
        #expect(recording.uploadStatus == metadata.uploadStatus)
        #expect(recording.transcriptionStatus == metadata.transcriptionStatus)
        #expect(recording.noteStatus == metadata.noteStatus)
        #expect(recording.sourceDeviceID == "iphone-schema")
        #expect(recording.artifactRefs?.contains(metadataArtifact.artifactID) == true)
        #expect(studyItem.path != nil)
        #expect(metadataArtifact.logicalPathToken == metadata.relativeMetadataPath)
        #expect(metadataArtifact.localAvailability == .local)
        #expect(metadataArtifact.autoDownloadAllowed == true)
        #expect(metadataObject.objectKind == .recordingMetadata)
        #expect(metadataObject.fileName == "metadata.json")
        #expect(metadataObject.sha256 == metadataArtifact.checksum)
        #expect(metadataObject.size == metadataArtifact.size)
        #expect(studyItemObject.objectKind == .studyItem)
        #expect(studyItemObject.displayTitle == studyItem.title)
        #expect(studyItemObject.updatedAt == studyItem.updatedAt)
        #expect(!encoded.contains(rootURL.path))
        #expect(!encoded.lowercased().contains("sharedsecret"))
        #expect(!encoded.lowercased().contains("hmac"))
    }

    @Test func artifactSanitizerRejectsTraversalAbsoluteAndEscapePaths() throws {
        #expect(throws: LocalNetworkSyncArtifactValidationError.pathTraversal) {
            try LocalNetworkSyncArtifactID.validateLogicalPathToken("transcripts/../secret.txt")
        }
        #expect(throws: LocalNetworkSyncArtifactValidationError.absolutePath) {
            try LocalNetworkSyncArtifactID.validateLogicalPathToken("/Users/vita/secret.txt")
        }
        #expect(throws: LocalNetworkSyncArtifactValidationError.invalidArtifactID) {
            try LocalNetworkSyncArtifactID.validate("../artifact")
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsArtifactEscapeTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let outsideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsOutside-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outsideURL) }
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        let symlinkURL = rootURL.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideURL)

        #expect(throws: LocalNetworkSyncArtifactValidationError.unsafeResolvedPath) {
            _ = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: "link/escape.md")
        }
    }

    @Test func localNetworkDiffPlannerSchedulesTranscriptDownloadButNotAudioDownload() {
        let generatedAt = Date(timeIntervalSince1970: 1)
        let local = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-01",
                deviceName: "iPhone",
                platform: .iPhone,
                generatedAt: generatedAt,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            )
        )
        let transcriptID = LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "recording-01", logicalPathToken: "transcripts/recording-01/transcript.md")
        let audioID = LocalNetworkSyncArtifactID.make(kind: .audio, ownerID: "recording-01", logicalPathToken: "audio/inbox/recording-01/audio.m4a")
        let peer = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: generatedAt,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            artifacts: [
                LocalNetworkSyncArtifactEntry(
                    artifactID: transcriptID,
                    kind: .transcriptMarkdown,
                    ownerID: "recording-01",
                    checksum: "tx",
                    size: 20,
                    updatedAt: generatedAt,
                    availability: .local,
                    logicalPathToken: "transcripts/recording-01/transcript.md"
                ),
                LocalNetworkSyncArtifactEntry(
                    artifactID: audioID,
                    kind: .audio,
                    ownerID: "recording-01",
                    checksum: nil,
                    size: 5,
                    updatedAt: generatedAt,
                    availability: .local,
                    logicalPathToken: "audio/inbox/recording-01/audio.m4a"
                )
            ]
        )

        let plan = LocalNetworkSyncDiffPlanner().plan(local: local, peer: peer, lastSuccessfulSyncAt: nil)

        #expect(plan.downloadArtifactActions.map(\.entityID).contains(transcriptID))
        #expect(!plan.downloadArtifactActions.map(\.entityID).contains(audioID))
        #expect(plan.noOps.contains { $0.entityID == audioID && $0.reason == "audio_auto_download_disabled" })
    }

    @Test func localNetworkDiffPlannerSchedulesExistingUploadWhenMacMissingIPhoneAudio() {
        let generatedAt = Date(timeIntervalSince1970: 1)
        let localRecording = LocalNetworkSyncRecordingEntry(
            recordingID: "recording-audio-01",
            metadataHash: "metadata-same",
            audioAvailable: true,
            audioChecksum: nil,
            audioSize: 5,
            uploadLedgerState: nil,
            receiveStatus: nil,
            processingStatus: nil,
            updatedAt: generatedAt,
            deleted: false,
            title: "iPhone audio",
            createdAt: generatedAt,
            tombstone: false,
            audioAvailability: .local,
            uploadStatus: "localOnly",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            sourceDeviceID: "iphone-01",
            artifactRefs: nil
        )
        let peerRecording = LocalNetworkSyncRecordingEntry(
            recordingID: "recording-audio-01",
            metadataHash: "metadata-same",
            audioAvailable: false,
            audioChecksum: nil,
            audioSize: nil,
            uploadLedgerState: nil,
            receiveStatus: "metadataReceived",
            processingStatus: "awaitingAudio",
            updatedAt: generatedAt,
            deleted: false,
            title: "iPhone audio",
            createdAt: generatedAt,
            tombstone: false,
            audioAvailability: .missing,
            uploadStatus: nil,
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            sourceDeviceID: nil,
            artifactRefs: nil
        )
        let local = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-01",
                deviceName: "iPhone",
                platform: .iPhone,
                generatedAt: generatedAt,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [localRecording]
        )
        let peer = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: generatedAt,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [peerRecording]
        )

        let plan = LocalNetworkSyncDiffPlanner().plan(local: local, peer: peer, lastSuccessfulSyncAt: nil)

        #expect(plan.uploadRecordingAudioActions.contains { $0.entityID == "recording-audio-01" && $0.reason == "peer_metadata_only" })
        #expect(plan.existingUploadActions == plan.uploadRecordingAudioActions)
    }

    @Test func localNetworkDiffPlannerDoesNotUploadWhenPeerAudioMatchesHashAndSize() {
        let generatedAt = Date(timeIntervalSince1970: 1)
        let checksum = SecureUploadUtilities.sha256Hex(Data("same-audio".utf8))
        let localRecording = LocalNetworkSyncRecordingEntry(
            recordingID: "recording-audio-noop",
            metadataHash: "metadata-same",
            audioAvailable: true,
            audioChecksum: checksum,
            audioSize: 10,
            uploadLedgerState: "succeeded",
            receiveStatus: nil,
            processingStatus: nil,
            updatedAt: generatedAt,
            deleted: false,
            title: "iPhone audio",
            createdAt: generatedAt,
            tombstone: false,
            audioAvailability: .local,
            uploadStatus: "uploaded",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            sourceDeviceID: "iphone-01",
            artifactRefs: nil
        )
        var peerRecording = localRecording
        peerRecording.audioAvailable = true
        peerRecording.audioAvailability = .local
        peerRecording.receiveStatus = "completed"
        peerRecording.sourceDeviceID = nil
        let local = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-01",
                deviceName: "iPhone",
                platform: .iPhone,
                generatedAt: generatedAt,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [localRecording]
        )
        let peer = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: generatedAt,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [peerRecording]
        )

        let plan = LocalNetworkSyncDiffPlanner().plan(local: local, peer: peer, lastSuccessfulSyncAt: nil)

        #expect(plan.uploadRecordingAudioActions.isEmpty)
        #expect(plan.existingUploadActions.isEmpty)
        #expect(plan.noOps.contains { $0.entityID == "recording-audio-noop" && $0.reason == "checksum_equal" })
    }

    @Test func recordingAudioUploadDecisionMatrixCoversHardRules() {
        let signature = RecordingAudioSignature(sha256: "abcdef1234567890", size: 42)
        let otherSignature = RecordingAudioSignature(sha256: "feedface12345678", size: 42)
        let local = RecordingLocalAudioState.available(signature)

        let viewRefresh = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: local,
            peerAudioState: .missing,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .folderViewRefresh,
            syncRunID: "run",
            objectID: "recordingAudio:decision",
            recordingID: "decision"
        )
        let localMissing = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .missing,
            peerAudioState: .missing,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .periodicSync,
            syncRunID: "run",
            objectID: "recordingAudio:decision",
            recordingID: "decision"
        )
        let peerMatches = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: local,
            peerAudioState: .available(signature),
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .periodicSync,
            syncRunID: "run",
            objectID: "recordingAudio:decision",
            recordingID: "decision"
        )
        let queued = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: local,
            peerAudioState: .metadataOnly,
            transferJobState: .queued,
            ledgerState: .none,
            triggerSource: .periodicSync,
            syncRunID: "run",
            objectID: "recordingAudio:decision",
            recordingID: "decision"
        )
        let completedPeerMatches = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: local,
            peerAudioState: .available(signature),
            transferJobState: .none,
            ledgerState: .completed(signature),
            triggerSource: .manualSyncMacHint,
            syncRunID: "run",
            objectID: "recordingAudio:decision",
            recordingID: "decision"
        )
        let metadataOnly = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: local,
            peerAudioState: .metadataOnly,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .manualSyncIPhone,
            syncRunID: "run",
            objectID: "recordingAudio:decision",
            recordingID: "decision"
        )
        let missing = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: local,
            peerAudioState: .missing,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .periodicSync,
            syncRunID: "run",
            objectID: "recordingAudio:decision",
            recordingID: "decision"
        )
        let mismatch = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: local,
            peerAudioState: .different(otherSignature),
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .periodicSync,
            syncRunID: "run",
            objectID: "recordingAudio:decision",
            recordingID: "decision"
        )
        let peerUnknownPeriodic = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: local,
            peerAudioState: .unknown,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .periodicSync,
            syncRunID: "run",
            objectID: "recordingAudio:decision",
            recordingID: "decision"
        )
        let peerUnknownManual = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: local,
            peerAudioState: .unknown,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .manualUploadButton,
            syncRunID: "run",
            objectID: "recordingAudio:decision",
            recordingID: "decision"
        )
        let retryPendingPeriodic = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: local,
            peerAudioState: .missing,
            transferJobState: .none,
            ledgerState: .retryPending,
            triggerSource: .periodicSync,
            syncRunID: "run",
            objectID: "recordingAudio:decision",
            recordingID: "decision"
        )
        let retryDrainer = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: local,
            peerAudioState: .unknown,
            transferJobState: .none,
            ledgerState: .retryPending,
            triggerSource: .retryDrainer,
            syncRunID: "run",
            objectID: "recordingAudio:decision",
            recordingID: "decision"
        )

        #expect(viewRefresh.kind == .suppress)
        #expect(viewRefresh.diagnosticStage == "uploadDecisionSuppressedViewRefreshOnly")
        #expect(localMissing.kind == .fail)
        #expect(localMissing.diagnosticStage == "uploadDecisionFailedLocalAudioMissing")
        #expect(peerMatches.kind == .noOp)
        #expect(peerMatches.diagnosticStage == "uploadDecisionNoOpPeerAlreadyHasSameAudio")
        #expect(queued.kind == .suppress)
        #expect(queued.diagnosticStage == "uploadDecisionSuppressedQueued")
        #expect(completedPeerMatches.kind == .suppress)
        #expect(completedPeerMatches.diagnosticStage == "uploadDecisionSuppressedCompletedAndPeerMatches")
        #expect(metadataOnly.shouldCreateUploadJob)
        #expect(metadataOnly.diagnosticStage == "uploadDecisionUploadBecausePeerMetadataOnly")
        #expect(missing.shouldCreateUploadJob)
        #expect(missing.diagnosticStage == "uploadDecisionUploadBecausePeerMissingAudio")
        #expect(mismatch.kind == .fail)
        #expect(mismatch.reasonCode == "peer_audio_conflict")
        #expect(peerUnknownPeriodic.kind == .suppress)
        #expect(peerUnknownPeriodic.reasonCode == "peer_audio_unknown_deferred")
        #expect(peerUnknownManual.shouldCreateUploadJob)
        #expect(peerUnknownManual.reasonCode == "manual_force_peer_unknown")
        #expect(retryPendingPeriodic.kind == .suppress)
        #expect(retryPendingPeriodic.displayState == .retryPending)
        #expect(retryDrainer.shouldCreateUploadJob)
        #expect(retryDrainer.reasonCode == "retry_drainer_peer_unknown")
    }

    @Test func localNetworkChecksumCacheHitsAndInvalidatesBySizeAndModificationDate() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsChecksumCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("audio.m4a", isDirectory: false)
        try Data("first-audio".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 10)], ofItemAtPath: fileURL.path)

        let runtime = CanonicalChecksumRuntime()
        let cacheDirectoryURL = rootURL.appendingPathComponent("ChecksumCache", isDirectory: true)
        let first = await runtime.checksum(
            fileURL: fileURL,
            logicalToken: "Recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: cacheDirectoryURL
        )
        let second = await runtime.checksum(
            fileURL: fileURL,
            logicalToken: "Recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: cacheDirectoryURL
        )

        #expect(first.event == CanonicalChecksumCacheEvent.miss)
        #expect(second.event == CanonicalChecksumCacheEvent.hit)
        #expect(first.sha256 == second.sha256)
        #expect(first.hashComputed)
        #expect(!second.hashComputed)

        try Data("changed-audio-size".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 20)], ofItemAtPath: fileURL.path)
        let third = await runtime.checksum(
            fileURL: fileURL,
            logicalToken: "Recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: cacheDirectoryURL
        )

        #expect(third.event == CanonicalChecksumCacheEvent.stale)
        #expect(third.hashComputed)
        #expect(third.sha256 != first.sha256)
    }

    @Test func localNetworkDiffPlannerMarksBothChangedConflictAndTombstoneWinner() {
        let lastSync = Date(timeIntervalSince1970: 100)
        let localFolder = LocalNetworkSyncFolderEntry(
            folderID: "folder-conflict",
            parentID: nil,
            path: "Course",
            name: "Local",
            colorToken: nil,
            updatedAt: Date(timeIntervalSince1970: 130),
            revisionHash: "local",
            deleted: false
        )
        let peerFolder = LocalNetworkSyncFolderEntry(
            folderID: "folder-conflict",
            parentID: nil,
            path: "Course",
            name: "Peer",
            colorToken: nil,
            updatedAt: Date(timeIntervalSince1970: 140),
            revisionHash: "peer",
            deleted: false
        )
        let localTombstoneVictim = LocalNetworkSyncFolderEntry(
            folderID: "folder-tombstone",
            parentID: nil,
            path: "Old",
            name: "Old",
            colorToken: nil,
            updatedAt: Date(timeIntervalSince1970: 10),
            revisionHash: "old-local",
            deleted: false
        )
        let peerTombstone = LocalNetworkSyncFolderEntry(
            folderID: "folder-tombstone",
            parentID: nil,
            path: "Old",
            name: "Old",
            colorToken: nil,
            updatedAt: Date(timeIntervalSince1970: 20),
            revisionHash: "old-peer-deleted",
            deleted: true
        )
        let local = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-01",
                deviceName: "iPhone",
                platform: .iPhone,
                generatedAt: lastSync,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            folders: [localFolder, localTombstoneVictim]
        )
        let peer = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: lastSync,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            folders: [peerFolder, peerTombstone]
        )

        let conflictPlan = LocalNetworkSyncDiffPlanner().plan(local: local, peer: peer, lastSuccessfulSyncAt: lastSync)
        let tombstonePlan = LocalNetworkSyncDiffPlanner().plan(local: local, peer: peer, lastSuccessfulSyncAt: nil)

        #expect(conflictPlan.conflictActions.contains { $0.entityID == "folder-conflict" && $0.reason == "both_changed_after_last_sync" })
        #expect(tombstonePlan.downloadMetadataActions.contains { $0.entityID == "folder-tombstone" && $0.reason == "peer_tombstone_wins" })
    }

    @Test func recordingBundleStudyItemActionUsesItemIDAndScopedManifestCoversTombstone() throws {
        let recordingID = "scoped-recording"
        let item = StudyItemMetadata(
            recordingID: recordingID,
            title: "Scoped item",
            createdAt: Date(timeIntervalSince1970: 100),
            duration: 8,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let itemEntry = LocalNetworkSyncStudyItemEntry(
            itemID: item.itemID,
            kind: item.kind,
            title: item.title,
            folderIDs: item.folderIDs,
            recordingID: recordingID,
            updatedAt: item.updatedAt,
            revisionHash: item.localNetworkStudyItemBusinessSignatureV2,
            deleted: false
        )
        let localInventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-scoped",
                deviceName: "iPhone",
                platform: .iPhone,
                generatedAt: item.updatedAt,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            studyItems: [itemEntry]
        )
        let plan = LocalNetworkSyncDiffPlanner().plan(
            local: localInventory,
            peer: emptyLocalNetworkInventory(deviceID: "mac-scoped", platform: .Mac),
            lastSuccessfulSyncAt: nil
        )
        let itemAction = try #require(plan.uploadMetadataActions.first {
            $0.entityKind == "studyItem"
        })

        #expect(itemAction.entityID == item.itemID)
        #expect(localInventory.objects.first { $0.objectKind == .studyItem }?.ownerID == item.itemID)

        // A mixed-version peer can still advertise the historical recording
        // owner in the object entry. The objectID remains authoritative.
        var legacyOwnerInventory = localInventory
        if let objectIndex = legacyOwnerInventory.objects.firstIndex(where: { $0.objectKind == .studyItem }) {
            legacyOwnerInventory.objects[objectIndex].ownerID = recordingID
        }
        let mixedVersionPlan = LocalNetworkSyncDiffPlanner().plan(
            local: legacyOwnerInventory,
            peer: emptyLocalNetworkInventory(deviceID: "mac-legacy-owner", platform: .Mac),
            lastSuccessfulSyncAt: nil
        )
        #expect(mixedVersionPlan.uploadMetadataActions.contains {
            $0.entityKind == "studyItem" && $0.entityID == item.itemID
        })

        let deletedAt = Date(timeIntervalSince1970: 300)
        let tombstonedItem = StudyItemMetadata(
            itemID: item.itemID,
            kind: item.kind,
            title: item.title,
            createdAt: item.createdAt,
            updatedAt: deletedAt,
            recordingID: recordingID,
            duration: item.duration,
            isTrashed: true,
            trashedAt: deletedAt
        )
        let recording = LocalNetworkSyncRecordingEntry(
            recordingID: recordingID,
            metadataHash: tombstonedItem.localNetworkRecordingBusinessSignatureV2,
            audioChecksum: nil,
            audioSize: nil,
            uploadLedgerState: nil,
            receiveStatus: "tombstoned",
            processingStatus: nil,
            updatedAt: deletedAt,
            deleted: true,
            tombstone: true
        )
        let tombstone = StudyLibrarySyncTombstone(
            id: "item:\(item.itemID):delete",
            entityKind: .item,
            entityID: item.itemID,
            operation: .delete,
            updatedAt: deletedAt,
            modifiedByDeviceID: "iphone-scoped"
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "iphone-scoped",
            generatedAt: deletedAt,
            items: [tombstonedItem],
            folders: [],
            tombstones: [tombstone],
            recordings: [recording]
        )

        let scoped = try LocalNetworkSyncEngine.metadataManifest(manifest, scopedTo: [itemAction])
        #expect(scoped.items.map(\.itemID) == [item.itemID])
        #expect(scoped.tombstones.map(\.entityID) == [item.itemID])
        #expect(scoped.recordings.map(\.recordingID) == [recordingID])

        let legacyOwnerAction = LocalNetworkSyncDiffAction(
            id: "legacy-study-item-owner",
            kind: .uploadMetadata,
            entityKind: "studyItem",
            entityID: recordingID,
            reason: "legacy_recording_owner"
        )
        let legacyScoped = try LocalNetworkSyncEngine.metadataManifest(
            manifest,
            scopedTo: [legacyOwnerAction]
        )
        #expect(legacyScoped.items.map(\.itemID) == [item.itemID])
        #expect(legacyScoped.tombstones.map(\.entityID) == [item.itemID])

        let missingAction = LocalNetworkSyncDiffAction(
            id: "missing-study-item",
            kind: .uploadMetadata,
            entityKind: "studyItem",
            entityID: "missing-item",
            reason: "missing"
        )
        do {
            _ = try LocalNetworkSyncEngine.metadataManifest(manifest, scopedTo: [missingAction])
            Issue.record("Expected an uncovered metadata action to fail")
        } catch {
            #expect(error.localizedDescription.contains("scoped_manifest_action_coverage"))
        }
    }

    @Test func recordingScopedManifestRequiresRecordingEntryOrDeletionTombstone() throws {
        let recordingID = "recording-coverage-proof"
        let now = Date(timeIntervalSince1970: 420)
        let item = StudyItemMetadata(
            recordingID: recordingID,
            title: "Recording coverage",
            createdAt: now.addingTimeInterval(-20),
            duration: 20,
            updatedAt: now
        )
        let pendingUpload = PendingRecordingUpload(
            itemID: item.itemID,
            recordingID: recordingID,
            localAudioRelativePath: "Audio/recording-coverage-proof.m4a",
            targetDeviceID: "mac-coverage",
            createdAt: now,
            updatedAt: now
        )
        let action = LocalNetworkSyncDiffAction(
            id: "recording-coverage-action",
            kind: .uploadMetadata,
            entityKind: "recording",
            entityID: recordingID,
            reason: "recording_metadata"
        )
        let tombstoneAction = LocalNetworkSyncDiffAction(
            id: "recording-coverage-tombstone-action",
            kind: .uploadMetadata,
            entityKind: "recording",
            entityID: recordingID,
            reason: "local_tombstone_wins"
        )

        let itemAndPendingOnly = StudyLibrarySyncManifest.make(
            deviceID: "iphone-coverage",
            generatedAt: now,
            items: [item],
            folders: [],
            pendingUploads: [pendingUpload]
        )
        do {
            _ = try LocalNetworkSyncEngine.metadataManifest(itemAndPendingOnly, scopedTo: [action])
            Issue.record("An item or pending upload must not cover a recording action")
        } catch {
            #expect(error.localizedDescription.contains("scoped_manifest_action_coverage"))
        }

        let restoreMarker = StudyLibrarySyncTombstone(
            id: "restore:\(item.itemID)",
            entityKind: .item,
            entityID: item.itemID,
            operation: .restore,
            updatedAt: now,
            modifiedByDeviceID: "iphone-coverage"
        )
        let restoreOnly = StudyLibrarySyncManifest.make(
            deviceID: "iphone-coverage",
            generatedAt: now,
            items: [],
            folders: [],
            tombstones: [restoreMarker]
        )
        do {
            _ = try LocalNetworkSyncEngine.metadataManifest(restoreOnly, scopedTo: [tombstoneAction])
            Issue.record("A restore marker must not cover a recording action")
        } catch {
            #expect(error.localizedDescription.contains("scoped_manifest_action_coverage"))
        }

        var deletionMarker = restoreMarker
        deletionMarker.id = "trash:\(item.itemID)"
        deletionMarker.operation = .trash
        let deletionOnly = StudyLibrarySyncManifest.make(
            deviceID: "iphone-coverage",
            generatedAt: now,
            items: [],
            folders: [],
            tombstones: [deletionMarker]
        )
        let deletionScoped = try LocalNetworkSyncEngine.metadataManifest(
            deletionOnly,
            scopedTo: [tombstoneAction]
        )
        #expect(deletionScoped.recordings.isEmpty)
        #expect(deletionScoped.tombstones == [deletionMarker])

        let recordingEntry = LocalNetworkSyncRecordingEntry(
            recordingID: recordingID,
            metadataHash: "recording-business-signature",
            audioChecksum: nil,
            audioSize: nil,
            uploadLedgerState: nil,
            receiveStatus: nil,
            processingStatus: nil,
            updatedAt: now,
            deleted: false
        )
        let recordingScoped = try LocalNetworkSyncEngine.metadataManifest(
            StudyLibrarySyncManifest.make(
                deviceID: "iphone-coverage",
                generatedAt: now,
                items: [item],
                folders: [],
                pendingUploads: [pendingUpload],
                recordings: [recordingEntry]
            ),
            scopedTo: [action]
        )
        #expect(recordingScoped.recordings == [recordingEntry])
    }

    @Test func conflictIsolationClosesLegacyItemRecordingArtifactAndFolderDescendants() {
        let parentFolderID = "folder-parent"
        let childFolderID = "folder-child"
        let legacyConflictRecordingID = "recording-legacy-conflict"
        let descendantRecordingID = "recording-descendant-conflict"
        let unrelatedRecordingID = "recording-unrelated"
        let legacyItemID = StudyItemMetadata.recordingBundleItemID(for: legacyConflictRecordingID)
        let descendantItemID = StudyItemMetadata.recordingBundleItemID(for: descendantRecordingID)
        let artifactID = "artifact-conflicted"
        let descendantArtifactID = "artifact-descendant"
        let now = Date(timeIntervalSince1970: 500)
        let folders = [
            LocalNetworkSyncFolderEntry(
                folderID: parentFolderID,
                parentID: nil,
                path: "Parent",
                name: "Parent",
                colorToken: nil,
                updatedAt: now,
                revisionHash: "parent",
                deleted: false
            ),
            LocalNetworkSyncFolderEntry(
                folderID: childFolderID,
                parentID: parentFolderID,
                path: "Parent/Child",
                name: "Child",
                colorToken: nil,
                updatedAt: now,
                revisionHash: "child",
                deleted: false
            )
        ]
        let items = [
            LocalNetworkSyncStudyItemEntry(
                itemID: legacyItemID,
                kind: .recordingBundle,
                title: "Legacy owner conflict",
                folderIDs: [],
                recordingID: legacyConflictRecordingID,
                updatedAt: now,
                revisionHash: "legacy",
                deleted: false
            ),
            LocalNetworkSyncStudyItemEntry(
                itemID: descendantItemID,
                kind: .recordingBundle,
                title: "Descendant conflict",
                folderIDs: [childFolderID],
                recordingID: descendantRecordingID,
                updatedAt: now,
                revisionHash: "descendant",
                deleted: false
            )
        ]
        let artifacts = [
            LocalNetworkSyncArtifactEntry(
                artifactID: artifactID,
                kind: .transcriptMarkdown,
                ownerID: legacyConflictRecordingID,
                checksum: "legacy-hash",
                size: 1,
                updatedAt: now,
                availability: .local,
                logicalPathToken: "transcripts/legacy.md"
            ),
            LocalNetworkSyncArtifactEntry(
                artifactID: descendantArtifactID,
                kind: .noteMarkdown,
                ownerID: descendantRecordingID,
                checksum: "descendant-hash",
                size: 1,
                updatedAt: now,
                availability: .local,
                logicalPathToken: "notes/descendant.md"
            )
        ]
        let inventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-conflict-closure",
                deviceName: "iPhone",
                platform: .iPhone,
                generatedAt: now,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            folders: folders,
            studyItems: items,
            artifacts: artifacts
        )
        func action(
            _ kind: LocalNetworkSyncDiffActionKind,
            _ entityKind: String,
            _ entityID: String
        ) -> LocalNetworkSyncDiffAction {
            LocalNetworkSyncDiffAction(
                id: "\(kind.rawValue):\(entityKind):\(entityID)",
                kind: kind,
                entityKind: entityKind,
                entityID: entityID,
                reason: "test"
            )
        }
        var source = LocalNetworkSyncDiffPlan()
        source.conflictActions = [
            action(.conflict, "studyItem", legacyConflictRecordingID),
            action(.conflict, "folder", parentFolderID)
        ]
        source.uploadMetadataActions = [
            action(.uploadMetadata, "studyItem", legacyConflictRecordingID),
            action(.uploadMetadata, "studyItem", descendantRecordingID),
            action(.uploadMetadata, "folder", childFolderID),
            action(.uploadMetadata, "recording", unrelatedRecordingID)
        ]
        source.uploadRecordingAudioActions = [
            action(.uploadRecordingAudio, "recording", legacyConflictRecordingID),
            action(.uploadRecordingAudio, "recording", descendantRecordingID),
            action(.uploadRecordingAudio, "recording", unrelatedRecordingID)
        ]
        source.uploadArtifactActions = [
            action(.uploadArtifact, "artifact", artifactID),
            action(.uploadArtifact, "artifact", descendantArtifactID)
        ]

        let isolated = LocalNetworkSyncEngine.conflictIsolatedExecutionPlan(
            source,
            localInventory: inventory,
            peerInventory: emptyLocalNetworkInventory(deviceID: "mac-conflict-closure", platform: .Mac)
        )

        #expect(isolated.blockedRecordingIDs == [legacyConflictRecordingID, descendantRecordingID])
        #expect(isolated.plan.uploadMetadataActions.map(\.entityID) == [unrelatedRecordingID])
        #expect(isolated.plan.uploadRecordingAudioActions.map(\.entityID) == [unrelatedRecordingID])
        #expect(isolated.plan.uploadArtifactActions.isEmpty)
        #expect(isolated.plan.conflictActions == source.conflictActions)
    }

    @Test func conflictIsolationFailsClosedWhenArtifactConflictHasNoArtifactEntryOwner() {
        let recordingID = "recording-unresolved-artifact-owner"
        let artifactID = "artifact-object-without-artifact-entry"
        let now = Date(timeIntervalSince1970: 560)
        let recording = LocalNetworkSyncRecordingEntry(
            recordingID: recordingID,
            metadataHash: "recording-hash",
            audioChecksum: "audio-hash",
            audioSize: 8,
            uploadLedgerState: nil,
            receiveStatus: nil,
            processingStatus: nil,
            updatedAt: now,
            deleted: false
        )
        let artifactObject = LocalNetworkSyncObjectEntry(
            objectID: artifactID,
            objectKind: .transcriptMarkdown,
            ownerID: recordingID,
            displayTitle: "Transcript",
            fileName: "transcript.md",
            logicalName: "Transcript",
            sha256: "artifact-hash",
            size: 12,
            updatedAt: now,
            deleted: false,
            tombstone: false,
            sourceDeviceID: "iphone-fail-closed",
            logicalPathToken: "Transcripts/transcript.md",
            availability: .local,
            transferState: nil,
            transferProgress: nil,
            conflictStatus: "conflict",
            autoDownloadAllowed: true
        )
        let inventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "iphone-fail-closed",
                deviceName: "iPhone",
                platform: .iPhone,
                generatedAt: now,
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [recording],
            artifacts: [],
            objects: [artifactObject]
        )
        func action(
            _ kind: LocalNetworkSyncDiffActionKind,
            _ entityKind: String,
            _ entityID: String
        ) -> LocalNetworkSyncDiffAction {
            LocalNetworkSyncDiffAction(
                id: "\(kind.rawValue):\(entityKind):\(entityID)",
                kind: kind,
                entityKind: entityKind,
                entityID: entityID,
                reason: "test"
            )
        }
        var source = LocalNetworkSyncDiffPlan()
        source.conflictActions = [action(.conflict, "artifact", artifactID)]
        source.uploadMetadataActions = [action(.uploadMetadata, "recording", recordingID)]
        source.downloadMetadataActions = [action(.downloadMetadata, "recording", "peer-recording")]
        source.uploadArtifactActions = [action(.uploadArtifact, "artifact", artifactID)]
        source.downloadArtifactActions = [action(.downloadArtifact, "artifact", "peer-artifact")]
        source.uploadRecordingAudioActions = [action(.uploadRecordingAudio, "recording", recordingID)]

        let isolated = LocalNetworkSyncEngine.conflictIsolatedExecutionPlan(
            source,
            localInventory: inventory,
            peerInventory: emptyLocalNetworkInventory(deviceID: "mac-fail-closed", platform: .Mac)
        )

        #expect(isolated.plan.uploadMetadataActions.isEmpty)
        #expect(isolated.plan.downloadMetadataActions.isEmpty)
        #expect(isolated.plan.uploadArtifactActions.isEmpty)
        #expect(isolated.plan.downloadArtifactActions.isEmpty)
        #expect(isolated.plan.uploadRecordingAudioActions.isEmpty)
        #expect(isolated.plan.conflictActions == source.conflictActions)
        #expect(isolated.blockedRecordingIDs.contains(recordingID))
        #expect(isolated.blockedRecordingIDs.contains("peer-recording"))
    }

    @Test func durableSyncSignalDebouncerQueuesSameRunOnlyOnceAcrossHeartbeatRedelivery() {
        var debouncer = LocalNetworkSyncDurableSignalDebouncer(interval: 5)
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var queuedCount = 0

        #expect(!debouncer.shouldDebounce(syncRunID: "durable-run", now: startedAt))
        debouncer.recordQueued(syncRunID: "durable-run", at: startedAt)
        queuedCount += 1
        #expect(!debouncer.shouldDebounce(
            syncRunID: "different-run",
            now: startedAt.addingTimeInterval(1)
        ))
        debouncer.recordQueued(syncRunID: "different-run", at: startedAt.addingTimeInterval(1))

        // Run IDs remain idempotent for their tracked lifecycle rather than a
        // five-second wall-clock window. An interleaved run must not erase it.
        for offset in [3.0, 6.0, 9.0] {
            let now = startedAt.addingTimeInterval(offset)
            if debouncer.shouldDebounce(syncRunID: "durable-run", now: now) {
                debouncer.recordQueued(syncRunID: "durable-run", at: now)
                continue
            }
            debouncer.recordQueued(syncRunID: "durable-run", at: now)
            queuedCount += 1
        }

        #expect(queuedCount == 1)
        #expect(debouncer.shouldDebounce(
            syncRunID: "durable-run",
            now: startedAt.addingTimeInterval(60)
        ))
    }

    @Test func durableSyncSignalQueuePreservesDistinctRunsInFIFOOrderBeforeDrain() throws {
        var queue = LocalNetworkSyncDurableSignalQueue(
            maximumPendingCount: 4,
            maximumCompletedRunIDCount: 8
        )
        let startedAt = Date(timeIntervalSince1970: 2_000)

        #expect(queue.enqueue(syncRunID: "durable-run-a", receivedAt: startedAt) == .queued)
        #expect(queue.enqueue(
            syncRunID: "durable-run-b",
            receivedAt: startedAt.addingTimeInterval(1)
        ) == .queued)
        #expect(queue.pendingCount == 2)

        let firstRequest = queue.dequeueNext()
        let secondRequest = queue.dequeueNext()
        let first = try #require(firstRequest)
        let second = try #require(secondRequest)
        #expect(first.syncRunID == "durable-run-a")
        #expect(second.syncRunID == "durable-run-b")
        queue.markFinished(first)
        queue.markFinished(second)

        #expect(queue.enqueue(
            syncRunID: "durable-run-a",
            receivedAt: startedAt.addingTimeInterval(60)
        ) == .duplicate)
        #expect(!queue.hasPendingRequests)
    }

    @Test func durableSyncSignalQueueRestoresPendingAndInFlightRunsFromDisk() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let stateURL = rootURL
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("durable-signal-rebuild-test.json", isDirectory: false)
        let startedAt = Date(timeIntervalSince1970: 3_000)
        var queue = LocalNetworkSyncDurableSignalQueue(
            maximumPendingCount: 4,
            maximumCompletedRunIDCount: 8
        )

        #expect(queue.enqueuePersistingCorrelatedRun(
            syncRunID: "recover-run-a",
            receivedAt: startedAt,
            fileURL: stateURL
        ) == .queued)
        #expect(queue.enqueuePersistingCorrelatedRun(
            syncRunID: "recover-run-b",
            receivedAt: startedAt.addingTimeInterval(1),
            fileURL: stateURL
        ) == .queued)
        let inFlightRequest = queue.dequeueNext()
        let inFlight = try #require(inFlightRequest)
        #expect(inFlight.syncRunID == "recover-run-a")
        try queue.writePersistentState(to: stateURL)

        var restored = try LocalNetworkSyncDurableSignalQueue.loadPersistentState(
            from: stateURL,
            maximumPendingCount: 4,
            maximumCompletedRunIDCount: 8
        )
        let recoveredFirstRequest = restored.dequeueNext()
        let recoveredSecondRequest = restored.dequeueNext()
        let recoveredFirst = try #require(recoveredFirstRequest)
        let recoveredSecond = try #require(recoveredSecondRequest)
        #expect(recoveredFirst.syncRunID == "recover-run-a")
        #expect(recoveredSecond.syncRunID == "recover-run-b")
        restored.markFinished(recoveredFirst)
        restored.markFinished(recoveredSecond)
        try restored.writePersistentState(to: stateURL)

        var completedReload = try LocalNetworkSyncDurableSignalQueue.loadPersistentState(
            from: stateURL,
            maximumPendingCount: 4,
            maximumCompletedRunIDCount: 8
        )
        #expect(completedReload.enqueuePersistingCorrelatedRun(
            syncRunID: "recover-run-a",
            receivedAt: startedAt.addingTimeInterval(60),
            fileURL: stateURL
        ) == .duplicate)
        #expect(!completedReload.hasPendingRequests)
    }

    @Test func durableSyncSignalQueueWriteFailureRollsBackAndCannotBeAcked() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let blockingParentURL = rootURL.appendingPathComponent("not-a-directory", isDirectory: false)
        try Data("block-directory-creation".utf8).write(to: blockingParentURL, options: .atomic)
        let unwritableStateURL = blockingParentURL
            .appendingPathComponent("durable-signal.json", isDirectory: false)
        var queue = LocalNetworkSyncDurableSignalQueue()

        let result = queue.enqueuePersistingCorrelatedRun(
            syncRunID: "persist-failure-run",
            receivedAt: Date(timeIntervalSince1970: 4_000),
            fileURL: unwritableStateURL
        )

        #expect(result == .persistenceFailed)
        #expect(!result.isReliablyQueued)
        #expect(!queue.hasPendingRequests)
        #expect(queue.pendingCount == 0)
    }

    @Test func localNetworkSyncStateCorruptionDoesNotCrashOrDeleteRecordings() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "state-corruption-audio", title: "保留录音", store: audioStore)
        let syncURL = rootURL
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("local-network-sync-state.json", isDirectory: false)
        try FileManager.default.createDirectory(at: syncURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: syncURL)

        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL)

        #expect(stateStore.state == .empty)
        #expect(stateStore.lastError != nil)
        #expect(try audioStore.loadMetadata(id: "state-corruption-audio").id == "state-corruption-audio")
    }

    @Test func localNetworkSyncStateControlPlaneSupersedesFreshRunsAndRejectsStaleUpdates() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let stateStore = LocalNetworkSyncStateStore(
            rootURL: rootURL,
            controlPlaneInactivityTimeout: 30
        )
        let startedAt = Date(timeIntervalSince1970: 2_200)

        #expect(stateStore.recordControlPlane(
            syncRunID: "old-run",
            state: .inventoryExchanging,
            at: startedAt
        ))
        #expect(!stateStore.recordControlPlane(
            syncRunID: "old-run",
            state: .syncStartSignalSent,
            at: startedAt.addingTimeInterval(1)
        ))
        #expect(stateStore.state.activeSyncRunID == "old-run")
        #expect(stateStore.state.controlPlaneState == .inventoryExchanging)

        #expect(stateStore.recordControlPlane(
            syncRunID: "new-start-run",
            state: .syncStartSignalSent,
            at: startedAt.addingTimeInterval(2)
        ))
        #expect(stateStore.state.activeSyncRunID == "new-start-run")
        #expect(stateStore.state.controlPlaneState == .syncStartSignalSent)

        #expect(stateStore.recordControlPlane(
            syncRunID: "new-inventory-run",
            state: .inventoryExchanging,
            at: startedAt.addingTimeInterval(3)
        ))
        #expect(stateStore.state.activeSyncRunID == "new-inventory-run")
        #expect(stateStore.state.controlPlaneState == .inventoryExchanging)

        #expect(!stateStore.recordControlPlane(
            syncRunID: "new-inventory-run",
            state: .syncStartAcked,
            at: startedAt.addingTimeInterval(4)
        ))
        #expect(!stateStore.recordControlPlane(
            syncRunID: "old-run",
            state: .planningTransfers,
            at: startedAt.addingTimeInterval(5)
        ))
        #expect(!stateStore.recordControlPlane(
            syncRunID: "old-run",
            state: .completed,
            at: startedAt.addingTimeInterval(6)
        ))
        #expect(!stateStore.recordControlPlane(
            syncRunID: "new-start-run",
            state: .failed,
            at: startedAt.addingTimeInterval(7)
        ))
        #expect(!stateStore.recordSuccess(
            peerDeviceID: "mac-control-plane",
            localInventoryHash: "stale-local-hash",
            peerInventoryHash: "stale-peer-hash",
            appliedPeerRevision: "stale-revision",
            pendingUploadCount: 0,
            pendingDownloadCount: 0,
            syncRunID: "old-run",
            at: startedAt.addingTimeInterval(8)
        ))
        #expect(!stateStore.recordFailure(
            code: "unrelated_failure",
            message: "unrelated failure",
            syncRunID: "never-active-run",
            at: startedAt.addingTimeInterval(9)
        ))

        #expect(stateStore.state.activeSyncRunID == "new-inventory-run")
        #expect(stateStore.state.controlPlaneState == .inventoryExchanging)
        #expect(stateStore.state.lastSuccessfulSyncAt == nil)
        #expect(stateStore.state.lastLocalInventoryHash == nil)
        #expect(stateStore.state.lastErrorCode == nil)
    }

    @Test func localNetworkProgressStoreSupersedesFreshRunsAndRejectsStaleUpdates() {
        let progressStore = LocalNetworkSyncProgressStore(controlPlaneInactivityTimeout: 30)
        let startedAt = Date(timeIntervalSince1970: 2_300)

        progressStore.record(
            deviceID: "mac-control-plane",
            syncRunID: "old-run",
            state: .inventoryExchanging,
            at: startedAt
        )
        progressStore.record(
            deviceID: "mac-control-plane",
            syncRunID: "old-run",
            state: .syncStartSignalSent,
            at: startedAt.addingTimeInterval(1)
        )
        #expect(progressStore.syncRunID == "old-run")
        #expect(progressStore.controlPlaneState == .inventoryExchanging)

        progressStore.record(
            deviceID: "mac-control-plane",
            syncRunID: "new-start-run",
            state: .syncStartSignalReceived,
            at: startedAt.addingTimeInterval(2)
        )
        #expect(progressStore.syncRunID == "new-start-run")
        #expect(progressStore.controlPlaneState == .syncStartSignalReceived)

        progressStore.record(
            deviceID: "mac-control-plane",
            syncRunID: "new-inventory-run",
            state: .inventoryExchanging,
            at: startedAt.addingTimeInterval(3)
        )
        #expect(progressStore.syncRunID == "new-inventory-run")
        #expect(progressStore.controlPlaneState == .inventoryExchanging)

        progressStore.record(
            deviceID: "mac-control-plane",
            syncRunID: "new-inventory-run",
            state: .syncStartAcked,
            at: startedAt.addingTimeInterval(4)
        )
        progressStore.record(
            deviceID: "mac-control-plane",
            syncRunID: "old-run",
            state: .planningTransfers,
            at: startedAt.addingTimeInterval(5)
        )
        progressStore.record(
            deviceID: "mac-control-plane",
            syncRunID: "old-run",
            state: .completed,
            at: startedAt.addingTimeInterval(6)
        )
        progressStore.record(
            deviceID: "mac-control-plane",
            syncRunID: "new-start-run",
            state: .failed,
            at: startedAt.addingTimeInterval(7)
        )

        #expect(progressStore.syncRunID == "new-inventory-run")
        #expect(progressStore.controlPlaneState == .inventoryExchanging)
        #expect(progressStore.updatedAt == startedAt.addingTimeInterval(3))
    }

    @Test func localNetworkSchedulerQueuesOneTickWhenReentrant() async {
        var tickCount = 0
        var triggers: [String] = []
        var queuedTriggers: [String] = []
        let scheduler = LocalNetworkSyncScheduler(
            interval: 0.01,
            onInFlightRequestQueued: { trigger in
                queuedTriggers.append(trigger)
            }
        ) { trigger, _ in
            tickCount += 1
            triggers.append(trigger)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        async let first: Bool = scheduler.requestTick(trigger: "first")
        try? await Task.sleep(nanoseconds: 5_000_000)
        let second = await scheduler.requestTick(trigger: "second")
        let firstResult = await first

        #expect(firstResult)
        #expect(!second)
        #expect(tickCount == 2)
        #expect(triggers == ["first", "second"])
        #expect(queuedTriggers == ["second"])
    }

    @Test func localNetworkSchedulerExposesPendingRequestForHeartbeatDedupe() async {
        var pendingObserved = false
        let scheduler = LocalNetworkSyncScheduler(interval: 0.01) { _, _ in
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        async let first: Bool = scheduler.requestTick(trigger: "first")
        try? await Task.sleep(nanoseconds: 5_000_000)
        async let second: Bool = scheduler.requestTick(trigger: "manual-sync-requested")
        try? await Task.sleep(nanoseconds: 5_000_000)
        pendingObserved = scheduler.hasPendingRequestAfterCurrentRun
        _ = await first
        _ = await second

        #expect(pendingObserved)
    }

    @Test func localNetworkSyncSchedulerDefaultsToSixtyAndAllowsTenThirtySixtySecondIntervals() {
        let defaultScheduler = LocalNetworkSyncScheduler { _, _ in }
        let ten = LocalNetworkSyncScheduler(interval: 10) { _, _ in }
        let thirty = LocalNetworkSyncScheduler(interval: 30) { _, _ in }
        let sixty = LocalNetworkSyncScheduler(interval: 60) { _, _ in }
        let fallback = LocalNetworkSyncScheduler(interval: 17) { _, _ in }

        #expect(defaultScheduler.configuredInterval == 60)
        #expect(ten.configuredInterval == 10)
        #expect(thirty.configuredInterval == 30)
        #expect(sixty.configuredInterval == 60)
        #expect(fallback.configuredInterval == 60)
    }

    @Test func syncEventReasonParsesNotificationUserInfo() {
        let notification = Notification(
            name: .localNetworkSyncEventTriggered,
            object: nil,
            userInfo: [
                LocalNetworkSyncEventTrigger.reasonUserInfoKey: SyncTriggerReason.recordingCreated.rawValue
            ]
        )

        #expect(LocalNetworkSyncEventTrigger.reason(from: notification) == .recordingCreated)
    }

    @Test func eventDrivenStatusOnlyTriggerCannotCreateUploadJob() {
        let statusOnly = RecordingAudioSyncTriggerSource(syncTrigger: "event-driven:syncStatusRefreshRequested")
        let newRecording = RecordingAudioSyncTriggerSource(syncTrigger: "event-driven:recordingCreated")
        let aggregatedDataChange = RecordingAudioSyncTriggerSource(
            syncTrigger: "event-driven:recordingCreated+syncStatusRefreshRequested"
        )

        #expect(statusOnly == .studyLibraryRefresh)
        #expect(!statusOnly.canCreateUploadJob)
        #expect(newRecording.canCreateUploadJob)
        #expect(aggregatedDataChange.canCreateUploadJob)
    }

    @Test func studyLibraryFolderMetadataChangePostsImmediateSyncEvent() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        var receivedReasons: [SyncTriggerReason] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .localNetworkSyncEventTriggered,
            object: nil,
            queue: nil
        ) { notification in
            if let reason = LocalNetworkSyncEventTrigger.reason(from: notification) {
                receivedReasons.append(reason)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = try studyStore.createFolder(named: "Linear Algebra", at: StudyBrowsePath())

        #expect(receivedReasons.contains(.studyLibraryMetadataChanged))
    }

    @Test func localNetworkSyncStartGateRequiresActivePairedAndOnline() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let online = statusStore.markConnected(deviceID: snapshot.deviceID, displayName: "Mac")
        let offline = statusStore.markOffline(deviceID: snapshot.deviceID, displayName: "Mac", error: "offline")

        #expect(LocalNetworkSyncStartGate.canRun(isActive: true, snapshot: snapshot, status: online))
        #expect(!LocalNetworkSyncStartGate.canRun(isActive: false, snapshot: snapshot, status: online))
        #expect(!LocalNetworkSyncStartGate.canRun(isActive: true, snapshot: makeUnpairedMacSnapshot(), status: online))
        #expect(!LocalNetworkSyncStartGate.canRun(isActive: true, snapshot: snapshot, status: offline))
        #expect(!LocalNetworkSyncStartGate.canRun(isActive: true, snapshot: snapshot, status: nil))
        #expect(!LocalNetworkSyncStartGate.canRun(
            isActive: true,
            snapshot: snapshot,
            status: online,
            userConnectionIntent: .disconnectedByUser
        ))
    }

    @Test func heartbeatMonitorStartsPeriodicForegroundPing() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let client = FakeLocalNetworkHeartbeatClient()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: client,
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(
                heartbeatInterval: 0.01,
                requestTimeout: 0.01,
                missedHeartbeatLimit: 2,
                staleAfter: 0.05,
                disconnectedAfter: 0.1
            )
        )

        monitor.startForegroundMonitoring()
        try? await Task.sleep(nanoseconds: 35_000_000)
        monitor.suspend()

        #expect(client.requests.count >= 1)
        #expect(statusStore.status(for: makePairedMacSnapshot().deviceID)?.monitoringMode == .suspended)
    }

    @Test func heartbeatMonitorSuppressedWhenUserDoesNotWantConnection() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let client = FakeLocalNetworkHeartbeatClient()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let provider = FakeSecureMacConnectionSnapshotProvider(
            snapshot: snapshot,
            userConnectionIntent: .disconnectedByUser
        )
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: provider,
            client: client,
            statusStore: statusStore,
            diagnosticsStore: diagnosticsStore,
            configuration: LocalNetworkHeartbeatConfiguration(
                heartbeatInterval: 0.01,
                requestTimeout: 0.01,
                missedHeartbeatLimit: 2,
                staleAfter: 0.05,
                disconnectedAfter: 0.1
            )
        )

        let didStart = monitor.startForegroundMonitoring()
        try? await Task.sleep(nanoseconds: 20_000_000)

        let status = try #require(statusStore.status(for: snapshot.deviceID))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))
        #expect(!didStart)
        #expect(!monitor.isMonitoring)
        #expect(client.requests.isEmpty)
        #expect(status.lastErrorCode == "user_disconnected")
        #expect(phases.contains("heartbeatSuppressedBecauseUserDoesNotWantConnection"))
    }

    @Test func foregroundResumeStartsHeartbeatEvenWhenDisconnectedAndSendsImmediateProbe() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let client = FakeLocalNetworkHeartbeatClient()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        _ = statusStore.markOffline(deviceID: snapshot.deviceID, displayName: "Rokurics Mac", error: "previous_disconnect")
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot),
            client: client,
            statusStore: statusStore,
            diagnosticsStore: diagnosticsStore,
            configuration: LocalNetworkHeartbeatConfiguration(
                heartbeatInterval: 0.05,
                requestTimeout: 0.02,
                missedHeartbeatLimit: 3,
                staleAfter: 0.05,
                disconnectedAfter: 0.1
            )
        )

        let didStart = monitor.startForegroundMonitoring()
        try? await Task.sleep(nanoseconds: 30_000_000)
        monitor.suspend()

        let status = try #require(statusStore.status(for: snapshot.deviceID, now: Date()))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))
        #expect(didStart)
        #expect(client.requests.first?.sequenceNumber == 1)
        #expect(status.presenceState == .online)
        #expect(status.missedHeartbeatCount == 0)
        #expect(phases.contains("heartbeatMonitorResumeRequested"))
        #expect(phases.contains("heartbeatImmediateProbeStarted"))
        #expect(phases.contains("heartbeatImmediateProbeSucceeded"))
    }

    @Test func heartbeatMonitorDoesNotStartWithoutPairedDevice() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let client = FakeLocalNetworkHeartbeatClient()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makeUnpairedMacSnapshot()),
            client: client,
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(
                heartbeatInterval: 0.01,
                requestTimeout: 0.01,
                missedHeartbeatLimit: 2,
                staleAfter: 0.05,
                disconnectedAfter: 0.1
            )
        )

        let didStart = monitor.startForegroundMonitoring()
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(!didStart)
        #expect(!monitor.isMonitoring)
        #expect(client.requests.isEmpty)
        #expect(statusStore.latestStatus == nil)
    }

    @Test func pairingSuccessAllowsHeartbeatToStartAfterPreviouslyUnpairedState() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = FakeSecureMacConnectionSnapshotProvider(snapshot: makeUnpairedMacSnapshot())
        let client = FakeLocalNetworkHeartbeatClient()
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: provider,
            client: client,
            statusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            configuration: LocalNetworkHeartbeatConfiguration(
                heartbeatInterval: 0.01,
                requestTimeout: 0.01,
                missedHeartbeatLimit: 2,
                staleAfter: 0.05,
                disconnectedAfter: 0.1
            )
        )

        #expect(!monitor.startForegroundMonitoring())
        provider.snapshot = makePairedMacSnapshot()
        #expect(monitor.startForegroundMonitoring())
        try? await Task.sleep(nanoseconds: 25_000_000)
        monitor.suspend()

        #expect(client.requests.count >= 1)
    }

    @MainActor
    @Test func pairingSuccessStoresCurrentMacIdentityInConnectionStore() throws {
        let suiteName = "RokuricsTests.Pairing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let keychain = KeychainStore(service: "com.Vita0818.Rokurics.tests.\(UUID().uuidString)")
        defer {
            try? keychain.delete(account: SecureMacConnectionSettings.deviceIDKey)
            try? keychain.delete(account: SecureMacConnectionSettings.sharedSecretKey)
            try? keychain.delete(account: SecureMacConnectionSettings.macFingerprintKey)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = SecureMacConnectionStore(userDefaults: defaults, keychainStore: keychain)
        let fingerprint = String(repeating: "a", count: 64)
        let result = SecurePairingResult(
            deviceID: "iphone-\(UUID().uuidString.lowercased())",
            sharedSecretBase64URL: Data("paired-secret-\(UUID().uuidString)".utf8).base64URLEncodedString(),
            pairedAt: "2026-05-26T10:00:00Z",
            macName: "Rokurics Mac",
            macModel: "MacBook"
        )

        try store.savePairing(
            result: result,
            host: " https://192.168.1.25:8787/pair ",
            portText: "8787",
            fingerprint: fingerprint.uppercased()
        )

        let snapshot = store.snapshot
        #expect(snapshot.isPaired)
        #expect(snapshot.macHost == "192.168.1.25")
        #expect(snapshot.macPort == 8787)
        #expect(snapshot.macFingerprint == fingerprint)
        #expect(snapshot.deviceID == result.deviceID)
        #expect(snapshot.sharedSecretBase64URL == result.sharedSecretBase64URL)

        let reloaded = SecureMacConnectionStore(userDefaults: defaults, keychainStore: keychain)
        #expect(reloaded.snapshot.macHost == "192.168.1.25")
        #expect(reloaded.snapshot.macPort == 8787)
        #expect(reloaded.snapshot.macFingerprint == fingerprint)
        #expect(reloaded.snapshot.sharedSecretBase64URL == result.sharedSecretBase64URL)
        #expect(reloaded.userConnectionIntent == .wantsConnected)
    }

    @Test func secureMacHostNormalizerPreservesIPv6AndStripsOnlyAuthorityPort() {
        #expect(SecureMacHostNormalizer.normalize("fe80::1234") == "fe80::1234")
        #expect(SecureMacHostNormalizer.normalize("[fe80::1234]") == "fe80::1234")
        #expect(SecureMacHostNormalizer.normalize("https://[fe80::1234]:8787/pair") == "fe80::1234")
        #expect(SecureMacHostNormalizer.normalize("rokurics-mac.local:8787") == "rokurics-mac.local")
    }

    @MainActor
    @Test func pairingInfoParserUsesDynamicPortCopiedByMac() throws {
        let suiteName = "RokuricsTests.DynamicPairingPort.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fingerprint = String(repeating: "A", count: 64)
        let pasted = """
        Rokurics Pairing
        Host: rokurics-mac.local
        Port: 8788
        Code: 123456
        Fingerprint: \(fingerprint)
        """

        let parsed = try #require(RokuricsPairingInfoParser.parse(pasted))

        #expect(parsed.host == "rokurics-mac.local")
        #expect(parsed.portText == "8788")
        #expect(parsed.pairingCode == "123456")
        #expect(parsed.fingerprint == fingerprint)

        let store = SecureMacConnectionStore(
            userDefaults: defaults,
            keychainStore: KeychainStore(service: "com.Vita0818.Rokurics.tests.\(UUID().uuidString)")
        )
        store.applyPairingInfo(parsed)

        #expect(store.macPortText == "8788")
        #expect(store.snapshot.macPort == 8788)
    }

    @MainActor
    @Test func manualDisconnectClearsPairedCredentialsAndRequiresFreshPairing() throws {
        let suiteName = "RokuricsTests.Intent.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let keychain = KeychainStore(service: "com.Vita0818.Rokurics.tests.\(UUID().uuidString)")
        defer {
            try? keychain.delete(account: SecureMacConnectionSettings.deviceIDKey)
            try? keychain.delete(account: SecureMacConnectionSettings.sharedSecretKey)
            try? keychain.delete(account: SecureMacConnectionSettings.macFingerprintKey)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = SecureMacConnectionStore(userDefaults: defaults, keychainStore: keychain)
        let result = SecurePairingResult(
            deviceID: "iphone-\(UUID().uuidString.lowercased())",
            sharedSecretBase64URL: Data("paired-secret-\(UUID().uuidString)".utf8).base64URLEncodedString(),
            pairedAt: "2026-05-26T10:00:00Z",
            macName: "Rokurics Mac",
            macModel: "MacBook"
        )
        try store.savePairing(
            result: result,
            host: "192.168.1.25",
            portText: "8787",
            fingerprint: String(repeating: "a", count: 64)
        )

        try store.clearPairing()
        let reloaded = SecureMacConnectionStore(userDefaults: defaults, keychainStore: keychain)

        #expect(!reloaded.snapshot.isPaired)
        #expect(reloaded.snapshot.sharedSecretBase64URL.isEmpty)
        #expect(reloaded.snapshot.deviceID.isEmpty)
        #expect(reloaded.snapshot.macHost.isEmpty)
        #expect(reloaded.snapshot.macPort == SecureMacConnectionSettings.defaultPort)
        #expect(reloaded.userConnectionIntent == .disconnectedByUser)
    }

    @Test func heartbeatPongMarksPeerOnlineAndRecordsLatency() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: FakeLocalNetworkHeartbeatClient(),
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )

        let didSend = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let status = try #require(statusStore.status(for: makePairedMacSnapshot().deviceID, now: Date(timeIntervalSince1970: 11)))

        #expect(didSend)
        #expect(status.presenceState == .online)
        #expect(status.state == .connected)
        #expect(status.missedHeartbeatCount == 0)
        #expect(status.latencyMilliseconds != nil)
    }

    @Test func heartbeatSyncRequestedHintInvokesQueuedSyncHandler() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let heartbeatClient = FakeLocalNetworkHeartbeatClient()
        heartbeatClient.syncRequested = true
        var syncRequestCount = 0
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: heartbeatClient,
            statusStore: statusStore,
            diagnosticsStore: diagnosticsStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )
        monitor.onSyncRequested = { _ in
            syncRequestCount += 1
            return true
        }

        let didSend = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(didSend)
        #expect(syncRequestCount == 1)
        #expect(phases.contains("syncRequestedHintReceived"))
    }

    @Test func heartbeatSyncStartSignalSendsAckAndQueuesSameRunID() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let heartbeatClient = FakeLocalNetworkHeartbeatClient()
        heartbeatClient.syncStartSignal = LocalNetworkSyncStartSignal(
            syncRunID: "signal-run-01",
            initiatorDeviceID: "mac-test",
            initiatorPlatform: .Mac,
            requestedAt: Date(timeIntervalSince1970: 9),
            reason: "manual"
        )
        var queuedSyncRunID: String?
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: heartbeatClient,
            statusStore: statusStore,
            diagnosticsStore: diagnosticsStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )
        monitor.onSyncRequested = { syncRunID in
            queuedSyncRunID = syncRunID
            return true
        }

        let didSend = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(didSend)
        #expect(queuedSyncRunID == "signal-run-01")
        #expect(heartbeatClient.ackRequests.map(\.syncRunID) == ["signal-run-01"])
        #expect(phases.contains("syncStartSignalReceived"))
        #expect(phases.contains("syncStartAckSent"))
    }

    @Test func heartbeatSyncStartSignalStillQueuesWhenAckDeliveryFails() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let heartbeatClient = FakeLocalNetworkHeartbeatClient()
        heartbeatClient.syncStartSignal = LocalNetworkSyncStartSignal(
            syncRunID: "signal-run-ack-loss",
            initiatorDeviceID: "mac-test",
            initiatorPlatform: .Mac,
            requestedAt: Date(timeIntervalSince1970: 9),
            reason: "manual"
        )
        heartbeatClient.ackError = SecureMacUploadError.serverRejected("simulated_ack_response_loss")
        var queuedSyncRunID: String?
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: heartbeatClient,
            statusStore: statusStore,
            diagnosticsStore: diagnosticsStore,
            configuration: LocalNetworkHeartbeatConfiguration(
                heartbeatInterval: 3,
                requestTimeout: 1,
                missedHeartbeatLimit: 3,
                staleAfter: 6,
                disconnectedAfter: 10
            )
        )
        monitor.onSyncRequested = {
            queuedSyncRunID = $0
            return true
        }

        let didSend = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let status = try #require(statusStore.status(for: makePairedMacSnapshot().deviceID, now: Date(timeIntervalSince1970: 10)))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(didSend)
        #expect(queuedSyncRunID == "signal-run-ack-loss")
        #expect(status.presenceState == .online)
        #expect(status.missedHeartbeatCount == 0)
        #expect(phases.contains("syncStartAckFailed"))
    }

    @Test func heartbeatSyncStartSignalDefersAckUntilRunIsReliablyQueued() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let heartbeatClient = FakeLocalNetworkHeartbeatClient()
        heartbeatClient.syncStartSignal = LocalNetworkSyncStartSignal(
            syncRunID: "signal-run-queue-full",
            initiatorDeviceID: "mac-test",
            initiatorPlatform: .Mac,
            requestedAt: Date(timeIntervalSince1970: 9),
            reason: "manual"
        )
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: heartbeatClient,
            statusStore: statusStore,
            diagnosticsStore: diagnosticsStore,
            configuration: LocalNetworkHeartbeatConfiguration(
                heartbeatInterval: 3,
                requestTimeout: 1,
                missedHeartbeatLimit: 3,
                staleAfter: 6,
                disconnectedAfter: 10
            )
        )
        monitor.onSyncRequested = { _ in false }

        let didSend = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let status = try #require(statusStore.status(
            for: makePairedMacSnapshot().deviceID,
            now: Date(timeIntervalSince1970: 10)
        ))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(didSend)
        #expect(heartbeatClient.ackRequests.isEmpty)
        #expect(status.presenceState == .online)
        #expect(phases.contains("syncStartAckDeferredQueueRejected"))
    }

    @Test func liveDeviceStatusHeartbeatSyncRequestedQueuesImmediateSync() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        var queuedSyncRunIDs: [String?] = []
        var heartbeatReturnedBeforeTickStarted = false
        var heartbeatReturned = false
        let signal = LocalNetworkSyncStartSignal(
            syncRunID: "device-status-sync-run",
            initiatorDeviceID: "mac-test",
            initiatorPlatform: .Mac,
            requestedAt: Date(timeIntervalSince1970: 9),
            reason: "manual"
        )
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot),
            studyLibraryStore: StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore),
            deviceStatusSender: { _, _ in
                DeviceStatusResponse(
                    ok: true,
                    status: nil,
                    syncState: nil,
                    syncRequested: true,
                    syncStartSignal: signal,
                    error: nil
                )
            },
            heartbeatRequestedSyncHandler: { syncRunID in
                heartbeatReturnedBeforeTickStarted = heartbeatReturned
                queuedSyncRunIDs.append(syncRunID)
                return true
            },
            statusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            syncStateStore: StudyLibrarySyncStateStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore,
            runtimeConfiguration: .gitBackedEnabled,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )

        await coordinator.performHeartbeat()
        heartbeatReturned = true
        for _ in 0..<20 where queuedSyncRunIDs.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(queuedSyncRunIDs == ["device-status-sync-run"])
        #expect(heartbeatReturnedBeforeTickStarted)
        #expect(phases.contains("heartbeatSyncRequestedHintReceived"))
        #expect(phases.contains("heartbeatSyncRequestedTickQueued"))
        #expect(phases.contains("heartbeatSyncRequestedTickStarted"))
        #expect(phases.contains("heartbeatSyncRequestedTickCompleted"))
    }

    @Test func liveDeviceStatusHeartbeatSyncRequestedFalseDoesNotQueueSync() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        var queuedCount = 0
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            studyLibraryStore: StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore),
            deviceStatusSender: { _, _ in
                DeviceStatusResponse(ok: true, status: nil, syncState: nil, syncRequested: false, error: nil)
            },
            heartbeatRequestedSyncHandler: { _ in
                queuedCount += 1
                return true
            },
            statusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            syncStateStore: StudyLibrarySyncStateStore(rootURL: rootURL),
            diagnosticsStore: ConnectionDiagnosticsStore(rootURL: rootURL),
            runtimeConfiguration: .gitBackedEnabled,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )

        await coordinator.performHeartbeat()
        try? await Task.sleep(nanoseconds: 30_000_000)

        #expect(queuedCount == 0)
    }

    @Test func liveDeviceStatusHeartbeatDuplicateSyncRequestedIsDebounced() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        var queuedCount = 0
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            studyLibraryStore: StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore),
            deviceStatusSender: { _, _ in
                DeviceStatusResponse(ok: true, status: nil, syncState: nil, syncRequested: true, error: nil)
            },
            heartbeatRequestedSyncHandler: { _ in
                queuedCount += 1
                return true
            },
            statusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            syncStateStore: StudyLibrarySyncStateStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore,
            runtimeConfiguration: .gitBackedEnabled,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )

        await coordinator.performHeartbeat()
        for _ in 0..<20 where queuedCount == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        await coordinator.performHeartbeat()
        try? await Task.sleep(nanoseconds: 30_000_000)
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(queuedCount == 1)
        #expect(phases.contains("heartbeatSyncRequestedTickDebounced"))
    }

    @Test func liveDeviceStatusDurableSignalsScheduleDistinctRunsInFIFOOrder() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let runIDs = ["device-status-run-a", "device-status-run-b"]
        var responseIndex = 0
        var scheduledRunIDs: [String] = []
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            studyLibraryStore: StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore),
            deviceStatusSender: { _, _ in
                let runID = runIDs[min(responseIndex, runIDs.count - 1)]
                responseIndex += 1
                return DeviceStatusResponse(
                    ok: true,
                    status: nil,
                    syncState: nil,
                    syncRequested: true,
                    syncStartSignal: LocalNetworkSyncStartSignal(
                        syncRunID: runID,
                        initiatorDeviceID: "mac-test",
                        initiatorPlatform: .Mac,
                        requestedAt: Date(),
                        reason: "manual"
                    ),
                    error: nil
                )
            },
            heartbeatRequestedSyncHandler: { syncRunID in
                if let syncRunID {
                    scheduledRunIDs.append(syncRunID)
                }
                try? await Task.sleep(nanoseconds: 40_000_000)
                return true
            },
            statusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            syncStateStore: StudyLibrarySyncStateStore(rootURL: rootURL),
            diagnosticsStore: ConnectionDiagnosticsStore(rootURL: rootURL),
            runtimeConfiguration: .gitBackedEnabled,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )

        await coordinator.performHeartbeat()
        await coordinator.performHeartbeat()
        for _ in 0..<40 where scheduledRunIDs.count < 2 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(scheduledRunIDs == runIDs)
    }

    @Test func heartbeatMonitorSendsRepeatedSequencesAndRecordsTraceDiagnostics() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let client = FakeLocalNetworkHeartbeatClient()
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot),
            client: client,
            statusStore: statusStore,
            diagnosticsStore: diagnosticsStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )

        for offset in [0, 3, 6] {
            _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10 + TimeInterval(offset)))
        }

        #expect(client.requests.map(\.sequenceNumber) == [1, 2, 3])
        let entries = diagnosticsStore.loadEntries()
        let startedSequences = entries
            .filter { $0.phase == "heartbeatRequestStarted" }
            .compactMap(\.heartbeatSequence)
        let responseSequences = entries
            .filter { $0.phase == "heartbeatResponseReceived" }
            .compactMap(\.responseSequence)
        let onlineSequences = entries
            .filter { $0.phase == "heartbeatMarkedOnline" }
            .compactMap(\.heartbeatSequence)
        let latestStatus = try #require(statusStore.status(for: snapshot.deviceID, now: Date()))

        #expect(startedSequences == [1, 2, 3])
        #expect(responseSequences == [1, 2, 3])
        #expect(onlineSequences == [1, 2, 3])
        #expect(latestStatus.presenceState == .online)
        #expect(latestStatus.missedHeartbeatCount == 0)
    }

    @Test func presenceSnapshotUnifiesStateAndRecentOnlineText() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL, staleAfter: 5, disconnectedAfter: 10)
        let snapshot = makePairedMacSnapshot()
        _ = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: Date(timeIntervalSince1970: 0),
            receivedAt: Date(timeIntervalSince1970: 0),
            latencyMilliseconds: 1
        )

        let interruptedStatus = try #require(statusStore.status(for: snapshot.deviceID, now: Date(timeIntervalSince1970: 8)))
        let presence = interruptedStatus.presenceSnapshot(now: Date(timeIntervalSince1970: 8))

        #expect(interruptedStatus.state != .connected)
        #expect(presence.state == .interrupted)
        #expect(presence.statusText == "连接中断 8 秒")
        #expect(presence.recentOnlineText == presence.statusText)
        #expect(!presence.isOnline)
    }

    @Test func heartbeatRecoveryResetsInterruptedSeconds() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL, staleAfter: 5, disconnectedAfter: 10)
        let snapshot = makePairedMacSnapshot()
        _ = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: Date(timeIntervalSince1970: 0),
            receivedAt: Date(timeIntervalSince1970: 0),
            latencyMilliseconds: 1
        )
        #expect(statusStore.status(for: snapshot.deviceID, now: Date(timeIntervalSince1970: 6))?.presenceSnapshot(now: Date(timeIntervalSince1970: 6)).state == .interrupted)

        _ = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: Date(timeIntervalSince1970: 7),
            receivedAt: Date(timeIntervalSince1970: 7),
            latencyMilliseconds: 1
        )
        let recovered = try #require(statusStore.status(for: snapshot.deviceID, now: Date(timeIntervalSince1970: 7)))
        let presence = recovered.presenceSnapshot(now: Date(timeIntervalSince1970: 7))

        #expect(presence.state == .online)
        #expect(presence.interruptedSeconds == 0)
        #expect(presence.recentOnlineText == "刚刚")
    }

    @Test func disabledSyncCoordinatorReadsPresenceStoreInsteadOfMarkingOffline() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let provider = FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: provider,
            studyLibraryStore: StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore),
            statusStore: statusStore,
            syncStateStore: syncStateStore,
            runtimeConfiguration: .default,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )

        let now = Date()
        _ = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: now,
            receivedAt: now,
            latencyMilliseconds: 4
        )
        coordinator.startForegroundMonitoring()
        coordinator.refreshPairingState()

        #expect(!coordinator.isAutomaticSyncMonitoringActive)
        #expect(coordinator.connectionStatus.presenceState == .online)
        #expect(coordinator.connectionStatus.state == .connected)
        #expect(coordinator.connectionStatus.lastSeenAt == now)

        _ = statusStore.recordHeartbeatFailure(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            errorCode: "heartbeat_timeout",
            errorMessage: "Timed out",
            now: now.addingTimeInterval(1)
        )
        _ = statusStore.recordHeartbeatFailure(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            errorCode: "heartbeat_timeout",
            errorMessage: "Timed out",
            now: now.addingTimeInterval(2)
        )
        _ = statusStore.recordHeartbeatFailure(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            errorCode: "heartbeat_timeout",
            errorMessage: "Timed out",
            now: now.addingTimeInterval(3)
        )
        coordinator.refreshPairingState()

        #expect(coordinator.connectionStatus.presenceState == .disconnected)
        #expect(coordinator.connectionStatus.state == .offline)
    }

    @Test func manualSyncInterruptedTriggersImmediateHeartbeatRetryBeforeLocalNetworkSync() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let provider = FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        let heartbeatClient = FakeLocalNetworkHeartbeatClient()
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        _ = statusStore.markOffline(deviceID: snapshot.deviceID, displayName: "Rokurics Mac", error: "previous_disconnect")
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: provider,
            studyLibraryStore: StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore),
            presenceHeartbeatClient: heartbeatClient,
            statusStore: statusStore,
            syncStateStore: syncStateStore,
            diagnosticsStore: diagnosticsStore,
            runtimeConfiguration: .default,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )

        let result = await coordinator.synchronizeNow()
        let status = try #require(statusStore.status(for: snapshot.deviceID, now: Date()))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(result == nil)
        #expect(heartbeatClient.requests.map(\.sequenceNumber) == [1])
        #expect(status.presenceSnapshot().isOnline)
        #expect(status.lastSyncStatus != StudyLibrarySyncRuntimeConfiguration.disabledStatusText)
        #expect(phases.contains("manualSyncTriggeredImmediateProbe"))
        #expect(phases.contains("syncSkippedReason"))
    }

    @Test func disabledManualSyncRunsLocalNetworkEngineInsteadOfDisabledStatus() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let provider = FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let recordingManager = RecordingManager(fileStore: audioStore)
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let uploadCoordinator = RecordingUploadCoordinator(jobStore: uploadJobStore)
        let syncClient = FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac))
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: provider,
            studyLibraryStore: recordingManager.studyLibraryStore,
            recordingManager: recordingManager,
            uploadCoordinator: uploadCoordinator,
            localNetworkSyncClient: syncClient,
            statusStore: statusStore,
            syncStateStore: syncStateStore,
            diagnosticsStore: diagnosticsStore,
            runtimeConfiguration: .default,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )
        let now = Date()
        _ = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: now,
            receivedAt: now,
            latencyMilliseconds: 4
        )

        let result = await coordinator.synchronizeNow()
        let status = try #require(statusStore.status(for: snapshot.deviceID, now: Date()))
        let entries = diagnosticsStore.loadEntries()
        let phases = Set(entries.map(\.phase))

        #expect(result == nil)
        #expect(syncClient.inventoryRequestCount == 1)
        #expect(syncClient.startRequests.count == 1)
        #expect(syncClient.inventorySyncRunIDs == [syncClient.startRequests.first?.syncRunID])
        #expect(status.lastSyncStatus != StudyLibrarySyncRuntimeConfiguration.disabledStatusText)
        #expect(phases.contains("manualSyncTapped"))
        #expect(phases.contains("manualSyncActionFired"))
        #expect(phases.contains("syncStartSignalSent"))
        #expect(phases.contains("syncStartAckReceived"))
        #expect(phases.contains("syncRunStarted"))
        #expect(phases.contains("localInventoryBuilt"))
        #expect(phases.contains("peerInventoryFetched"))
        #expect(entries.first { $0.phase == "syncRunStarted" }?.syncRunID != nil)
    }

    @Test func manualSyncDoesNotForceConnectionWhenUserIntentIsFalse() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let provider = FakeSecureMacConnectionSnapshotProvider(
            snapshot: snapshot,
            userConnectionIntent: .disconnectedByUser
        )
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let heartbeatClient = FakeLocalNetworkHeartbeatClient()
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let coordinator = StudyLibrarySyncCoordinator(
            connectionStore: provider,
            studyLibraryStore: StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore),
            presenceHeartbeatClient: heartbeatClient,
            statusStore: statusStore,
            syncStateStore: StudyLibrarySyncStateStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore,
            runtimeConfiguration: .default,
            heartbeatInterval: 0.01,
            syncInterval: 0.01
        )

        let result = await coordinator.synchronizeNow()
        let status = try #require(statusStore.status(for: snapshot.deviceID))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(result == nil)
        #expect(provider.userConnectionIntent == .disconnectedByUser)
        #expect(heartbeatClient.requests.isEmpty)
        #expect(status.lastErrorCode == "user_disconnected")
        #expect(phases.contains("syncSkippedBecauseUserDoesNotWantConnection"))
    }

    @Test func syncFailureStatusDoesNotMutatePresenceToDisconnectedOrHeartbeatMiss() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        _ = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: Date(timeIntervalSince1970: 1),
            receivedAt: Date(timeIntervalSince1970: 1),
            latencyMilliseconds: 1
        )

        let afterSyncFailure = statusStore.recordSyncResult(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            statusText: "同步失败",
            at: Date(timeIntervalSince1970: 2),
            error: "sync_timeout"
        )

        #expect(afterSyncFailure.presenceState == .online)
        #expect(afterSyncFailure.missedHeartbeatCount == 0)
        #expect(afterSyncFailure.lastErrorCode == nil)
        #expect(afterSyncFailure.lastSyncStatus == "同步失败")
    }

    @Test func heartbeatTimeoutsIncrementMissesAndDisconnectAfterThreshold() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL, missedHeartbeatLimit: 2)
        let client = FakeLocalNetworkHeartbeatClient(error: URLError(.timedOut))
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: client,
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 2, staleAfter: 6, disconnectedAfter: 10)
        )

        _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let first = try #require(statusStore.status(for: makePairedMacSnapshot().deviceID, now: Date(timeIntervalSince1970: 10)))
        _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 11))
        let second = try #require(statusStore.status(for: makePairedMacSnapshot().deviceID, now: Date(timeIntervalSince1970: 11)))

        #expect(first.presenceState == .interrupted)
        #expect(first.missedHeartbeatCount == 1)
        #expect(second.presenceState == .disconnected)
        #expect(second.missedHeartbeatCount == 2)
    }

    @Test func heartbeatMonitorPreventsConcurrentRequests() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let client = FakeLocalNetworkHeartbeatClient(delayNanoseconds: 50_000_000)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: client,
            statusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )

        async let first: Bool = monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        try? await Task.sleep(nanoseconds: 5_000_000)
        let second = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let firstResult = await first

        #expect(firstResult)
        #expect(!second)
        #expect(client.maxConcurrentRequests == 1)
    }

    @Test func signedRequestSuccessRefreshesPresenceState() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let snapshot = makePairedMacSnapshot()

        _ = statusStore.recordHeartbeatFailure(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            errorCode: "heartbeat_timeout",
            errorMessage: "Timed out"
        )
        let refreshed = statusStore.recordSignedRequestSucceeded(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            now: Date(timeIntervalSince1970: 20)
        )

        #expect(refreshed.presenceState == .online)
        #expect(refreshed.lastSignedRequestSucceededAt == Date(timeIntervalSince1970: 20))
        #expect(refreshed.missedHeartbeatCount == 0)
    }

    @Test func heartbeatFailureDoesNotDeleteUploadJobOrSyncState() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "heartbeat-preserve-upload-job", title: "保留上传任务", store: audioStore, uploadStatus: "failed")
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let snapshot = makePairedMacSnapshot()
        let connectionProvider = FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot)
        _ = try jobStore.ensureJob(for: metadata, settings: snapshot, now: Date(timeIntervalSince1970: 1))
        let syncStateStore = LocalNetworkSyncStateStore(rootURL: rootURL)
        syncStateStore.recordFailure(code: "previous_sync_failure", message: "keep me", at: Date(timeIntervalSince1970: 2))
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL, missedHeartbeatLimit: 1)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: connectionProvider,
            client: FakeLocalNetworkHeartbeatClient(error: URLError(.cannotConnectToHost)),
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 1, staleAfter: 6, disconnectedAfter: 10)
        )

        _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 3))

        #expect(try jobStore.loadJob(recordingID: metadata.id) != nil)
        #expect(syncStateStore.state.lastErrorCode == "previous_sync_failure")
        #expect(connectionProvider.snapshot.isPaired)
    }

    @Test func heartbeatSecurityFailureMapsToSecurityError() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            client: FakeLocalNetworkHeartbeatClient(error: SecureMacUploadError.fingerprintMismatch),
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )

        _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let status = try #require(statusStore.status(for: makePairedMacSnapshot().deviceID, now: Date(timeIntervalSince1970: 10)))

        #expect(status.presenceState == .securityError)
        #expect(status.lastErrorCode == "certificate_pinning_failed")
    }

    @Test func uploadTestGateUsesPresenceState() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let onlineStatus = statusStore.recordHeartbeatSuccess(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            sentAt: Date(timeIntervalSince1970: 1),
            receivedAt: Date(timeIntervalSince1970: 2),
            latencyMilliseconds: 3
        )

        #expect(MacUploadTestPresenceGate.blockedReason(snapshot: snapshot, status: onlineStatus, now: Date(timeIntervalSince1970: 2)) == nil)

        let disconnected = statusStore.markOffline(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            error: "heartbeat_disconnected",
            now: Date(timeIntervalSince1970: 12)
        )

        #expect(MacUploadTestPresenceGate.blockedReason(snapshot: snapshot, status: disconnected) == "heartbeat_disconnected")
        #expect(MacUploadTestPresenceGate.blockedReason(snapshot: makeUnpairedMacSnapshot(), status: disconnected) == "not_paired")
    }

    @Test func studyItemTransferProgressModelReplacesActionAreaUntilComplete() {
        let item = StudyItemMetadata(
            recordingID: "transfer-recording",
            title: "传输中录音",
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 5
        )
        let transferring = LocalNetworkTransferProgress(
            objectID: "transfer-recording",
            objectKind: LocalNetworkSyncObjectKind.transcriptMarkdown.rawValue,
            state: .transferring,
            progressFraction: 0.4,
            receivedBytes: 4,
            totalBytes: 10,
            sourceDeviceID: "mac-01",
            statusText: "40%"
        )

        let withTransfer = item.withLocalNetworkTransferProgress(transferring)
        let failed = item.withLocalNetworkTransferProgress(LocalNetworkTransferProgress(
            objectID: "transfer-recording",
            objectKind: LocalNetworkSyncObjectKind.transcriptMarkdown.rawValue,
            state: .failed,
            progressFraction: nil,
            receivedBytes: 4,
            totalBytes: 10,
            sourceDeviceID: "mac-01",
            statusText: "传输失败"
        ))
        let restored = withTransfer.withLocalNetworkTransferProgress(LocalNetworkTransferProgress(
            objectID: "transfer-recording",
            objectKind: LocalNetworkSyncObjectKind.transcriptMarkdown.rawValue,
            state: .complete,
            progressFraction: 1,
            receivedBytes: 10,
            totalBytes: 10,
            sourceDeviceID: "mac-01",
            statusText: "已完成"
        ))

        #expect(withTransfer.localNetworkTransferProgress?.state == .transferring)
        #expect(withTransfer.localNetworkTransferProgress?.progressFraction == 0.4)
        #expect(withTransfer.localNetworkTransferProgress?.isVisibleInActionArea == true)
        #expect(failed.localNetworkTransferProgress?.state == .failed)
        #expect(failed.localNetworkTransferProgress?.isVisibleInActionArea == true)
        #expect(restored.localNetworkTransferProgress == nil)
    }

    @Test func uploadedNoOpDisplayStateDoesNotAnimateTransfer() {
        let metadata = makeMetadata(
            id: "display-noop",
            title: "已同步",
            relativeAudioPath: "Recordings/display-noop.m4a",
            relativeMetadataPath: "Metadata/display-noop.json",
            uploadStatus: RecordingUploadStatus.uploaded.rawValue
        )

        let displayState = RecordingUploadActionAreaPresentation.displayState(
            metadata: metadata,
            status: .uploaded
        )
        let presentation = RecordingUploadActionAreaPresentation.resolve(
            metadata: metadata,
            status: .uploaded,
            isMacPaired: true
        )

        #expect(displayState == .hidden)
        #expect(displayState.shouldAnimateTransfer == false)
        #expect(presentation == nil)
    }

    @Test func heartbeatDiagnosticsContainPhasesWithoutSecrets() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot),
            client: FakeLocalNetworkHeartbeatClient(),
            statusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )

        _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        monitor.recordSignedRequestSucceeded(settings: snapshot, now: Date(timeIntervalSince1970: 11))
        await diagnosticsStore.flushForTests()

        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))
        #expect(phases.contains("heartbeatRequestStarted"))
        #expect(phases.contains("heartbeatResponseReceived"))
        #expect(phases.contains("heartbeatMarkedOnline"))
        #expect(phases.contains("signedRequestRefreshedLastSeen"))

        let diagnosticsText = try String(contentsOf: diagnosticsStore.logURL, encoding: .utf8)
        #expect(!diagnosticsText.lowercased().contains("sharedsecret"))
        #expect(!diagnosticsText.lowercased().contains("hmac"))
        #expect(!diagnosticsText.lowercased().contains("privatekey"))
        #expect(!diagnosticsText.contains(snapshot.sharedSecretBase64URL))
    }

    @Test func staleHostOrPortHeartbeatFailureIsClassifiedWithoutClearingCredentials() async throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = SecureMacConnectionSnapshot(
            macHost: "192.0.2.55",
            macPort: 65535,
            macFingerprint: String(repeating: "a", count: 64),
            macName: "Rokurics Mac",
            macModel: "Mac",
            deviceID: "iphone-stale-host",
            sharedSecretBase64URL: Data("stale-host-secret".utf8).base64EncodedString(),
            pairedAt: "2026-05-26T10:00:00Z"
        )
        let provider = FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let monitor = LocalNetworkHeartbeatMonitor(
            connectionStore: provider,
            client: FakeLocalNetworkHeartbeatClient(error: SecureMacUploadError.httpsUnavailable("连接被拒绝或 Mac 未监听该地址。")),
            statusStore: statusStore,
            configuration: LocalNetworkHeartbeatConfiguration(heartbeatInterval: 3, requestTimeout: 1, missedHeartbeatLimit: 3, staleAfter: 6, disconnectedAfter: 10)
        )

        _ = await monitor.performHeartbeat(now: Date(timeIntervalSince1970: 10))
        let status = try #require(statusStore.status(for: snapshot.deviceID, now: Date(timeIntervalSince1970: 10)))

        #expect(status.presenceState == .interrupted)
        #expect(status.lastErrorCode == "heartbeat_unreachable")
        #expect(provider.snapshot.isPaired)
        #expect(provider.snapshot.sharedSecretBase64URL == snapshot.sharedSecretBase64URL)
    }

    @Test func heartbeatConfigurationSupportsForegroundSecondScaleIntervals() {
        let configuration = LocalNetworkHeartbeatConfiguration(
            heartbeatInterval: 1,
            requestTimeout: 1.5,
            missedHeartbeatLimit: 3,
            staleAfter: 6,
            disconnectedAfter: 10
        )

        #expect((1...5).contains(configuration.heartbeatInterval))
        #expect(configuration.requestTimeout <= 3)
        #expect(configuration.missedHeartbeatLimit == 3)
    }

    @Test func heartbeatPayloadDoesNotCarrySyncOrFileDataOrSecrets() throws {
        let request = ConnectionHeartbeatRequest(
            deviceID: "iphone-01",
            deviceName: "Vita iPhone",
            platform: .iPhone,
            appInstanceID: "instance-01",
            sequenceNumber: 7,
            sentAt: Date(timeIntervalSince1970: 10),
            lastKnownPeerStatusRevision: 3
        )

        let json = String(data: try Self.studyEncoder.encode(request), encoding: .utf8) ?? ""

        #expect(!json.lowercased().contains("sharedsecret"))
        #expect(!json.lowercased().contains("hmac"))
        #expect(!json.lowercased().contains("manifest"))
        #expect(!json.lowercased().contains("transcript"))
        #expect(!json.lowercased().contains("audio"))
        #expect(!json.lowercased().contains("note"))
    }

    @Test func disconnectedOrSecurityStatusDoesNotClearPairedCredentials() throws {
        let (_, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = makePairedMacSnapshot()
        let provider = FakeSecureMacConnectionSnapshotProvider(snapshot: snapshot)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL, missedHeartbeatLimit: 1)

        _ = statusStore.recordHeartbeatFailure(
            deviceID: snapshot.deviceID,
            displayName: "Rokurics Mac",
            errorCode: "certificate_pinning_failed",
            errorMessage: "Certificate pinning failed",
            isSecurityFailure: true
        )

        #expect(statusStore.status(for: snapshot.deviceID)?.presenceState == .securityError)
        #expect(provider.snapshot.isPaired)
        #expect(provider.snapshot.sharedSecretBase64URL == snapshot.sharedSecretBase64URL)
    }

    @Test func localNetworkSyncEngineDoesNotRunSecureSyncWithoutPairedDevice() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let fakeClient = FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac))
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makeUnpairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL)
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 1))

        #expect(plan == nil)
        #expect(fakeClient.inventoryRequestCount == 0)
    }

    @Test func localNetworkSyncEngineRespectsNextAllowedSyncAt() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL)
        var blockedState = LocalNetworkSyncState.empty
        blockedState.nextAllowedSyncAt = Date(timeIntervalSince1970: 10_000)
        stateStore.replace(blockedState)
        let fakeClient = FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac))
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: stateStore
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 1))

        #expect(plan == nil)
        #expect(fakeClient.inventoryRequestCount == 0)
    }

    @Test func localNetworkSyncEngineManualTriggerBypassesNextAllowedSyncAt() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL)
        var blockedState = LocalNetworkSyncState.empty
        blockedState.nextAllowedSyncAt = Date(timeIntervalSince1970: 10_000)
        stateStore.replace(blockedState)
        let fakeClient = FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac))
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: stateStore
        )

        let plan = await engine.performTick(trigger: "manual", now: Date(timeIntervalSince1970: 1))

        #expect(plan != nil)
        #expect(fakeClient.inventoryRequestCount == 1)
    }

    @Test func localNetworkSyncEngineSkipsWhenPresenceIsNotOnline() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        _ = statusStore.markOffline(deviceID: makePairedMacSnapshot().deviceID, displayName: "Mac", error: "offline")
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL)
        let fakeClient = FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac))
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: stateStore,
            connectionStatusStore: statusStore
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 1))

        #expect(plan == nil)
        #expect(fakeClient.inventoryRequestCount == 0)
        #expect(stateStore.state.lastErrorCode == "presence_not_online")
    }

    @Test func localNetworkSyncDiagnosticsContainPhasesWithoutSecrets() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac)),
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore
        )

        _ = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 10))
        await diagnosticsStore.flushForTests()
        let rawLog = (try? String(contentsOf: diagnosticsStore.logURL, encoding: .utf8)) ?? ""
        let entries = diagnosticsStore.loadEntries()

        #expect(rawLog.contains("syncRunStarted"))
        #expect(rawLog.contains("syncRunIDCreated"))
        #expect(rawLog.contains("syncTickStarted"))
        #expect(rawLog.contains("localInventoryBuilt"))
        #expect(rawLog.contains("peerInventoryFetched"))
        #expect(rawLog.contains("diffPlanCreated"))
        #expect(rawLog.contains("bidirectionalDiffPlanCreated"))
        #expect(rawLog.contains("noTransferNeeded"))
        #expect(rawLog.contains("syncTickCompleted"))
        #expect(entries.first { $0.phase == "syncRunStarted" }?.syncRunID != nil)
        #expect(!rawLog.lowercased().contains("sharedsecret"))
        #expect(!rawLog.lowercased().contains("hmac"))
        #expect(!rawLog.contains("c3luYy1zZWNyZXQ"))
    }

    @Test func localNetworkSyncEngineRecordsConflictWinnerLoserHashAndTime() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let logicalPath = "transcripts/conflict-recording/transcript.md"
        let localData = Data("local conflict".utf8)
        let localURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: audioStore.baseDirectory(), logicalPathToken: logicalPath)
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try localData.write(to: localURL)
        let item = StudyItemMetadata(
            recordingID: "conflict-recording",
            title: "冲突转写",
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 5,
            transcriptMarkdownRelativePath: logicalPath,
            updatedAt: Date(timeIntervalSince1970: 2_010),
            transcriptionStatus: "transcribed",
            noteStatus: "notStarted"
        )
        _ = try await studyStore.applySyncManifest(
            StudyLibrarySyncManifest.make(deviceID: makePairedMacSnapshot().deviceID, generatedAt: Date(), items: [item], folders: []),
            localDeviceID: makePairedMacSnapshot().deviceID
        )
        let artifactID = LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "conflict-recording", logicalPathToken: logicalPath)
        let peerInventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: Date(),
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            artifacts: [
                LocalNetworkSyncArtifactEntry(
                    artifactID: artifactID,
                    kind: .transcriptMarkdown,
                    ownerID: "conflict-recording",
                    checksum: SecureUploadUtilities.sha256Hex(Data("peer conflict".utf8)),
                    size: Int64(Data("peer conflict".utf8).count),
                    updatedAt: Date(timeIntervalSince1970: 2_020),
                    availability: .local,
                    logicalPathToken: logicalPath
                )
            ]
        )
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL)
        var state = LocalNetworkSyncState.empty
        state.lastSuccessfulSyncAt = Date(timeIntervalSince1970: 100)
        stateStore.replace(state)
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: FakeLocalNetworkSyncClient(peerInventory: peerInventory),
            stateStore: stateStore,
            diagnosticsStore: diagnosticsStore
        )

        let plan = await engine.performTick(trigger: "manual", now: Date(timeIntervalSince1970: 3_000))
        let conflict = try #require(diagnosticsStore.loadEntries().first {
            $0.phase == "conflictDetected"
                && $0.result?.contains("winner=") == true
        })

        #expect(plan == nil)
        #expect(stateStore.state.lastErrorMessage != nil)
        #expect(conflict.result?.contains("winner=") == true)
        #expect(conflict.result?.contains("loser=") == true)
        #expect(conflict.result?.contains("localHash=") == true)
        #expect(conflict.result?.contains("peerHash=") == true)
        #expect(conflict.result?.contains("localUpdatedAt=") == true)
        #expect(conflict.result?.contains("peerUpdatedAt=") == true)
    }

    @Test func localNetworkSyncEngineDownloadsTranscriptArtifact() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let logicalPath = "transcripts/recording-remote/transcript.md"
        let receivePath = "incoming/recording-remote/receive.json"
        let artifactID = LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "recording-remote", logicalPathToken: logicalPath)
        let receiveArtifactID = LocalNetworkSyncArtifactID.make(kind: .receiveJSON, ownerID: "recording-remote", logicalPathToken: receivePath)
        let item = StudyItemMetadata(
            recordingID: "recording-remote",
            title: "远端转写",
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 9,
            receiveRelativePath: receivePath,
            transcriptMarkdownRelativePath: logicalPath,
            updatedAt: Date(timeIntervalSince1970: 2_010),
            transcriptionStatus: "transcribed",
            noteStatus: "notStarted"
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: "mac-01",
            generatedAt: Date(timeIntervalSince1970: 2_020),
            items: [item],
            folders: []
        )
        let peerInventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: Date(timeIntervalSince1970: 2_020),
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            studyItems: [
                LocalNetworkSyncStudyItemEntry(
                    itemID: item.itemID,
                    kind: item.kind,
                    title: item.title,
                    folderIDs: item.folderIDs,
                    recordingID: item.recordingID,
                    updatedAt: item.updatedAt,
                    revisionHash: item.localNetworkStudyItemBusinessSignatureV2,
                    deleted: false
                )
            ],
            artifacts: [
                LocalNetworkSyncArtifactEntry(
                    artifactID: artifactID,
                    kind: .transcriptMarkdown,
                    ownerID: "recording-remote",
                    checksum: SecureUploadUtilities.sha256Hex(Data("hello transcript".utf8)),
                    size: 16,
                    updatedAt: Date(timeIntervalSince1970: 2_020),
                    availability: .local,
                    logicalPathToken: logicalPath
                ),
                LocalNetworkSyncArtifactEntry(
                    artifactID: receiveArtifactID,
                    kind: .receiveJSON,
                    ownerID: "recording-remote",
                    checksum: SecureUploadUtilities.sha256Hex(Data(#"{"status":"completed"}"#.utf8)),
                    size: Int64(Data(#"{"status":"completed"}"#.utf8).count),
                    updatedAt: Date(timeIntervalSince1970: 2_020),
                    availability: .local,
                    logicalPathToken: receivePath
                )
            ],
            studyManifest: manifest
        )
        let fakeClient = FakeLocalNetworkSyncClient(
            peerInventory: peerInventory,
            artifactResponses: [
                artifactID: LocalNetworkSyncArtifactResponse(
                    ok: true,
                    artifactID: artifactID,
                    kind: .transcriptMarkdown,
                    checksum: SecureUploadUtilities.sha256Hex(Data("hello transcript".utf8)),
                    size: 16,
                    logicalPathToken: logicalPath,
                    dataBase64: Data("hello transcript".utf8).base64EncodedString(),
                    error: nil
                ),
                receiveArtifactID: LocalNetworkSyncArtifactResponse(
                    ok: true,
                    artifactID: receiveArtifactID,
                    kind: .receiveJSON,
                    checksum: SecureUploadUtilities.sha256Hex(Data(#"{"status":"completed"}"#.utf8)),
                    size: Int64(Data(#"{"status":"completed"}"#.utf8).count),
                    logicalPathToken: receivePath,
                    dataBase64: Data(#"{"status":"completed"}"#.utf8).base64EncodedString(),
                    error: nil
                )
            ]
        )
        var observedTransferStates: [LocalNetworkTransferState] = []
        var observedTransferItemExists = false
        var observedTransferCustomProperties: [[String: String]] = []
        fakeClient.onArtifactRequest = { _ in
            if let transferItem = studyStore.item(recordingID: "recording-remote") {
                observedTransferItemExists = true
                observedTransferCustomProperties.append(transferItem.customProperties)
            }
            if let progress = studyStore.item(recordingID: "recording-remote")?.localNetworkTransferProgress {
                observedTransferStates.append(progress.state)
            }
        }
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 3_000))
        let downloadedURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: audioStore.baseDirectory(), logicalPathToken: logicalPath)
        let downloadedReceiveURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: audioStore.baseDirectory(), logicalPathToken: receivePath)

        #expect(plan?.downloadArtifactActions.map(\.entityID).contains(artifactID) == true)
        #expect(plan?.downloadArtifactActions.map(\.entityID).contains(receiveArtifactID) == true)
        #expect(String(data: try Data(contentsOf: downloadedURL), encoding: .utf8) == "hello transcript")
        #expect(String(data: try Data(contentsOf: downloadedReceiveURL), encoding: .utf8) == #"{"status":"completed"}"#)
        #expect(fakeClient.artifactRequestIDs == [receiveArtifactID, artifactID] || fakeClient.artifactRequestIDs == [artifactID, receiveArtifactID])
        #expect(observedTransferStates.contains(.transferring), "itemExists=\(observedTransferItemExists), customProperties=\(observedTransferCustomProperties)")
        #expect(studyStore.item(recordingID: "recording-remote")?.localNetworkTransferProgress == nil)
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))
        #expect(phases.contains("transferJobStarted"))
        #expect(phases.contains("fileTransferStarted"))
        #expect(phases.contains("fileTransferProgressUpdated"))
        #expect(phases.contains("checksumVerified"))
        #expect(phases.contains("atomicReplaceCompleted"))
        #expect(phases.contains("peerFileApplied"))
        #expect(phases.contains("fileTransferCompleted"))
    }

    @Test func localNetworkSyncEngineDoesNotRecordSuccessForPeerPartialMetadataApply() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        try studyStore.save(StudyItemMetadata(
            kind: .standaloneNote,
            title: "只同步 metadata",
            createdAt: Date(timeIntervalSince1970: 2_000),
            updatedAt: Date(timeIntervalSince1970: 2_010)
        ))
        var partialResult = StudyLibrarySyncApplyResult()
        partialResult.failedChanges = 1
        let fakeClient = FakeLocalNetworkSyncClient(
            peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac),
            applyMetadataResponse: StudyLibrarySyncManifestResponse(
                ok: true,
                manifest: nil,
                syncState: nil,
                deviceStatus: nil,
                applyResult: partialResult,
                baseCommitID: nil,
                newCommitID: nil,
                remoteChanges: nil,
                rejectedChanges: nil,
                error: "sync_apply_metadata_partial_failure"
            )
        )
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL)
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: RecordingUploadJobStore(audioFileStore: audioStore),
            client: fakeClient,
            stateStore: stateStore
        )

        let plan = await engine.performTick(trigger: "manual", now: Date(timeIntervalSince1970: 3_000))

        #expect(plan == nil)
        #expect(fakeClient.applyMetadataCount == 1)
        #expect(stateStore.state.lastSuccessfulSyncAt == nil)
        #expect(stateStore.state.lastErrorMessage != nil)
    }

    @Test func localNetworkSyncEngineUploadsSmallArtifactWhenPeerMissing() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let logicalPath = "transcripts/local-recording/transcript.md"
        let localData = Data("local transcript".utf8)
        let localURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: audioStore.baseDirectory(), logicalPathToken: logicalPath)
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try localData.write(to: localURL)

        let item = StudyItemMetadata(
            recordingID: "local-recording",
            title: "本地转写",
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 5,
            transcriptMarkdownRelativePath: logicalPath,
            updatedAt: Date(timeIntervalSince1970: 2_010),
            transcriptionStatus: "transcribed",
            noteStatus: "notStarted"
        )
        _ = try await studyStore.applySyncManifest(
            StudyLibrarySyncManifest.make(
                deviceID: makePairedMacSnapshot().deviceID,
                generatedAt: Date(timeIntervalSince1970: 2_020),
                items: [item],
                folders: []
            ),
            localDeviceID: makePairedMacSnapshot().deviceID
        )

        let fakeClient = FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac))
        var observedUploadProgressStates: [LocalNetworkTransferState] = []
        fakeClient.onArtifactPut = { _ in
            if let progress = studyStore.item(recordingID: "local-recording")?.localNetworkTransferProgress {
                observedUploadProgressStates.append(progress.state)
            }
        }
        let transferJobStore = LocalNetworkSyncTransferJobStore(rootURL: rootURL)
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL),
            transferJobStore: transferJobStore,
            diagnosticsStore: diagnosticsStore
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 3_000))
        let artifactID = LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "local-recording", logicalPathToken: logicalPath)
        let putRequest = try #require(fakeClient.artifactPutRequests.first)
        let transferJob = try #require(try transferJobStore.loadJobs().first { $0.artifactID == artifactID })

        #expect(plan?.uploadArtifactActions.contains { $0.entityID == artifactID } == true)
        #expect(putRequest.artifactID == artifactID)
        #expect(putRequest.kind == .transcriptMarkdown)
        #expect(putRequest.logicalPathToken == logicalPath)
        #expect(putRequest.checksum == SecureUploadUtilities.sha256Hex(localData))
        #expect(Data(base64Encoded: putRequest.dataBase64) == localData)
        #expect(observedUploadProgressStates.contains(.transferring))
        #expect(studyStore.item(recordingID: "local-recording")?.localNetworkTransferProgress == nil)
        #expect(transferJob.direction == .upload)
        #expect(transferJob.state == .complete)
        #expect(transferJob.transferredBytes == Int64(localData.count))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))
        #expect(phases.contains("transferJobStarted"))
        #expect(phases.contains("fileTransferStarted"))
        #expect(phases.contains("fileTransferProgressUpdated"))
        #expect(phases.contains("checksumVerified"))
        #expect(phases.contains("peerFileApplied"))
        #expect(phases.contains("fileTransferCompleted"))
    }

    @Test func localNetworkSyncEngineUploadsLargeArtifactInChunksWhenPeerMissing() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let logicalPath = "transcripts/large-local-recording/transcript.md"
        let localData = Data(repeating: 0x41, count: 4 * 1024 * 1024 + 17)
        let localURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: audioStore.baseDirectory(), logicalPathToken: logicalPath)
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try localData.write(to: localURL)
        let item = StudyItemMetadata(
            recordingID: "large-local-recording",
            title: "大转写",
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 5,
            transcriptMarkdownRelativePath: logicalPath,
            updatedAt: Date(timeIntervalSince1970: 2_010),
            transcriptionStatus: "transcribed",
            noteStatus: "notStarted"
        )
        _ = try await studyStore.applySyncManifest(
            StudyLibrarySyncManifest.make(
                deviceID: makePairedMacSnapshot().deviceID,
                generatedAt: Date(timeIntervalSince1970: 2_020),
                items: [item],
                folders: []
            ),
            localDeviceID: makePairedMacSnapshot().deviceID
        )
        let fakeClient = FakeLocalNetworkSyncClient(peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac))
        let transferJobStore = LocalNetworkSyncTransferJobStore(rootURL: rootURL)
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL),
            transferJobStore: transferJobStore,
            diagnosticsStore: diagnosticsStore
        )

        let plan = await engine.performTick(trigger: "manual", now: Date(timeIntervalSince1970: 3_000))
        let artifactID = LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "large-local-recording", logicalPathToken: logicalPath)
        let transferJob = try #require(try transferJobStore.loadJobs().first { $0.artifactID == artifactID })
        let requests = fakeClient.artifactPutRequests

        #expect(plan?.uploadArtifactActions.contains { $0.entityID == artifactID } == true)
        #expect(requests.count > 1)
        #expect(requests.first?.offset == 0)
        #expect(requests.allSatisfy { $0.totalSize == Int64(localData.count) })
        #expect(requests.last?.isFinalChunk == true)
        #expect(requests.allSatisfy { Data(base64Encoded: $0.dataBase64)?.count == $0.chunkSize })
        #expect(transferJob.state == .complete)
        #expect(transferJob.transferredBytes == Int64(localData.count))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))
        #expect(phases.contains("fileTransferProgressUpdated"))
        #expect(phases.contains("fileTransferCompleted"))
    }

    @Test func localNetworkSyncEngineResumesLargeArtifactUploadFromPeerStatusOffset() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let logicalPath = "transcripts/resume-local-recording/transcript.md"
        let localData = Data(repeating: 0x52, count: 4 * 1024 * 1024 + 11)
        let localURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: audioStore.baseDirectory(), logicalPathToken: logicalPath)
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try localData.write(to: localURL)
        let item = StudyItemMetadata(
            recordingID: "resume-local-recording",
            title: "续传转写",
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 5,
            transcriptMarkdownRelativePath: logicalPath,
            updatedAt: Date(timeIntervalSince1970: 2_010),
            transcriptionStatus: "transcribed",
            noteStatus: "notStarted"
        )
        _ = try await studyStore.applySyncManifest(
            StudyLibrarySyncManifest.make(deviceID: makePairedMacSnapshot().deviceID, generatedAt: Date(timeIntervalSince1970: 2_020), items: [item], folders: []),
            localDeviceID: makePairedMacSnapshot().deviceID
        )
        let artifactID = LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "resume-local-recording", logicalPathToken: logicalPath)
        let resumeOffset = Int64(2 * 1024 * 1024)
        let fakeClient = FakeLocalNetworkSyncClient(
            peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac),
            artifactStatusResponses: [
                artifactID: LocalNetworkSyncArtifactStatusResponse(
                    ok: true,
                    artifactID: artifactID,
                    checksum: SecureUploadUtilities.sha256Hex(localData),
                    size: Int64(localData.count),
                    confirmedBytes: resumeOffset,
                    nextOffset: resumeOffset,
                    state: .resuming,
                    error: nil
                )
            ]
        )
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL),
            transferJobStore: LocalNetworkSyncTransferJobStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore
        )

        let plan = await engine.performTick(trigger: "manual", now: Date(timeIntervalSince1970: 3_000), syncRunID: "resume-run")
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(plan?.uploadArtifactActions.contains { $0.entityID == artifactID } == true)
        #expect(fakeClient.artifactStatusRequests.map(\.artifactID).contains(artifactID))
        #expect(fakeClient.artifactPutRequests.first?.offset == resumeOffset)
        #expect(phases.contains("transferSessionStatusFetched"))
        #expect(phases.contains("transferResumeAttempted"))
        #expect(phases.contains("transferResumed"))
    }

    @Test func localNetworkSyncEngineDoesNotCompleteArtifactWhenPeerOnlyReportsFullSizeResuming() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let logicalPath = "transcripts/unconfirmed-full-recording/transcript.md"
        let localData = Data(repeating: 0x55, count: 4 * 1024 * 1024 + 9)
        let localURL = try LocalNetworkSyncArtifactFileService.safeFileURL(
            rootURL: audioStore.baseDirectory(),
            logicalPathToken: logicalPath
        )
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try localData.write(to: localURL)
        let item = StudyItemMetadata(
            recordingID: "unconfirmed-full-recording",
            title: "未确认完成",
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 5,
            transcriptMarkdownRelativePath: logicalPath,
            updatedAt: Date(timeIntervalSince1970: 2_010),
            transcriptionStatus: "transcribed",
            noteStatus: "notStarted"
        )
        _ = try await studyStore.applySyncManifest(
            StudyLibrarySyncManifest.make(
                deviceID: makePairedMacSnapshot().deviceID,
                generatedAt: Date(timeIntervalSince1970: 2_020),
                items: [item],
                folders: []
            ),
            localDeviceID: makePairedMacSnapshot().deviceID
        )
        let artifactID = LocalNetworkSyncArtifactID.make(
            kind: .transcriptMarkdown,
            ownerID: "unconfirmed-full-recording",
            logicalPathToken: logicalPath
        )
        let fakeClient = FakeLocalNetworkSyncClient(
            peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac),
            artifactStatusResponses: [
                artifactID: LocalNetworkSyncArtifactStatusResponse(
                    ok: true,
                    artifactID: artifactID,
                    checksum: SecureUploadUtilities.sha256Hex(localData),
                    size: Int64(localData.count),
                    confirmedBytes: Int64(localData.count),
                    nextOffset: Int64(localData.count),
                    state: .resuming,
                    error: nil
                )
            ]
        )
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL)
        let transferJobStore = LocalNetworkSyncTransferJobStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: RecordingUploadJobStore(audioFileStore: audioStore),
            client: fakeClient,
            stateStore: stateStore,
            transferJobStore: transferJobStore,
            diagnosticsStore: diagnosticsStore
        )

        let plan = await engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 3_000),
            syncRunID: "unconfirmed-full-run"
        )
        let job = try #require(try transferJobStore.loadJobs().first { $0.artifactID == artifactID })

        #expect(plan == nil)
        #expect(fakeClient.artifactPutRequests.isEmpty)
        #expect(job.state != LocalNetworkTransferState.complete)
        #expect(stateStore.state.lastErrorMessage != nil)
        #expect(diagnosticsStore.loadEntries().contains { $0.phase == "syncTickFailed" })
    }

    @Test func localNetworkSyncEngineRejectsOutOfRangeResumeOffsetBeforeUploadingChunk() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let logicalPath = "transcripts/bad-offset-recording/transcript.md"
        let localData = Data(repeating: 0x4F, count: 4 * 1024 * 1024 + 13)
        let localURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: audioStore.baseDirectory(), logicalPathToken: logicalPath)
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try localData.write(to: localURL)
        let item = StudyItemMetadata(
            recordingID: "bad-offset-recording",
            title: "错误 offset",
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 5,
            transcriptMarkdownRelativePath: logicalPath,
            updatedAt: Date(timeIntervalSince1970: 2_010),
            transcriptionStatus: "transcribed",
            noteStatus: "notStarted"
        )
        _ = try await studyStore.applySyncManifest(
            StudyLibrarySyncManifest.make(deviceID: makePairedMacSnapshot().deviceID, generatedAt: Date(timeIntervalSince1970: 2_020), items: [item], folders: []),
            localDeviceID: makePairedMacSnapshot().deviceID
        )
        let artifactID = LocalNetworkSyncArtifactID.make(kind: .transcriptMarkdown, ownerID: "bad-offset-recording", logicalPathToken: logicalPath)
        let fakeClient = FakeLocalNetworkSyncClient(
            peerInventory: emptyLocalNetworkInventory(deviceID: "mac-01", platform: .Mac),
            artifactStatusResponses: [
                artifactID: LocalNetworkSyncArtifactStatusResponse(
                    ok: true,
                    artifactID: artifactID,
                    checksum: SecureUploadUtilities.sha256Hex(localData),
                    size: Int64(localData.count),
                    confirmedBytes: Int64(localData.count) + 1,
                    nextOffset: Int64(localData.count) + 1,
                    state: .resuming,
                    error: nil
                )
            ]
        )
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: fakeClient,
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL),
            transferJobStore: LocalNetworkSyncTransferJobStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore
        )

        let plan = await engine.performTick(trigger: "manual", now: Date(timeIntervalSince1970: 3_000), syncRunID: "bad-offset-run")
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(plan == nil)
        #expect(fakeClient.artifactPutRequests.isEmpty)
        #expect(phases.contains("transferOffsetMismatch"))
        #expect(phases.contains("syncTickFailed"))
    }

    @Test func localNetworkSyncEngineUploadsMissingRecordingAudioThroughExistingCoordinatorAndClearsCardProgress() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let audioData = Data("abcdefghi".utf8)
        let metadata = try saveRecording(
            id: "sync-audio-upload-success",
            title: "本地音频",
            store: audioStore,
            uploadStatus: RecordingUploadStatus.uploaded.rawValue,
            audioData: audioData
        )
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let recordingManager = RecordingManager(fileStore: audioStore)
        let transferJobStore = LocalNetworkSyncTransferJobStore(rootURL: rootURL)
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let uploadClient = FakeRecordingUploadClient(
            result: .success(RecordingUploadResult(
                recordingID: metadata.id,
                metadataFileName: "metadata.json",
                audioFileName: "audio.m4a",
                metadataDisposition: "acceptedExisting",
                audioDisposition: "acceptedNew"
            )),
            events: [
                .metadataStarted,
                .metadataSucceeded(disposition: "acceptedExisting"),
                .audioStarted,
                .audioResumableSessionStarted(
                    sessionID: "session-success",
                    totalBytes: Int64(audioData.count),
                    chunkSize: 3,
                    totalSHA256: SecureUploadUtilities.sha256Hex(audioData),
                    confirmedBytes: 0
                ),
                .audioResumableProgress(
                    sessionID: "session-success",
                    confirmedBytes: Int64(audioData.count),
                    totalBytes: Int64(audioData.count),
                    nextOffset: Int64(audioData.count)
                ),
                .audioSucceeded(disposition: "acceptedNew")
            ]
        )
        let uploadCoordinator = RecordingUploadCoordinator(uploadClient: uploadClient, jobStore: uploadJobStore)
        let syncClient = FakeLocalNetworkSyncClient(peerInventory: peerInventoryMissingAudio(for: metadata))
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            recordingManager: recordingManager,
            uploadCoordinator: uploadCoordinator,
            uploadJobStore: uploadJobStore,
            client: syncClient,
            stateStore: stateStore,
            transferJobStore: transferJobStore,
            diagnosticsStore: diagnosticsStore
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 3_000))
        let transferJob = try #require(try transferJobStore.loadJobs().first { $0.artifactID == "recordingAudio:\(metadata.id)" })
        let ledgerJSON = try String(
            contentsOf: rootURL.appendingPathComponent("Sync/local-network-transfer-ledger.json"),
            encoding: .utf8
        )
        let entries = diagnosticsStore.loadEntries()
        let phases = Set(entries.map(\.phase))
        let syncRunIDs = Set(entries.compactMap(\.syncRunID))

        #expect(plan?.uploadRecordingAudioActions.contains { $0.entityID == metadata.id && $0.reason == "peer_metadata_only" } == true)
        #expect(uploadClient.uploadRequestCount == 1)
        #expect(uploadClient.lastMetadata?.id == metadata.id)
        #expect(syncClient.artifactPutRequests.isEmpty)
        #expect(try audioStore.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.uploaded.rawValue)
        #expect(studyStore.item(recordingID: metadata.id)?.localNetworkTransferProgress == nil)
        #expect(stateStore.state.activeTransfers.isEmpty)
        #expect(transferJob.direction == .upload)
        #expect(transferJob.ownerID == metadata.id)
        #expect(transferJob.objectKind == LocalNetworkSyncObjectKind.recordingAudio.rawValue)
        #expect(transferJob.state == .complete)
        #expect(transferJob.transferredBytes == Int64(audioData.count))
        #expect(transferJob.nextOffset == Int64(audioData.count))
        #expect(transferJob.sha256 == SecureUploadUtilities.sha256Hex(audioData))
        #expect(ledgerJSON.contains(#""version""#))
        #expect(!ledgerJSON.lowercased().contains("sharedsecret"))
        #expect(!ledgerJSON.contains(makePairedMacSnapshot().sharedSecretBase64URL))
        #expect(phases.contains("existingUploadActionCreated"))
        #expect(phases.contains("existingUploadActionQueued"))
        #expect(phases.contains("existingUploadActionStarted"))
        #expect(phases.contains("recordingUploadCoordinatorCalled"))
        #expect(phases.contains("uploadJobCreated"))
        #expect(phases.contains("uploadStarted"))
        #expect(phases.contains("uploadDecisionUploadBecausePeerMetadataOnly"))
        #expect(phases.contains("syncRunCompleted"))
        #expect(syncRunIDs.count == 1)
    }

    @Test func localNetworkSyncEngineDoesNotCallUploadCoordinatorWhenPeerAudioAlreadyAvailable() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let audioData = Data("already-on-mac".utf8)
        let metadata = try saveRecording(
            id: "sync-audio-peer-available",
            title: "已在 Mac",
            store: audioStore,
            uploadStatus: RecordingUploadStatus.uploaded.rawValue,
            audioData: audioData
        )
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let recordingManager = RecordingManager(fileStore: audioStore)
        let uploadClient = FakeRecordingUploadClient(
            result: .success(RecordingUploadResult(
                recordingID: metadata.id,
                metadataFileName: "metadata.json",
                audioFileName: "audio.m4a",
                metadataDisposition: "acceptedExisting",
                audioDisposition: "acceptedExisting"
            ))
        )
        let uploadCoordinator = RecordingUploadCoordinator(uploadClient: uploadClient, jobStore: uploadJobStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            recordingManager: recordingManager,
            uploadCoordinator: uploadCoordinator,
            uploadJobStore: uploadJobStore,
            client: FakeLocalNetworkSyncClient(peerInventory: peerInventoryAudioAvailable(for: metadata, audioData: audioData)),
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore
        )

        let plan = await engine.performTick(trigger: "manual", now: Date(timeIntervalSince1970: 3_000), syncRunID: "iphone-manual-noop")
        _ = await engine.performTick(trigger: "manual-sync-requested", now: Date(timeIntervalSince1970: 3_001), syncRunID: "mac-manual-noop")
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(plan?.uploadRecordingAudioActions.isEmpty == true)
        #expect(uploadClient.uploadRequestCount == 0)
        #expect(phases.contains("syncPeerAudioAvailable"))
        #expect(phases.contains("syncPeerAudioHashMatched"))
        #expect(phases.contains("uploadDecisionNoOpPeerAlreadyHasSameAudio"))
        #expect(phases.contains("iphoneManualSyncNoOpBecausePeerMatches"))
        #expect(phases.contains("macManualSyncNoOpBecausePeerMatches"))
        #expect(!phases.contains("recordingUploadCoordinatorCalled"))
    }

    @Test func localNetworkSyncEngineSuppressesInFlightDuplicateRecordingAudioUpload() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let audioData = Data("in-flight-audio".utf8)
        let metadata = try saveRecording(id: "sync-audio-in-flight", title: "传输中", store: audioStore, audioData: audioData)
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let recordingManager = RecordingManager(fileStore: audioStore)
        let uploadClient = FakeRecordingUploadClient(
            result: .success(RecordingUploadResult(
                recordingID: metadata.id,
                metadataFileName: "metadata.json",
                audioFileName: "audio.m4a",
                metadataDisposition: "acceptedExisting",
                audioDisposition: "acceptedExisting"
            ))
        )
        let uploadCoordinator = RecordingUploadCoordinator(uploadClient: uploadClient, jobStore: uploadJobStore)
        let transferJobStore = LocalNetworkSyncTransferJobStore(rootURL: rootURL)
        try transferJobStore.upsert(
            LocalNetworkSyncTransferJob(
                transferID: "upload:recordingAudio:\(metadata.id)",
                direction: .upload,
                ownerID: metadata.id,
                artifactID: "recordingAudio:\(metadata.id)",
                objectKind: LocalNetworkSyncObjectKind.recordingAudio.rawValue,
                fileName: metadata.fileName,
                logicalName: metadata.relativeAudioPath,
                totalBytes: Int64(audioData.count),
                transferredBytes: 1,
                sha256: SecureUploadUtilities.sha256Hex(audioData),
                chunkSize: nil,
                nextOffset: 1,
                state: .transferring,
                createdAt: Date(timeIntervalSince1970: 2_900),
                updatedAt: Date(timeIntervalSince1970: 2_901),
                lastAttemptAt: Date(timeIntervalSince1970: 2_900),
                nextRetryAfter: nil,
                errorCode: nil,
                errorMessage: nil,
                peerDeviceID: makePairedMacSnapshot().deviceID,
                localTempPath: nil,
                syncRunID: "same-run"
            )
        )
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            recordingManager: recordingManager,
            uploadCoordinator: uploadCoordinator,
            uploadJobStore: uploadJobStore,
            client: FakeLocalNetworkSyncClient(peerInventory: peerInventoryMissingAudio(for: metadata)),
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL),
            transferJobStore: transferJobStore,
            diagnosticsStore: diagnosticsStore
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 3_000), syncRunID: "same-run")
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(plan == nil)
        #expect(uploadClient.uploadRequestCount == 0)
        #expect(phases.contains("uploadDecisionSuppressedInFlight"))
    }

    @Test func localNetworkSyncEngineDeduplicatesSameSyncRunRecordingAudioActions() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "sync-audio-dedup", title: "去重", store: audioStore)
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore,
            client: FakeLocalNetworkSyncClient(peerInventory: peerInventoryMissingAudio(for: metadata)),
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore
        )
        let localInventory = await LocalNetworkSyncInventoryBuilder(
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore
        ).buildRuntimeSnapshot(deviceID: "iphone-01", deviceName: "iPhone", lastKnownPeerRevision: nil).inventory
        let peerInventory = peerInventoryMissingAudio(for: metadata)
        let action = LocalNetworkSyncDiffAction(
            id: "uploadRecordingAudio:recording:\(metadata.id)",
            kind: .uploadRecordingAudio,
            entityKind: "recording",
            entityID: metadata.id,
            reason: "peer_metadata_only"
        )

        let filtered = engine.uploadRecordingAudioActionsToRun(
            [action, action],
            localInventory: localInventory,
            peerInventory: peerInventory,
            settings: makePairedMacSnapshot(),
            syncRunID: "same-run"
        )

        #expect(filtered.count == 1)
        #expect(diagnosticsStore.loadEntries().contains { $0.phase == "uploadDecisionSuppressedQueued" })
    }

    @Test func localViewRefreshDoesNotCreateUploadJob() throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveRecording(id: "view-refresh-no-upload", title: "刷新", store: audioStore)
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let recordingManager = RecordingManager(fileStore: audioStore)

        recordingManager.reloadRecordings()
        studyStore.refresh()
        let decision = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .available(RecordingAudioSignature(sha256: "hash", size: 4)),
            peerAudioState: .metadataOnly,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .folderViewRefresh,
            syncRunID: "view-refresh",
            objectID: "recordingAudio:view-refresh-no-upload",
            recordingID: "view-refresh-no-upload"
        )

        #expect(try jobStore.loadJobs().isEmpty)
        #expect(decision.shouldCreateUploadJob == false)
        #expect(decision.diagnosticStage == "uploadDecisionSuppressedViewRefreshOnly")
    }

    @Test func localNetworkSyncEngineLeavesFailedAudioTransferInCardActionAreaForRetry() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let audioData = Data("abcdefghi".utf8)
        let metadata = try saveRecording(id: "sync-audio-upload-failure", title: "失败音频", store: audioStore, audioData: audioData)
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let recordingManager = RecordingManager(fileStore: audioStore)
        let transferJobStore = LocalNetworkSyncTransferJobStore(rootURL: rootURL)
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL)
        let uploadClient = FakeRecordingUploadClient(
            result: .failure(RecordingUploadError.networkFailed("network lost")),
            events: [
                .metadataStarted,
                .metadataSucceeded(disposition: "acceptedExisting"),
                .audioStarted,
                .audioResumableSessionStarted(
                    sessionID: "session-failure",
                    totalBytes: Int64(audioData.count),
                    chunkSize: 3,
                    totalSHA256: SecureUploadUtilities.sha256Hex(audioData),
                    confirmedBytes: 0
                ),
                .audioResumableProgress(
                    sessionID: "session-failure",
                    confirmedBytes: 3,
                    totalBytes: Int64(audioData.count),
                    nextOffset: 3
                )
            ]
        )
        let uploadCoordinator = RecordingUploadCoordinator(uploadClient: uploadClient, jobStore: uploadJobStore)
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            recordingManager: recordingManager,
            uploadCoordinator: uploadCoordinator,
            uploadJobStore: uploadJobStore,
            client: FakeLocalNetworkSyncClient(peerInventory: peerInventoryMissingAudio(for: metadata)),
            stateStore: stateStore,
            transferJobStore: transferJobStore
        )

        let plan = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 3_000))
        let progress = try #require(studyStore.item(recordingID: metadata.id)?.localNetworkTransferProgress)
        let transferJob = try #require(try transferJobStore.loadJobs().first { $0.artifactID == "recordingAudio:\(metadata.id)" })
        let activeTransfer = try #require(stateStore.state.activeTransfers.first)

        #expect(plan == nil)
        #expect(stateStore.state.lastErrorMessage != nil)
        #expect(try audioStore.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.failed.rawValue)
        #expect(progress.state == .failed)
        #expect(progress.isVisibleInActionArea)
        #expect(progress.receivedBytes == 3)
        #expect(progress.totalBytes == Int64(audioData.count))
        #expect(progress.statusText == "传输失败，可重试")
        #expect(activeTransfer.state == .failed)
        #expect(transferJob.state == .failed)
        #expect(transferJob.transferredBytes == 3)
        #expect(transferJob.nextOffset == 3)
        #expect(transferJob.errorCode == "recording_audio_upload_failed")
        #expect(transferJob.nextRetryAfter != nil)
    }

    @Test func localNetworkSyncEngineAppliesCompletedReceiveStatusToLocalMetadata() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "receive-return-01", title: "待确认上传", store: audioStore, uploadStatus: "failed")
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let peerInventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: Date(timeIntervalSince1970: 2_020),
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [
                LocalNetworkSyncRecordingEntry(
                    recordingID: metadata.id,
                    metadataHash: StudyItemMetadata.defaultMetadata(for: metadata)
                        .localNetworkRecordingBusinessSignatureV2,
                    audioAvailable: true,
                    audioChecksum: nil,
                    audioSize: metadata.fileSize,
                    uploadLedgerState: nil,
                    receiveStatus: "completed",
                    processingStatus: "notStarted",
                    updatedAt: metadata.endedAt.addingTimeInterval(60),
                    deleted: false
                )
            ]
        )
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: jobStore,
            client: FakeLocalNetworkSyncClient(peerInventory: peerInventory),
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL)
        )

        _ = await engine.performTick(trigger: "foreground", now: Date(timeIntervalSince1970: 3_000))

        #expect(try audioStore.loadMetadata(id: metadata.id).uploadStatus == RecordingUploadStatus.uploaded.rawValue)
    }

    @Test func secureUploadServerResponseDecodesMetadataAcceptedNew() throws {
        let response = try decodeSecureUploadResponse("""
        {"audioFileName":null,"disposition":"acceptedNew","metadataFileName":"metadata.json","message":"recording metadata received","ok":true,"processingStatus":"awaitingAudio","receiveFileName":"receive.json","receiveStatus":"metadataReceived","recordingID":"metadata-new"}
        """)

        #expect(response.ok)
        #expect(response.recordingID == "metadata-new")
        #expect(response.metadataFileName == "metadata.json")
        #expect(response.audioFileName == nil)
        #expect(response.disposition == "acceptedNew")
        #expect(response.receiveStatus == "metadataReceived")
        #expect(response.processingStatus == "awaitingAudio")
    }

    @Test func secureUploadServerResponseDecodesMetadataAcceptedExisting() throws {
        let response = try decodeSecureUploadResponse("""
        {"audioFileName":null,"disposition":"acceptedExisting","metadataFileName":"metadata.json","message":"recording metadata received","ok":true,"processingStatus":"awaitingAudio","receiveFileName":"receive.json","receiveStatus":"metadataReceived","recordingID":"metadata-existing"}
        """)

        #expect(response.ok)
        #expect(response.recordingID == "metadata-existing")
        #expect(response.disposition == "acceptedExisting")
        #expect(response.receiveStatus == "metadataReceived")
        #expect(response.processingStatus == "awaitingAudio")
    }

    @Test func secureUploadServerResponseDecodesMetadataConflict() throws {
        let response = try decodeSecureUploadResponse("""
        {"disposition":"rejectedConflict","error":"recording_metadata_conflict","ok":false,"reason":"Conflict"}
        """)
        let error = SecureMacUploadError.serverRejected(response.error ?? "missing_error")

        #expect(!response.ok)
        #expect(response.error == "recording_metadata_conflict")
        #expect(response.disposition == "rejectedConflict")
        #expect(response.reason == "Conflict")
        #expect(error.localizedDescription == "recording_metadata_conflict")
    }

    @Test func secureUploadServerResponseDecodesAudioAcceptedNew() throws {
        let response = try decodeSecureUploadResponse("""
        {"audioFileName":"audio.m4a","disposition":"acceptedNew","metadataFileName":"metadata.json","message":"recording audio received","ok":true,"processingStatus":"notStarted","receiveFileName":"receive.json","receiveStatus":"completed","recordingID":"audio-new"}
        """)

        #expect(response.ok)
        #expect(response.recordingID == "audio-new")
        #expect(response.audioFileName == "audio.m4a")
        #expect(response.disposition == "acceptedNew")
        #expect(response.receiveStatus == "completed")
        #expect(response.processingStatus == "notStarted")
    }

    @Test func secureUploadServerResponseDecodesAudioAcceptedExisting() throws {
        let response = try decodeSecureUploadResponse("""
        {"audioFileName":"audio.m4a","disposition":"acceptedExisting","metadataFileName":"metadata.json","message":"recording audio received","ok":true,"processingStatus":"notStarted","receiveFileName":"receive.json","receiveStatus":"completed","recordingID":"audio-existing"}
        """)

        #expect(response.ok)
        #expect(response.recordingID == "audio-existing")
        #expect(response.audioFileName == "audio.m4a")
        #expect(response.disposition == "acceptedExisting")
        #expect(response.receiveStatus == "completed")
        #expect(response.processingStatus == "notStarted")
    }

    @Test func secureUploadServerResponseDecodesAudioConflict() throws {
        let response = try decodeSecureUploadResponse("""
        {"disposition":"rejectedConflict","error":"recording_audio_conflict","ok":false,"reason":"Conflict"}
        """)
        let error = SecureMacUploadError.serverRejected(response.error ?? "missing_error")

        #expect(!response.ok)
        #expect(response.error == "recording_audio_conflict")
        #expect(response.disposition == "rejectedConflict")
        #expect(response.reason == "Conflict")
        #expect(error.localizedDescription == "recording_audio_conflict")
    }

    @Test func connectionProbeResponseDecodesTinyEchoPayload() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(ConnectionProbeResponse.self, from: Data("""
        {"disposition":"ok","echoedClientPayload":"tiny hello","ok":true,"receivedSequenceNumber":9,"serverPayload":"rokurics-probe-ok","serverTime":"2026-05-26T00:00:00Z"}
        """.utf8))

        #expect(response.ok)
        #expect(response.disposition == "ok")
        #expect(response.receivedSequenceNumber == 9)
        #expect(response.echoedClientPayload == "tiny hello")
        #expect(response.serverPayload == "rokurics-probe-ok")
    }

    @Test func secureUploadServerResponseKeepsLegacyAndMalformedErrorsReadable() throws {
        let legacy = try decodeSecureUploadResponse(#"{"ok":false,"error":"legacy_upload_failed"}"#)

        #expect(!legacy.ok)
        #expect(legacy.error == "legacy_upload_failed")
        #expect(SecureMacUploadError.serverRejected(legacy.error ?? "missing_error").localizedDescription == "legacy_upload_failed")

        do {
            _ = try decodeSecureUploadResponse("not-json")
            Issue.record("Expected malformed JSON to fail decoding")
        } catch {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test func iphoneAIProviderPresetFiltersLocalDesktopProviders() {
        let visible = AIProviderPreset.iPhoneVisibleCases

        #expect(visible.contains(.openAI))
        #expect(visible.contains(.deepSeek))
        #expect(visible.contains(.gemini))
        #expect(visible.contains(.customOpenAICompatible))
        #expect(!visible.contains(.lmStudioLocal))
        #expect(!visible.contains(.ollamaLocal))
    }

    @Test func localNetworkSyncEngineDefaultRuntimeDoesNotUseCanonicalPrimary() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = try saveRecording(id: "v838-default-owner", title: "默认 legacy owner", store: audioStore)
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore,
            client: FakeLocalNetworkSyncClient(peerInventory: peerInventoryMissingAudio(for: metadata)),
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore
        )

        let plan = await engine.performTick(trigger: "manual", now: Date(timeIntervalSince1970: 3_000), syncRunID: "v838-default-owner")
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(plan == nil)
        #expect(phases.contains("syncTickFailed"))
        #expect(phases.contains("canonicalSyncRuntimePlanUsed") == false)
        #expect(phases.contains("canonicalSyncRuntimePlanFallback"))
    }

    @Test func localNetworkSyncEnginePrimaryRuntimeUsesCanonicalMetadataNoOpWithoutAudioJob() async throws {
        let (audioStore, rootURL) = try makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let audioData = Data("canonical same audio".utf8)
        let metadata = try saveRecording(id: "v838-canonical-primary", title: "Canonical primary", store: audioStore, audioData: audioData)
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let localInventory = await LocalNetworkSyncInventoryBuilder(
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore,
            diagnosticsStore: diagnosticsStore
        ).buildRuntimeSnapshot(
            deviceID: "iphone-01",
            deviceName: "iPhone",
            lastKnownPeerRevision: nil,
            shadowSyncRunID: "v838-canonical-primary"
        ).inventory
        let localRecording = try #require(localInventory.recordings.first { $0.recordingID == metadata.id })
        let peerInventory = LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: Date(timeIntervalSince1970: 2_020),
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [
                LocalNetworkSyncRecordingEntry(
                    recordingID: metadata.id,
                    metadataHash: "legacy-mismatch-\(metadata.id)",
                    audioAvailable: true,
                    audioChecksum: localRecording.audioChecksum,
                    audioSize: localRecording.audioSize,
                    uploadLedgerState: nil,
                    receiveStatus: "completed",
                    processingStatus: "notStarted",
                    updatedAt: metadata.createdAt.addingTimeInterval(10),
                    deleted: false,
                    title: metadata.title,
                    createdAt: metadata.createdAt,
                    tombstone: false,
                    audioAvailability: .local,
                    uploadStatus: nil,
                    transcriptionStatus: metadata.transcriptionStatus,
                    noteStatus: metadata.noteStatus,
                    sourceDeviceID: "iphone-01",
                    artifactRefs: nil,
                    audioLogicalPathToken: metadata.relativeAudioPath
                )
            ],
            canonicalManifest: localInventory.canonicalManifest
        )
        let runtimeConfiguration = CanonicalSyncRuntimeConfiguration(
            mode: .canonicalPlanPrimaryWithLegacyFallback,
            policy: CanonicalSyncRuntimePolicy(
                debugInternalBuild: true,
                ownerApproved: true,
                releaseDefaultBuild: false,
                allowDocumentedModifiedAtFallback: true,
                enabledScopes: [.recordingMetadata]
            )
        )
        let engine = LocalNetworkSyncEngine(
            connectionStore: FakeSecureMacConnectionSnapshotProvider(snapshot: makePairedMacSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore,
            client: FakeLocalNetworkSyncClient(peerInventory: peerInventory),
            stateStore: LocalNetworkSyncStateStore(rootURL: rootURL),
            diagnosticsStore: diagnosticsStore,
            canonicalSyncRuntimeConfiguration: runtimeConfiguration
        )

        let plan = await engine.performTick(trigger: "manual", now: Date(timeIntervalSince1970: 3_000), syncRunID: "v838-canonical-primary")
        let entries = diagnosticsStore.loadEntries()
        let phases = Set(entries.map(\.phase))

        #expect(plan?.uploadMetadataActions.contains { $0.entityKind == "recording" && $0.entityID == metadata.id } == false)
        #expect(plan?.downloadMetadataActions.contains { $0.entityKind == "recording" && $0.entityID == metadata.id } == false)
        #expect(plan?.noOps.contains { $0.entityKind == "recording" && $0.entityID == metadata.id && $0.reason == CanonicalSyncPlanReason.metadataHashEqual.rawValue } == true)
        #expect((try? uploadJobStore.loadJobs())?.isEmpty == true)
        #expect(phases.contains("canonicalSyncRuntimePlanUsed"))
        #expect(phases.contains("canonicalSyncRuntimeLegacyHashMismatchIgnored"))
        #expect(phases.contains("canonicalSyncRuntimeDuplicateLegacySuppressed") == false)
    }

    private func makeStore() throws -> (AudioFileStore, URL) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = AudioFileStore(rootDirectoryURL: rootURL)
        try store.ensureStorageDirectories()
        return (store, rootURL)
    }

    private func saveRecording(
        id: String,
        title: String,
        store: AudioFileStore,
        uploadStatus: String = "localOnly",
        studyFiling: StudyFilingPath? = nil,
        audioData: Data = Data("audio".utf8)
    ) throws -> RecordingMetadata {
        let audioURL = try store.recordingsDirectory()
            .appendingPathComponent(id, isDirectory: false)
            .appendingPathExtension("m4a")
        try audioData.write(to: audioURL)
        let metadataURL = try store.makeMetadataURL(id: id)
        let metadata = makeMetadata(
            id: id,
            title: title,
            relativeAudioPath: try store.relativePath(for: audioURL),
            relativeMetadataPath: try store.relativePath(for: metadataURL),
            uploadStatus: uploadStatus,
            studyFiling: studyFiling,
            fileSize: Int64(audioData.count)
        )
        try store.saveMetadata(metadata)
        return metadata
    }

    private func makeMetadata(
        id: String,
        title: String,
        relativeAudioPath: String,
        relativeMetadataPath: String,
        uploadStatus: String,
        studyFiling: StudyFilingPath? = nil,
        fileSize: Int64 = 5
    ) -> RecordingMetadata {
        RecordingMetadata(
            id: id,
            title: title,
            fileName: "\(id).m4a",
            relativeAudioPath: relativeAudioPath,
            relativeMetadataPath: relativeMetadataPath,
            createdAt: Date(timeIntervalSince1970: 1_800),
            endedAt: Date(timeIntervalSince1970: 1_806),
            duration: 6,
            format: "m4a",
            codec: "AAC",
            sampleRate: 16_000,
            channels: 1,
            bitrate: 64_000,
            fileSize: fileSize,
            uploadStatus: uploadStatus,
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            tags: [],
            studyFiling: studyFiling
        )
    }

    private static let studyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let studyDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func decodeSecureUploadResponse(_ json: String) throws -> SecureUploadServerResponse {
        try JSONDecoder().decode(SecureUploadServerResponse.self, from: Data(json.utf8))
    }

    private func peerInventoryMissingAudio(for metadata: RecordingMetadata) -> LocalNetworkSyncInventory {
        let item = StudyItemMetadata.defaultMetadata(for: metadata)
        let recording = LocalNetworkSyncRecordingEntry(
            recordingID: metadata.id,
            metadataHash: item.localNetworkRecordingBusinessSignatureV2,
            audioAvailable: false,
            audioChecksum: nil,
            audioSize: nil,
            uploadLedgerState: nil,
            receiveStatus: "metadataReceived",
            processingStatus: "awaitingAudio",
            updatedAt: metadata.endedAt,
            deleted: false,
            title: metadata.title,
            createdAt: metadata.createdAt,
            tombstone: false,
            audioAvailability: .missing,
            uploadStatus: nil,
            transcriptionStatus: metadata.transcriptionStatus,
            noteStatus: metadata.noteStatus,
            sourceDeviceID: nil,
            artifactRefs: nil
        )
        return LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: Date(timeIntervalSince1970: 2_020),
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [recording],
            studyManifest: StudyLibrarySyncManifest.make(
                deviceID: "mac-01",
                generatedAt: Date(timeIntervalSince1970: 2_020),
                items: [item],
                folders: [],
                recordings: [recording]
            )
        )
    }

    private func peerInventoryAudioAvailable(
        for metadata: RecordingMetadata,
        audioData: Data
    ) -> LocalNetworkSyncInventory {
        let item = StudyItemMetadata.defaultMetadata(for: metadata)
        let recording = LocalNetworkSyncRecordingEntry(
            recordingID: metadata.id,
            metadataHash: item.localNetworkRecordingBusinessSignatureV2,
            audioAvailable: true,
            audioChecksum: SecureUploadUtilities.sha256Hex(audioData),
            audioSize: Int64(audioData.count),
            uploadLedgerState: nil,
            receiveStatus: "completed",
            processingStatus: "notStarted",
            updatedAt: metadata.endedAt,
            deleted: false,
            title: metadata.title,
            createdAt: metadata.createdAt,
            tombstone: false,
            audioAvailability: .local,
            uploadStatus: nil,
            transcriptionStatus: metadata.transcriptionStatus,
            noteStatus: metadata.noteStatus,
            sourceDeviceID: nil,
            artifactRefs: nil
        )
        return LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: "mac-01",
                deviceName: "Mac",
                platform: .Mac,
                generatedAt: Date(timeIntervalSince1970: 2_020),
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            ),
            recordings: [recording],
            studyManifest: StudyLibrarySyncManifest.make(
                deviceID: "mac-01",
                generatedAt: Date(timeIntervalSince1970: 2_020),
                items: [item],
                folders: [],
                recordings: [recording]
            )
        )
    }
}

@MainActor
private final class FakeSecureMacConnectionSnapshotProvider: SecureMacConnectionSnapshotProviding, SecureMacConnectionIntentProviding {
    var snapshot: SecureMacConnectionSnapshot
    var userConnectionIntent: UserConnectionIntent

    init(snapshot: SecureMacConnectionSnapshot, userConnectionIntent: UserConnectionIntent = .wantsConnected) {
        self.snapshot = snapshot
        self.userConnectionIntent = userConnectionIntent
    }
}

private final class FakeRecordingUploadClient: RecordingUploadClientProtocol {
    enum ResultMode {
        case success(RecordingUploadResult)
        case failure(Error)
    }

    let result: ResultMode
    let events: [RecordingUploadProgressEvent]
    private(set) var lastMetadata: RecordingMetadata?
    private(set) var uploadRequestCount = 0

    init(result: ResultMode, events: [RecordingUploadProgressEvent] = []) {
        self.result = result
        self.events = events
    }

    func uploadRecording(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        progress: RecordingUploadProgressHandler?
    ) async throws -> RecordingUploadResult {
        uploadRequestCount += 1
        lastMetadata = metadata
        for event in events {
            try progress?(event)
        }

        switch result {
        case .success(let uploadResult):
            return uploadResult
        case .failure(let error):
            throw error
        }
    }
}

private final class FakeRecordingSecureUploadTransport: RecordingSecureUploadTransport {
    var metadataUploadCount = 0
    var singleFileUploadCount = 0
    var resumableStartCount = 0
    var statusCount = 0
    var finalizeCount = 0
    var chunkOffsets: [Int64] = []
    var failChunkAtOffset: Int64?
    var chunkErrorAtOffset: (offset: Int64, error: Error)?
    var statusConfirmedBytes: Int64?
    var statusError: Error?
    var finalizeDisposition = "acceptedNew"

    private var sessionID = "session-1"
    private var confirmedBytes: Int64 = 0
    private var totalBytes: Int64 = 0
    private var chunkSize = 0

    func uploadSignedData(
        settings: SecureMacConnectionSnapshot,
        path: String,
        body: Data,
        contentType: String,
        uploadType: String,
        recordingID: String,
        fileName: String,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) async throws -> SecureUploadServerResponse {
        metadataUploadCount += 1
        return SecureUploadServerResponse(
            ok: true,
            message: "metadata received",
            disposition: "acceptedNew",
            fileName: nil,
            recordingID: recordingID,
            metadataFileName: "metadata.json",
            audioFileName: nil,
            receiveStatus: "metadataReceived",
            processingStatus: "awaitingAudio",
            error: nil,
            reason: nil
        )
    }

    func uploadSignedFile(
        settings: SecureMacConnectionSnapshot,
        path: String,
        fileURL: URL,
        contentType: String,
        uploadType: String,
        recordingID: String,
        fileName: String,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) async throws -> SecureUploadServerResponse {
        singleFileUploadCount += 1
        return SecureUploadServerResponse(
            ok: true,
            message: "audio received",
            disposition: "acceptedNew",
            fileName: "audio.m4a",
            recordingID: recordingID,
            metadataFileName: nil,
            audioFileName: "audio.m4a",
            receiveStatus: "completed",
            processingStatus: "notStarted",
            error: nil,
            reason: nil
        )
    }

    func startResumableAudioUpload(
        settings: SecureMacConnectionSnapshot,
        request: ResumableAudioUploadStartRequest
    ) async throws -> ResumableAudioUploadSessionResponse {
        resumableStartCount += 1
        sessionID = "session-1"
        totalBytes = request.totalBytes
        chunkSize = request.chunkSize
        confirmedBytes = 0
        return sessionResponse(
            disposition: "acceptedNew",
            confirmedBytes: confirmedBytes,
            chunkSize: request.chunkSize,
            completed: false
        )
    }

    func fetchResumableAudioUploadStatus(
        settings: SecureMacConnectionSnapshot,
        request: ResumableAudioUploadStatusRequest
    ) async throws -> ResumableAudioUploadSessionResponse {
        statusCount += 1
        if let statusError {
            throw statusError
        }
        if let statusConfirmedBytes {
            confirmedBytes = statusConfirmedBytes
        }
        return sessionResponse(
            disposition: "acceptedExisting",
            confirmedBytes: confirmedBytes,
            chunkSize: chunkSize == 0 ? nil : chunkSize,
            completed: false
        )
    }

    func uploadResumableAudioChunk(
        settings: SecureMacConnectionSnapshot,
        recordingID: String,
        sessionID: String,
        offset: Int64,
        totalSHA256: String,
        chunk: Data
    ) async throws -> ResumableAudioUploadSessionResponse {
        if let chunkErrorAtOffset, chunkErrorAtOffset.offset == offset {
            throw chunkErrorAtOffset.error
        }
        if failChunkAtOffset == offset {
            throw RecordingUploadError.networkFailed("network lost")
        }

        chunkOffsets.append(offset)
        confirmedBytes = offset + Int64(chunk.count)
        return sessionResponse(
            disposition: "acceptedNew",
            confirmedBytes: confirmedBytes,
            chunkSize: chunkSize == 0 ? chunk.count : chunkSize,
            completed: false,
            chunkAccepted: true
        )
    }

    func finalizeResumableAudioUpload(
        settings: SecureMacConnectionSnapshot,
        request: ResumableAudioUploadFinalizeRequest
    ) async throws -> ResumableAudioUploadSessionResponse {
        finalizeCount += 1
        confirmedBytes = request.totalBytes
        totalBytes = request.totalBytes
        return sessionResponse(
            disposition: finalizeDisposition,
            confirmedBytes: request.totalBytes,
            chunkSize: chunkSize == 0 ? nil : chunkSize,
            completed: true,
            finalAudioExists: true,
            finalAudioRelativePath: "audio/inbox/day/\(request.recordingID)/audio.m4a",
            checksum: request.totalSHA256,
            fileSize: request.totalBytes
        )
    }

    private func sessionResponse(
        disposition: String,
        confirmedBytes: Int64,
        chunkSize: Int?,
        completed: Bool,
        chunkAccepted: Bool? = nil,
        finalAudioExists: Bool? = nil,
        finalAudioRelativePath: String? = nil,
        checksum: String? = nil,
        fileSize: Int64? = nil
    ) -> ResumableAudioUploadSessionResponse {
        ResumableAudioUploadSessionResponse(
            ok: true,
            disposition: disposition,
            status: completed ? "completed" : "active",
            sessionID: sessionID,
            confirmedBytes: confirmedBytes,
            nextOffset: confirmedBytes,
            chunkSize: chunkSize,
            completed: completed,
            finalAudioExists: finalAudioExists,
            chunkAccepted: chunkAccepted,
            finalAudioRelativePath: finalAudioRelativePath,
            checksum: checksum,
            fileSize: fileSize,
            receiveStatus: completed ? "completed" : nil,
            processingStatus: completed ? "notStarted" : nil,
            error: nil,
            reason: nil
        )
    }
}

private final class FakeLocalNetworkSyncClient: LocalNetworkSyncClientProtocol {
    let peerInventory: LocalNetworkSyncInventory
    var artifactResponses: [String: LocalNetworkSyncArtifactResponse]
    var artifactStatusResponses: [String: LocalNetworkSyncArtifactStatusResponse]
    var applyMetadataResponse: StudyLibrarySyncManifestResponse?
    var onArtifactRequest: ((String) -> Void)?
    var onArtifactPut: ((LocalNetworkSyncArtifactPutRequest) -> Void)?
    var onStartSignal: ((LocalNetworkSyncStartRequest) -> Void)?
    private(set) var inventoryRequestCount = 0
    private(set) var applyMetadataCount = 0
    private(set) var artifactRequestIDs: [String] = []
    private(set) var artifactPutRequests: [LocalNetworkSyncArtifactPutRequest] = []
    private(set) var inventorySyncRunIDs: [String?] = []
    private(set) var startRequests: [LocalNetworkSyncStartRequest] = []
    private(set) var ackRequests: [LocalNetworkSyncStartAckRequest] = []
    private(set) var artifactStatusRequests: [LocalNetworkSyncArtifactStatusRequest] = []

    init(
        peerInventory: LocalNetworkSyncInventory,
        artifactResponses: [String: LocalNetworkSyncArtifactResponse] = [:],
        artifactStatusResponses: [String: LocalNetworkSyncArtifactStatusResponse] = [:],
        applyMetadataResponse: StudyLibrarySyncManifestResponse? = nil
    ) {
        self.peerInventory = peerInventory
        self.artifactResponses = artifactResponses
        self.artifactStatusResponses = artifactStatusResponses
        self.applyMetadataResponse = applyMetadataResponse
    }

    func sendDeviceStatus(
        settings: SecureMacConnectionSnapshot,
        statusRequest: DeviceStatusRequest
    ) async throws -> DeviceStatusResponse {
        DeviceStatusResponse(ok: true, status: nil, syncState: nil, error: nil)
    }

    func fetchLocalNetworkSyncInventory(
        settings: SecureMacConnectionSnapshot,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String?
    ) async throws -> LocalNetworkSyncInventoryResponse {
        inventoryRequestCount += 1
        inventorySyncRunIDs.append(syncRunID)
        return LocalNetworkSyncInventoryResponse(ok: true, inventory: peerInventory, error: nil)
    }

    func sendLocalNetworkSyncStartSignal(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartRequest
    ) async throws -> LocalNetworkSyncStartResponse {
        onStartSignal?(request)
        startRequests.append(request)
        return LocalNetworkSyncStartResponse(
            ok: true,
            syncRunID: request.syncRunID,
            peerDeviceID: "mac-01",
            ackAt: Date(),
            disposition: "ack",
            error: nil
        )
    }

    func sendLocalNetworkSyncStartAck(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartAckRequest
    ) async throws -> LocalNetworkSyncStartAckResponse {
        ackRequests.append(request)
        return LocalNetworkSyncStartAckResponse(
            ok: true,
            syncRunID: request.syncRunID,
            peerDeviceID: "mac-01",
            ackReceivedAt: Date(),
            error: nil
        )
    }

    func applyLocalNetworkSyncMetadata(
        settings: SecureMacConnectionSnapshot,
        manifest: StudyLibrarySyncManifest
    ) async throws -> StudyLibrarySyncManifestResponse {
        applyMetadataCount += 1
        if let applyMetadataResponse {
            return applyMetadataResponse
        }
        return StudyLibrarySyncManifestResponse(
            ok: true,
            manifest: nil,
            syncState: nil,
            deviceStatus: nil,
            applyResult: StudyLibrarySyncApplyResult(),
            baseCommitID: nil,
            newCommitID: nil,
            remoteChanges: nil,
            rejectedChanges: nil,
            error: nil
        )
    }

    func requestLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        artifactID: String
    ) async throws -> LocalNetworkSyncArtifactResponse {
        try await requestLocalNetworkSyncArtifact(
            settings: settings,
            request: LocalNetworkSyncArtifactRequest(artifactID: artifactID)
        )
    }

    func requestLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactRequest
    ) async throws -> LocalNetworkSyncArtifactResponse {
        artifactRequestIDs.append(request.artifactID)
        onArtifactRequest?(request.artifactID)
        guard var response = artifactResponses[request.artifactID] else {
            return LocalNetworkSyncArtifactResponse(
                ok: false,
                artifactID: nil,
                kind: nil,
                checksum: nil,
                size: nil,
                logicalPathToken: nil,
                dataBase64: nil,
                error: "missing_fake_artifact"
            )
        }
        if let offset = request.offset,
           let length = request.length,
           let base64 = response.dataBase64,
           let data = Data(base64Encoded: base64) {
            let start = Int(offset)
            let end = min(start + length, data.count)
            guard start >= 0, start < data.count, end >= start else {
                return LocalNetworkSyncArtifactResponse(
                    ok: false,
                    artifactID: nil,
                    kind: nil,
                    checksum: nil,
                    size: nil,
                    logicalPathToken: nil,
                    dataBase64: nil,
                    error: "missing_fake_artifact_chunk"
                )
            }
            let chunk = data.subdata(in: start..<end)
            response.size = Int64(chunk.count)
            response.checksum = SecureUploadUtilities.sha256Hex(chunk)
            response.dataBase64 = chunk.base64EncodedString()
            response.offset = offset
            response.totalSize = Int64(data.count)
            response.isFinalChunk = end == data.count
        }
        return response
    }

    func putLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactPutRequest
    ) async throws -> LocalNetworkSyncArtifactPutResponse {
        onArtifactPut?(request)
        artifactPutRequests.append(request)
        return LocalNetworkSyncArtifactPutResponse(
            ok: true,
            artifactID: request.artifactID,
            disposition: "acceptedNew",
            checksum: request.checksum,
            size: request.size,
            confirmedBytes: request.offset.map { $0 + Int64(request.chunkSize ?? 0) } ?? request.size,
            error: nil
        )
    }

    func fetchLocalNetworkSyncArtifactStatus(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactStatusRequest
    ) async throws -> LocalNetworkSyncArtifactStatusResponse {
        artifactStatusRequests.append(request)
        if let response = artifactStatusResponses[request.artifactID] {
            return response
        }
        return LocalNetworkSyncArtifactStatusResponse(
            ok: true,
            artifactID: request.artifactID,
            checksum: request.checksum,
            size: request.size,
            confirmedBytes: 0,
            nextOffset: 0,
            state: .pending,
            error: nil
        )
    }
}

private final class FakeLocalNetworkHeartbeatClient: LocalNetworkHeartbeatClientProtocol {
    private(set) var requests: [ConnectionHeartbeatRequest] = []
    private(set) var maxConcurrentRequests = 0
    private var inFlightRequests = 0
    var error: Error?
    var delayNanoseconds: UInt64
    var syncRequested = false
    var syncStartSignal: LocalNetworkSyncStartSignal?
    var ackError: Error?
    private(set) var ackRequests: [LocalNetworkSyncStartAckRequest] = []

    init(error: Error? = nil, delayNanoseconds: UInt64 = 0) {
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    func sendConnectionHeartbeat(
        settings: SecureMacConnectionSnapshot,
        request: ConnectionHeartbeatRequest,
        requestTimeout: TimeInterval
    ) async throws -> ConnectionHeartbeatResponse {
        requests.append(request)
        inFlightRequests += 1
        maxConcurrentRequests = max(maxConcurrentRequests, inFlightRequests)
        defer {
            inFlightRequests -= 1
        }
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let error {
            throw error
        }
        return ConnectionHeartbeatResponse(
            ok: true,
            disposition: "ok",
            peerDeviceID: "mac-01",
            serverTime: Date(),
            receivedSequenceNumber: request.sequenceNumber,
            connectionStatusRevision: request.lastKnownPeerStatusRevision ?? 0,
            minimumSuggestedInterval: nil,
            syncRequested: syncRequested,
            syncStartSignal: syncStartSignal,
            status: nil,
            error: nil
        )
    }

    func sendLocalNetworkSyncStartAck(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartAckRequest
    ) async throws -> LocalNetworkSyncStartAckResponse {
        ackRequests.append(request)
        if let ackError {
            throw ackError
        }
        return LocalNetworkSyncStartAckResponse(
            ok: true,
            syncRunID: request.syncRunID,
            peerDeviceID: "mac-01",
            ackReceivedAt: Date(),
            error: nil
        )
    }
}

private func emptyLocalNetworkInventory(
    deviceID: String,
    platform: LocalNetworkSyncPlatform
) -> LocalNetworkSyncInventory {
    LocalNetworkSyncInventory.make(
        device: LocalNetworkSyncDeviceSection(
            deviceID: deviceID,
            deviceName: platform == .Mac ? "Mac" : "iPhone",
            platform: platform,
            generatedAt: Date(timeIntervalSince1970: 1),
            lastKnownPeerRevision: nil,
            appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
        )
    )
}

private func makePairedMacSnapshot() -> SecureMacConnectionSnapshot {
    SecureMacConnectionSnapshot(
        macHost: "127.0.0.1",
        macPort: 8787,
        macFingerprint: String(repeating: "a", count: 64),
        macName: "Rokurics Mac",
        macModel: "Mac",
        deviceID: "mac-disabled",
        sharedSecretBase64URL: "c3luYy1zZWNyZXQ",
        pairedAt: "2026-05-22T00:00:00Z"
    )
}

private func makeUnpairedMacSnapshot() -> SecureMacConnectionSnapshot {
    SecureMacConnectionSnapshot(
        macHost: "",
        macPort: SecureMacConnectionSettings.defaultPort,
        macFingerprint: "",
        macName: "",
        macModel: "",
        deviceID: "",
        sharedSecretBase64URL: "",
        pairedAt: ""
    )
}

struct CanonicalManifestRecordingsSchemaTests {
    @Test func oldManifestWithoutRecordingsDecodesToEmpty() throws {
        let manifest = try Self.decoder.decode(StudyLibrarySyncManifest.self, from: Data("""
        {
          "deviceID": "old-device",
          "generatedAt": "2026-06-11T00:00:00Z",
          "libraryVersion": 1,
          "items": [],
          "folders": [],
          "tombstones": [],
          "pendingUploads": [],
          "checksum": ""
        }
        """.utf8))

        #expect(manifest.recordings.isEmpty)
        #expect(manifest.items.isEmpty)
        #expect(manifest.folders.isEmpty)
    }

    @Test func newManifestWithRecordingsDecodesAndMissingAudioFactsRemainUnavailable() throws {
        let manifest = try Self.decoder.decode(StudyLibrarySyncManifest.self, from: Data("""
        {
          "deviceID": "iphone-device",
          "generatedAt": "2026-06-11T00:00:00Z",
          "libraryVersion": 1,
          "items": [],
          "folders": [],
          "tombstones": [],
          "pendingUploads": [],
          "recordings": [
            {
              "recordingID": "recording-schema",
              "metadataHash": "metadata-hash",
              "updatedAt": "2026-06-11T00:00:00Z",
              "deleted": false,
              "title": "Schema Recording"
            }
          ],
          "checksum": ""
        }
        """.utf8))
        let recording = try #require(manifest.recordings.first)

        #expect(recording.recordingID == "recording-schema")
        #expect(recording.audioAvailable == false)
        #expect(recording.audioChecksum == nil)
        #expect(recording.audioSize == nil)
    }

    @Test func malformedRecordingFactFailsClosed() {
        let data = Data("""
        {
          "deviceID": "iphone-device",
          "generatedAt": "2026-06-11T00:00:00Z",
          "libraryVersion": 1,
          "items": [],
          "folders": [],
          "tombstones": [],
          "pendingUploads": [],
          "recordings": [
            {
              "metadataHash": "metadata-hash",
              "updatedAt": "2026-06-11T00:00:00Z",
              "deleted": false
            }
          ],
          "checksum": ""
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            _ = try Self.decoder.decode(StudyLibrarySyncManifest.self, from: data)
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct CanonicalAudioUploadCandidateTests {
    @Test func peerMetadataOnlyCreatesUploadCandidate() {
        let decision = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .available(Self.localSignature),
            peerAudioState: .metadataOnly,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .periodicSync,
            syncRunID: "candidate-run",
            objectID: "recordingAudio:candidate",
            recordingID: "candidate"
        )

        #expect(decision.shouldCreateUploadJob)
        #expect(decision.reasonCode == "peer_metadata_only")
    }

    @Test func receiveRecordOnlyAndStudyItemOnlyTruthCreateUploadCandidateWithoutAudioProof() {
        let receiveRecordOnly = CanonicalRecordingExistenceTruth.evaluate(
            objectID: "candidate",
            local: Self.recordingObject(audioHash: Self.hash("a"), byteSize: 10),
            peer: nil,
            peerReceiveRecordExists: true
        )
        let studyItemOnly = CanonicalRecordingExistenceTruth.evaluate(
            objectID: "candidate",
            local: Self.recordingObject(audioHash: Self.hash("a"), byteSize: 10),
            peer: nil,
            peerStudyItemExists: true
        )

        #expect(receiveRecordOnly.decision == .uploadAudioCandidate)
        #expect(receiveRecordOnly.peerAudioAvailable == false)
        #expect(studyItemOnly.decision == .uploadAudioCandidate)
        #expect(studyItemOnly.peerAudioAvailable == false)
    }

    @Test func peerSameHashSizeNoOpsPeerUnknownDefersAndDifferentHashConflicts() {
        let same = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .available(Self.localSignature),
            peerAudioState: .available(Self.localSignature),
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .periodicSync,
            syncRunID: "candidate-run",
            objectID: "recordingAudio:candidate",
            recordingID: "candidate"
        )
        let unknown = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .available(Self.localSignature),
            peerAudioState: .unknown,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .periodicSync,
            syncRunID: "candidate-run",
            objectID: "recordingAudio:candidate",
            recordingID: "candidate"
        )
        let conflict = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .available(Self.localSignature),
            peerAudioState: .different(RecordingAudioSignature(sha256: Self.hash("b"), size: 10)),
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .periodicSync,
            syncRunID: "candidate-run",
            objectID: "recordingAudio:candidate",
            recordingID: "candidate"
        )

        #expect(same.kind == .noOp)
        #expect(same.reasonCode == "peer_already_has_same_audio")
        #expect(unknown.kind == .suppress)
        #expect(unknown.reasonCode == "peer_audio_unknown_deferred")
        #expect(conflict.kind == .fail)
        #expect(conflict.reasonCode == "peer_audio_conflict")
    }

    @Test func localAudioMissingOrViewRefreshDoesNotCreateUploadCandidate() {
        let localMissing = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .missing,
            peerAudioState: .metadataOnly,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .periodicSync,
            syncRunID: "candidate-run",
            objectID: "recordingAudio:candidate",
            recordingID: "candidate"
        )
        let viewRefresh = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: .available(Self.localSignature),
            peerAudioState: .metadataOnly,
            transferJobState: .none,
            ledgerState: .none,
            triggerSource: .folderViewRefresh,
            syncRunID: "candidate-run",
            objectID: "recordingAudio:candidate",
            recordingID: "candidate"
        )

        #expect(localMissing.shouldCreateUploadJob == false)
        #expect(localMissing.reasonCode == "local_audio_missing")
        #expect(viewRefresh.shouldCreateUploadJob == false)
        #expect(viewRefresh.reasonCode == "view_refresh_only")
    }

    private static let localSignature = RecordingAudioSignature(sha256: hash("a"), size: 10)

    private static func recordingObject(
        objectID: String = "candidate",
        audioHash: String?,
        byteSize: Int64?
    ) -> CanonicalRecordingObject {
        let metadata = CanonicalRecordingMetadata(
            objectID: objectID,
            title: "Candidate",
            createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1)),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2))
        )
        let artifacts: [CanonicalArtifact]
        if let audioHash {
            artifacts = [
                CanonicalArtifact(
                    artifactID: CanonicalArtifact.Kind.audio.artifactID(for: objectID),
                    objectID: objectID,
                    kind: .audio,
                    availability: .available,
                    contentHash: CanonicalHash(audioHash),
                    byteSize: byteSize
                )
            ]
        } else {
            artifacts = []
        }
        return CanonicalRecordingObject(
            objectID: objectID,
            nodeID: "iphone-test",
            metadata: metadata,
            artifacts: artifacts
        )
    }

    private static func hash(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }
}

struct CanonicalRecordingExistenceTruthTests {
    @Test func metadataOnlyIsNotAudioAvailable() {
        let truth = CanonicalRecordingExistenceTruth.evaluate(
            objectID: "recording-existence",
            local: Self.recordingObject(audioHash: Self.hash("a"), byteSize: 10),
            peer: Self.recordingObject(audioHash: nil, byteSize: nil)
        )

        #expect(truth.peerState == .metadataOnly)
        #expect(truth.peerAudioAvailable == false)
        #expect(truth.decision == .uploadAudioCandidate)
    }

    @Test func receiveRecordOnlyWithoutAudioIsNotAudioAvailable() {
        let truth = CanonicalRecordingExistenceTruth.evaluate(
            objectID: "recording-existence",
            local: Self.recordingObject(audioHash: Self.hash("a"), byteSize: 10),
            peer: nil,
            peerReceiveRecordExists: true
        )

        #expect(truth.peerState == .receiveRecordOnly)
        #expect(truth.peerAudioAvailable == false)
        #expect(truth.blockers.contains(.receiveRecordNotAudioProof))
    }

    @Test func completedLedgerAloneIsNotAudioNoOp() {
        let truth = CanonicalRecordingExistenceTruth.evaluate(
            objectID: "recording-existence",
            local: Self.recordingObject(audioHash: Self.hash("a"), byteSize: 10),
            peer: Self.recordingObject(audioHash: nil, byteSize: nil),
            peerCompletedLedgerOnly: true
        )

        #expect(truth.decision != .audioSameNoOp)
        #expect(truth.blockers.contains(.completedLedgerNotAudioProof))
    }

    @Test func sameHashAndSizeIsAudioNoOp() {
        let truth = CanonicalRecordingExistenceTruth.evaluate(
            objectID: "recording-existence",
            local: Self.recordingObject(audioHash: Self.hash("a"), byteSize: 10),
            peer: Self.recordingObject(audioHash: Self.hash("a"), byteSize: 10)
        )

        #expect(truth.peerState == .audioHashSizeMatched)
        #expect(truth.decision == .audioSameNoOp)
    }

    @Test func differentHashOrSizeIsConflict() {
        let hashConflict = CanonicalRecordingExistenceTruth.evaluate(
            objectID: "recording-existence",
            local: Self.recordingObject(audioHash: Self.hash("a"), byteSize: 10),
            peer: Self.recordingObject(audioHash: Self.hash("b"), byteSize: 10)
        )
        let sizeConflict = CanonicalRecordingExistenceTruth.evaluate(
            objectID: "recording-existence",
            local: Self.recordingObject(audioHash: Self.hash("a"), byteSize: 10),
            peer: Self.recordingObject(audioHash: Self.hash("a"), byteSize: 11)
        )

        #expect(hashConflict.decision == .conflict)
        #expect(hashConflict.blockers.contains(.audioHashMismatch))
        #expect(sizeConflict.decision == .conflict)
        #expect(sizeConflict.blockers.contains(.audioSizeMismatch))
    }

    @Test func peerUnknownIsDeferred() {
        let truth = CanonicalRecordingExistenceTruth.evaluate(
            objectID: "recording-existence",
            local: Self.recordingObject(audioHash: Self.hash("a"), byteSize: 10),
            peer: nil,
            peerKnown: false
        )

        #expect(truth.peerState == .peerUnknown)
        #expect(truth.decision == .deferred)
    }

    @Test func tombstonedObjectBlocksApplyAndUpload() {
        let truth = CanonicalRecordingExistenceTruth.evaluate(
            objectID: "recording-existence",
            local: Self.recordingObject(audioHash: Self.hash("a"), byteSize: 10),
            peer: nil,
            tombstonedParent: true
        )

        #expect(truth.decision == .blocked)
        #expect(truth.blockers.contains(.tombstonedParent))
    }

    @Test func diagnosticsAreRedacted() {
        let fullHash = Self.hash("a")
        let truth = CanonicalRecordingExistenceTruth.evaluate(
            objectID: "/Users/private/recording-existence",
            local: Self.recordingObject(objectID: "/Users/private/recording-existence", audioHash: fullHash, byteSize: 10),
            peer: nil,
            peerKnown: false
        )
        let diagnostics = truth.diagnostics(syncRunID: "existence-test", mode: .diagnosticsOnly)
        let diagnosticsRedacted = diagnostics.allSatisfy(\.isRedacted)

        #expect(diagnosticsRedacted)
        #expect(!diagnostics.map { $0.summary() }.joined().contains(fullHash))
        #expect(!diagnostics.map { $0.summary() }.joined().contains("/Users/private"))
    }

    private static func recordingObject(
        objectID: String = "recording-existence",
        audioHash: String?,
        byteSize: Int64?
    ) -> CanonicalRecordingObject {
        let metadata = CanonicalRecordingMetadata(
            objectID: objectID,
            title: "Existence Test",
            createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1)),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 2))
        )
        let artifacts: [CanonicalArtifact]
        if let audioHash {
            artifacts = [
                CanonicalArtifact(
                    artifactID: CanonicalArtifact.Kind.audio.artifactID(for: objectID),
                    objectID: objectID,
                    kind: .audio,
                    availability: .available,
                    contentHash: CanonicalHash(audioHash),
                    byteSize: byteSize
                )
            ]
        } else {
            artifacts = []
        }
        return CanonicalRecordingObject(
            objectID: objectID,
            nodeID: "iphone-test",
            metadata: metadata,
            artifacts: artifacts
        )
    }

    private static func hash(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }
}
