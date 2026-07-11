//
//  StudyLibrarySyncModels.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import CryptoKit
import Foundation

extension Notification.Name {
    static let localNetworkStudyLibraryDidChange = Notification.Name("Rokurics.localNetworkStudyLibraryDidChange")
    static let localNetworkSyncEventTriggered = Notification.Name("Rokurics.localNetworkSyncEventTriggered")
    static let localNetworkStatusConvergenceRefreshRequested = Notification.Name("Rokurics.localNetworkStatusConvergenceRefreshRequested")
}

nonisolated enum SyncTriggerReason: String, Codable, CaseIterable, Sendable {
    case manualPeerSyncRequested
    case recordingCreated
    case recordingMetadataChanged
    case studyLibraryMetadataChanged
    case generatedArtifactAvailabilityChanged
    case tombstoneConflictChanged
    case audioUploadFinalized
    case macAudioReceiveFinalized
    case transcriptionStatusChanged
    case noteStatusChanged
    case syncStatusRefreshRequested
    case retryStateChanged
    case appForegroundedWithPendingChanges
}

nonisolated enum LocalNetworkSyncEventTrigger {
    static let reasonUserInfoKey = "reason"
    static let sourceUserInfoKey = "source"
    static let recordingIDUserInfoKey = "recordingID"

    static func reason(from notification: Notification) -> SyncTriggerReason? {
        if let reason = notification.userInfo?[reasonUserInfoKey] as? SyncTriggerReason {
            return reason
        }
        if let rawReason = notification.userInfo?[reasonUserInfoKey] as? String {
            return SyncTriggerReason(rawValue: rawReason)
        }
        return nil
    }

    static func post(
        _ reason: SyncTriggerReason,
        source: String,
        recordingID: String? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        var userInfo: [String: Any] = [
            reasonUserInfoKey: reason.rawValue,
            sourceUserInfoKey: source
        ]
        if let recordingID {
            userInfo[recordingIDUserInfoKey] = String(recordingID.prefix(12))
        }
        notificationCenter.post(name: .localNetworkSyncEventTriggered, object: nil, userInfo: userInfo)
    }

    static func postStatusConvergenceRefresh(
        _ reason: SyncTriggerReason,
        source: String,
        recordingID: String? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        post(reason, source: source, recordingID: recordingID, notificationCenter: notificationCenter)
        var userInfo: [String: Any] = [
            reasonUserInfoKey: reason.rawValue,
            sourceUserInfoKey: source
        ]
        if let recordingID {
            userInfo[recordingIDUserInfoKey] = String(recordingID.prefix(12))
        }
        notificationCenter.post(name: .localNetworkStatusConvergenceRefreshRequested, object: nil, userInfo: userInfo)
    }
}

struct StudyLibrarySyncRuntimeConfiguration: Equatable, Sendable {
    var gitBackedSyncEnabled: Bool

    static let disabledReason = "Git-backed study sync is disabled"
    static let disabledStatusText = "同步已暂停"

    static let `default` = StudyLibrarySyncRuntimeConfiguration(gitBackedSyncEnabled: false)
    static let disabled = StudyLibrarySyncRuntimeConfiguration(gitBackedSyncEnabled: false)
    static let gitBackedEnabled = StudyLibrarySyncRuntimeConfiguration(gitBackedSyncEnabled: true)
}

enum DeviceConnectionLifecycleState: String, Codable, Equatable {
    case unpaired
    case offline
    case connecting
    case connected
}

enum ConnectionPresenceState: String, Codable, Equatable {
    case unknown
    case connecting
    case online
    case interrupted
    case stale
    case disconnected
    case securityError
}

enum ConnectionMonitoringMode: String, Codable, Equatable {
    case foregroundActive
    case suspended
    case disabled
}

struct DeviceConnectionStatus: Codable, Equatable, Identifiable {
    var id: String { deviceID }

    var deviceID: String
    var displayName: String
    var state: DeviceConnectionLifecycleState
    var lastSeenAt: Date?
    var lastHeartbeatAt: Date?
    var lastSyncAt: Date?
    var lastSyncStatus: String?
    var lastError: String?
    var presenceState: ConnectionPresenceState?
    var monitoringMode: ConnectionMonitoringMode?
    var lastHeartbeatSentAt: Date?
    var lastHeartbeatReceivedAt: Date?
    var lastSuccessfulHeartbeatAt: Date?
    var lastSignedRequestSucceededAt: Date?
    var missedHeartbeatCount: Int?
    var consecutiveFailureCount: Int?
    var latencyMilliseconds: Double?
    var lastErrorCode: String?
    var connectionStatusRevision: Int?

    static func unpaired(displayName: String = "Mac") -> DeviceConnectionStatus {
        DeviceConnectionStatus(
            deviceID: "unpaired",
            displayName: displayName,
            state: .unpaired,
            lastSeenAt: nil,
            lastHeartbeatAt: nil,
            lastSyncAt: nil,
            lastSyncStatus: nil,
            lastError: nil,
            presenceState: .unknown,
            monitoringMode: .disabled,
            lastHeartbeatSentAt: nil,
            lastHeartbeatReceivedAt: nil,
            lastSuccessfulHeartbeatAt: nil,
            lastSignedRequestSucceededAt: nil,
            missedHeartbeatCount: 0,
            consecutiveFailureCount: 0,
            latencyMilliseconds: nil,
            lastErrorCode: nil,
            connectionStatusRevision: 0
        )
    }
}

struct ConnectionPresenceSnapshot: Equatable {
    var state: ConnectionPresenceState
    var lifecycleState: DeviceConnectionLifecycleState
    var lastEvidenceAt: Date?
    var lastSeenAt: Date?
    var interruptedSeconds: Int
    var statusText: String
    var recentOnlineText: String
    var isOnline: Bool
    var isSuspended: Bool
}

extension DeviceConnectionStatus {
    func presenceSnapshot(
        now: Date = Date(),
        staleAfter: TimeInterval = 5,
        disconnectedAfter: TimeInterval = 10,
        missedHeartbeatLimit: Int = 3
    ) -> ConnectionPresenceSnapshot {
        if state == .unpaired {
            return ConnectionPresenceSnapshot(
                state: .unknown,
                lifecycleState: .unpaired,
                lastEvidenceAt: nil,
                lastSeenAt: nil,
                interruptedSeconds: 0,
                statusText: "未配对",
                recentOnlineText: "暂无",
                isOnline: false,
                isSuspended: monitoringMode == .disabled
            )
        }

        let evidenceAt = latestPresenceEvidenceAt
        let ageSeconds = evidenceAt.map { max(0, Int(now.timeIntervalSince($0).rounded(.down))) } ?? 0

        if presenceState == .securityError {
            return ConnectionPresenceSnapshot(
                state: .securityError,
                lifecycleState: .offline,
                lastEvidenceAt: evidenceAt,
                lastSeenAt: lastSeenAt,
                interruptedSeconds: ageSeconds,
                statusText: "安全校验失败",
                recentOnlineText: evidenceAt == nil ? "暂无" : "连接中断 \(max(1, ageSeconds)) 秒",
                isOnline: false,
                isSuspended: false
            )
        }

        if monitoringMode == .suspended {
            return ConnectionPresenceSnapshot(
                state: .stale,
                lifecycleState: .offline,
                lastEvidenceAt: evidenceAt,
                lastSeenAt: lastSeenAt,
                interruptedSeconds: ageSeconds,
                statusText: "前台监测已暂停",
                recentOnlineText: evidenceAt == nil ? "暂无" : "连接中断 \(max(1, ageSeconds)) 秒",
                isOnline: false,
                isSuspended: true
            )
        }

        guard let evidenceAt else {
            let resolvedState: ConnectionPresenceState = presenceState == .connecting ? .connecting : (presenceState ?? .unknown)
            return ConnectionPresenceSnapshot(
                state: resolvedState,
                lifecycleState: resolvedState == .connecting ? .connecting : .offline,
                lastEvidenceAt: nil,
                lastSeenAt: lastSeenAt,
                interruptedSeconds: 0,
                statusText: resolvedState == .connecting ? "正在连接" : "已配对但离线",
                recentOnlineText: "暂无",
                isOnline: false,
                isSuspended: false
            )
        }

        let missedCount = missedHeartbeatCount ?? 0
        let resolvedState: ConnectionPresenceState
        if missedCount >= missedHeartbeatLimit || now.timeIntervalSince(evidenceAt) > disconnectedAfter {
            resolvedState = .disconnected
        } else if now.timeIntervalSince(evidenceAt) > staleAfter {
            resolvedState = .interrupted
        } else {
            resolvedState = .online
        }

        switch resolvedState {
        case .online:
            return ConnectionPresenceSnapshot(
                state: .online,
                lifecycleState: .connected,
                lastEvidenceAt: evidenceAt,
                lastSeenAt: lastSeenAt,
                interruptedSeconds: 0,
                statusText: "已连接",
                recentOnlineText: Self.secondsAgoText(ageSeconds),
                isOnline: true,
                isSuspended: false
            )
        case .interrupted, .disconnected:
            let interruptedSeconds = max(1, ageSeconds)
            return ConnectionPresenceSnapshot(
                state: resolvedState,
                lifecycleState: .offline,
                lastEvidenceAt: evidenceAt,
                lastSeenAt: lastSeenAt,
                interruptedSeconds: interruptedSeconds,
                statusText: "连接中断 \(interruptedSeconds) 秒",
                recentOnlineText: "连接中断 \(interruptedSeconds) 秒",
                isOnline: false,
                isSuspended: false
            )
        default:
            return ConnectionPresenceSnapshot(
                state: resolvedState,
                lifecycleState: state,
                lastEvidenceAt: evidenceAt,
                lastSeenAt: lastSeenAt,
                interruptedSeconds: ageSeconds,
                statusText: state == .connecting ? "正在连接" : "已配对但离线",
                recentOnlineText: Self.secondsAgoText(ageSeconds),
                isOnline: false,
                isSuspended: false
            )
        }
    }

    var latestPresenceEvidenceAt: Date? {
        [
            lastSuccessfulHeartbeatAt,
            lastSignedRequestSucceededAt,
            lastSeenAt,
            lastHeartbeatAt
        ]
        .compactMap { $0 }
        .max()
    }

    private static func secondsAgoText(_ seconds: Int) -> String {
        seconds <= 0 ? "刚刚" : "\(seconds) 秒前"
    }
}

enum LocalNetworkSyncControlPlaneState: String, Codable, Equatable {
    case idle
    case syncStartSignalSent
    case syncStartSignalReceived
    case syncStartAcked
    case inventoryExchanging
    case planningTransfers
    case transferJobsCreated
    case transferring
    case pausedDisconnected
    case resuming
    case completed
    case failed
    case cancelled
}

enum LocalNetworkTransferState: String, Codable, Equatable {
    case pending
    case transferring
    case paused
    case pausedDisconnected
    case retryPending
    case resuming
    case verifying
    case complete
    case failed
    case conflict

    var isVisibleInActionArea: Bool {
        switch self {
        case .pending, .transferring, .paused, .pausedDisconnected, .retryPending, .resuming, .verifying, .failed, .conflict:
            return true
        case .complete:
            return false
        }
    }
}

struct LocalNetworkTransferProgress: Codable, Equatable, Identifiable {
    var id: String { objectID }

    var objectID: String
    var objectKind: String
    var state: LocalNetworkTransferState
    var progressFraction: Double?
    var receivedBytes: Int64?
    var totalBytes: Int64?
    var sourceDeviceID: String?
    var statusText: String?

    var isVisibleInActionArea: Bool {
        state.isVisibleInActionArea
    }
}

struct RecordingAudioSignature: Codable, Equatable {
    var sha256: String?
    var size: Int64?

    var normalizedSHA256: String? {
        let value = sha256?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    func matches(_ other: RecordingAudioSignature) -> Bool {
        guard let lhsHash = normalizedSHA256,
              let rhsHash = other.normalizedSHA256,
              let lhsSize = size,
              let rhsSize = other.size else {
            return false
        }
        return lhsHash == rhsHash && lhsSize == rhsSize
    }

    var summary: String {
        "hash=\(normalizedSHA256.map { String($0.prefix(12)) } ?? "missing");size=\(size.map(String.init) ?? "missing")"
    }
}

enum RecordingMetadataSyncState: String, Codable, Equatable {
    case unknown
    case missing
    case metadataOnly
    case synced
    case conflict
    case deleted
}

enum RecordingLocalAudioState: Equatable {
    case unknown
    case missing
    case unreadable(reason: String)
    case available(RecordingAudioSignature)
    case deleted

    var signature: RecordingAudioSignature? {
        if case .available(let signature) = self {
            return signature
        }
        return nil
    }

    var isAvailable: Bool {
        signature != nil
    }

    var summary: String {
        switch self {
        case .unknown:
            return "unknown"
        case .missing:
            return "missing"
        case .unreadable(let reason):
            return "unreadable:\(Self.sanitize(reason))"
        case .available(let signature):
            return "available(\(signature.summary))"
        case .deleted:
            return "deleted"
        }
    }

    private static func sanitize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : String(trimmed.prefix(32))
    }
}

enum RecordingPeerAudioState: Equatable {
    case unknown
    case missing
    case metadataOnly
    case available(RecordingAudioSignature)
    case different(RecordingAudioSignature?)
    case deleted

    var signature: RecordingAudioSignature? {
        switch self {
        case .available(let signature), .different(let signature?):
            return signature
        case .unknown, .missing, .metadataOnly, .different(nil), .deleted:
            return nil
        }
    }

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var summary: String {
        switch self {
        case .unknown:
            return "unknown"
        case .missing:
            return "missing"
        case .metadataOnly:
            return "metadataOnly"
        case .available(let signature):
            return "available(\(signature.summary))"
        case .different(let signature):
            return "different(\(signature?.summary ?? "signature=missing"))"
        case .deleted:
            return "deleted"
        }
    }
}

enum RecordingTransferJobState: Equatable {
    case none
    case queued
    case inFlight
    case finalizing
    case completed
    case failed(reason: String?)
    case retryPending
    case paused

    var summary: String {
        switch self {
        case .none:
            return "none"
        case .queued:
            return "queued"
        case .inFlight:
            return "inFlight"
        case .finalizing:
            return "finalizing"
        case .completed:
            return "completed"
        case .failed(let reason):
            return "failed:\(reason.map { String($0.prefix(32)) } ?? "unknown")"
        case .retryPending:
            return "retryPending"
        case .paused:
            return "paused"
        }
    }
}

enum RecordingUploadLedgerState: Equatable {
    case none
    case queued
    case inFlight
    case finalizing
    case completed(RecordingAudioSignature?)
    case failed(reason: String?)
    case retryPending
    case fatalFailed(reason: String?)

    var summary: String {
        switch self {
        case .none:
            return "none"
        case .queued:
            return "queued"
        case .inFlight:
            return "inFlight"
        case .finalizing:
            return "finalizing"
        case .completed(let signature):
            return "completed(\(signature?.summary ?? "signature=missing"))"
        case .failed(let reason):
            return "failed:\(reason.map { String($0.prefix(32)) } ?? "unknown")"
        case .retryPending:
            return "retryPending"
        case .fatalFailed(let reason):
            return "fatalFailed:\(reason.map { String($0.prefix(32)) } ?? "unknown")"
        }
    }
}

enum RecordingAudioSyncTriggerSource: String, Codable, Equatable {
    case manualUploadButton
    case retryDrainer
    case manualSyncIPhone
    case manualSyncMacHint
    case periodicSync
    case folderViewRefresh
    case recordingListRefresh
    case studyLibraryRefresh
    case appActivationRefresh

    init(syncTrigger: String) {
        let normalized = syncTrigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("event-driven:") && Self.isStatusOnlyEventTrigger(normalized) {
            self = .studyLibraryRefresh
        } else if normalized.hasPrefix("event-driven:") && normalized.contains("appforegroundedwithpendingchanges") {
            self = .appActivationRefresh
        } else if normalized.contains("retry-drainer") || normalized.contains("retrydrainer") {
            self = .retryDrainer
        } else if normalized.contains("manual-sync-requested") || normalized.contains("mac") {
            self = .manualSyncMacHint
        } else if normalized.contains("manual") {
            self = .manualSyncIPhone
        } else if normalized.contains("folder") {
            self = .folderViewRefresh
        } else if normalized.contains("recording-list") || normalized.contains("recordinglist") {
            self = .recordingListRefresh
        } else if normalized.contains("study") {
            self = .studyLibraryRefresh
        } else if normalized.contains("foreground") || normalized.contains("activation") {
            self = .appActivationRefresh
        } else {
            self = .periodicSync
        }
    }

    private static func isStatusOnlyEventTrigger(_ normalized: String) -> Bool {
        let statusReasons = [
            "audiouploadfinalized",
            "macaudioreceivefinalized",
            "transcriptionstatuschanged",
            "notestatuschanged",
            "syncstatusrefreshrequested",
            "retrystatechanged"
        ]
        let dataChangeReasons = [
            "recordingcreated",
            "recordingmetadatachanged",
            "studylibrarymetadatachanged",
            "generatedartifactavailabilitychanged",
            "tombstoneconflictchanged",
            "appforegroundedwithpendingchanges",
            "manualpeersyncrequested"
        ]
        return statusReasons.contains { normalized.contains($0) }
            && !dataChangeReasons.contains { normalized.contains($0) }
    }

    var canCreateUploadJob: Bool {
        switch self {
        case .manualUploadButton, .retryDrainer, .manualSyncIPhone, .manualSyncMacHint, .periodicSync, .appActivationRefresh:
            return true
        case .folderViewRefresh, .recordingListRefresh, .studyLibraryRefresh:
            return false
        }
    }

    var isViewRefreshOnly: Bool {
        switch self {
        case .folderViewRefresh, .recordingListRefresh, .studyLibraryRefresh:
            return true
        case .manualUploadButton, .retryDrainer, .manualSyncIPhone, .manualSyncMacHint, .periodicSync, .appActivationRefresh:
            return false
        }
    }

    var isExplicitSingleRecordingUpload: Bool {
        switch self {
        case .manualUploadButton, .retryDrainer:
            return true
        case .manualSyncIPhone, .manualSyncMacHint, .periodicSync, .folderViewRefresh, .recordingListRefresh, .studyLibraryRefresh, .appActivationRefresh:
            return false
        }
    }
}

enum RecordingAudioUploadDecisionKind: String, Codable, Equatable {
    case upload
    case noOp
    case suppress
    case fail
}

enum RecordingUploadDisplayState: Equatable {
    case hidden
    case waiting
    case retryPending
    case manualRetryAvailable(String?)
    case preparing
    case uploading(progressFraction: Double?)
    case finalizing
    case uploaded
    case conflict(String?)
    case fatalFailed(String?)
    case failed(String?)

    var shouldAnimateTransfer: Bool {
        switch self {
        case .waiting, .retryPending, .preparing, .uploading, .finalizing:
            return true
        case .hidden, .manualRetryAvailable, .uploaded, .conflict, .fatalFailed, .failed:
            return false
        }
    }
}

enum LocalNetworkChecksumCacheEvent: String, Codable, Equatable {
    case hit
    case miss
    case invalidated
}

struct LocalNetworkChecksumCacheResult: Equatable {
    var sha256: String
    var size: Int64
    var modifiedAt: Date
    var computedAt: Date
    var event: LocalNetworkChecksumCacheEvent
}

struct RecordingAudioUploadDecision: Equatable {
    var kind: RecordingAudioUploadDecisionKind
    var reasonCode: String
    var diagnosticStage: String
    var displayState: RecordingUploadDisplayState

    var shouldCreateUploadJob: Bool {
        kind == .upload
    }
}

enum RecordingAudioUploadDecisionEvaluator {
    static func evaluateRecordingAudioUploadDecision(
        localAudioState: RecordingLocalAudioState,
        peerAudioState: RecordingPeerAudioState,
        transferJobState: RecordingTransferJobState,
        ledgerState: RecordingUploadLedgerState,
        triggerSource: RecordingAudioSyncTriggerSource,
        syncRunID: String?,
        objectID: String,
        recordingID: String
    ) -> RecordingAudioUploadDecision {
        _ = syncRunID
        _ = objectID
        _ = recordingID

        if triggerSource.isViewRefreshOnly {
            return decision(.suppress, reason: "view_refresh_only", stage: "uploadDecisionSuppressedViewRefreshOnly", display: .hidden)
        }

        switch localAudioState {
        case .missing, .unknown:
            return decision(.fail, reason: "local_audio_missing", stage: "uploadDecisionFailedLocalAudioMissing", display: .failed("local_audio_missing"))
        case .unreadable:
            return decision(.fail, reason: "local_audio_unreadable", stage: "uploadDecisionFailedLocalAudioMissing", display: .failed("local_audio_unreadable"))
        case .deleted:
            return decision(.fail, reason: "local_audio_deleted", stage: "uploadDecisionFailedLocalAudioMissing", display: .hidden)
        case .available:
            break
        }

        if let localSignature = localAudioState.signature {
            switch peerAudioState {
            case .available(let peerSignature) where localSignature.matches(peerSignature):
                if case .completed = ledgerState {
                    return decision(.suppress, reason: "completed_ledger_peer_matches", stage: "uploadDecisionSuppressedCompletedAndPeerMatches", display: .uploaded)
                }
                return decision(.noOp, reason: "peer_already_has_same_audio", stage: "uploadDecisionNoOpPeerAlreadyHasSameAudio", display: .uploaded)
            default:
                break
            }
        }

        switch transferJobState {
        case .queued:
            return decision(.suppress, reason: "transfer_queued", stage: "uploadDecisionSuppressedQueued", display: .waiting)
        case .inFlight:
            return decision(.suppress, reason: "transfer_in_flight", stage: "uploadDecisionSuppressedInFlight", display: .uploading(progressFraction: nil))
        case .finalizing:
            return decision(.suppress, reason: "transfer_finalizing", stage: "uploadDecisionSuppressedInFlight", display: .finalizing)
        case .retryPending:
            return decision(.suppress, reason: "transfer_retry_pending", stage: "retryPendingDisplayState", display: .retryPending)
        case .none, .completed, .failed, .paused:
            break
        }

        switch ledgerState {
        case .queued:
            return decision(.suppress, reason: "ledger_queued", stage: "uploadDecisionSuppressedQueued", display: .waiting)
        case .inFlight:
            return decision(.suppress, reason: "ledger_in_flight", stage: "uploadDecisionSuppressedInFlight", display: .uploading(progressFraction: nil))
        case .finalizing:
            return decision(.suppress, reason: "ledger_finalizing", stage: "uploadDecisionSuppressedInFlight", display: .finalizing)
        case .retryPending:
            if triggerSource.isExplicitSingleRecordingUpload {
                break
            }
            return decision(.suppress, reason: "ledger_retry_pending", stage: "retryPendingDisplayState", display: .retryPending)
        case .fatalFailed(let reason):
            if let reason, reason.contains("conflict") {
                return decision(.fail, reason: reason, stage: "uploadSuppressedConflict", display: .conflict(reason))
            }
            return decision(.fail, reason: reason ?? "ledger_fatal_failed", stage: "uploadDecisionFatalFailed", display: .fatalFailed(reason))
        case .none, .completed, .failed:
            break
        }

        guard triggerSource.canCreateUploadJob else {
            return decision(.suppress, reason: "trigger_cannot_create_upload", stage: "uploadDecisionSuppressedViewRefreshOnly", display: .hidden)
        }

        switch peerAudioState {
        case .metadataOnly:
            return decision(.upload, reason: "peer_metadata_only", stage: "uploadDecisionUploadBecausePeerMetadataOnly", display: .preparing)
        case .missing:
            return decision(.upload, reason: "peer_missing_audio", stage: "uploadDecisionUploadBecausePeerMissingAudio", display: .preparing)
        case .unknown:
            if triggerSource == .manualUploadButton {
                return decision(.upload, reason: "manual_force_peer_unknown", stage: "manualForcePeerUnknownUpload", display: .preparing)
            }
            if triggerSource == .retryDrainer {
                return decision(.upload, reason: "retry_drainer_peer_unknown", stage: "retryJobEligible", display: .preparing)
            }
            return decision(.suppress, reason: "peer_audio_unknown_deferred", stage: "peerAudioUnknownDeferred", display: .waiting)
        case .available, .different:
            return decision(.fail, reason: "peer_audio_conflict", stage: "uploadSuppressedConflict", display: .conflict("peer_audio_conflict"))
        case .deleted:
            return decision(.upload, reason: "peer_audio_deleted", stage: "uploadDecisionUploadBecausePeerMissingAudio", display: .preparing)
        }
    }

    private static func decision(
        _ kind: RecordingAudioUploadDecisionKind,
        reason: String,
        stage: String,
        display: RecordingUploadDisplayState
    ) -> RecordingAudioUploadDecision {
        RecordingAudioUploadDecision(
            kind: kind,
            reasonCode: reason,
            diagnosticStage: stage,
            displayState: display
        )
    }
}

enum RecordingAudioUploadDecisionDiagnostics {
    static func result(
        recordingID: String,
        objectID: String,
        logicalPathToken: String? = nil,
        triggerSource: RecordingAudioSyncTriggerSource,
        decision: RecordingAudioUploadDecision,
        localAudioState: RecordingLocalAudioState,
        peerAudioState: RecordingPeerAudioState,
        transferJobState: RecordingTransferJobState,
        ledgerState: RecordingUploadLedgerState
    ) -> String {
        [
            "recordingIDPrefix=\(prefix(recordingID))",
            "objectIDPrefix=\(prefix(objectID))",
            "logicalPathTokenPrefix=\(prefix(logicalPathToken))",
            "triggerSource=\(triggerSource.rawValue)",
            "decision=\(decision.kind.rawValue)",
            "reasonCode=\(decision.reasonCode)",
            "localAudio=\(localAudioState.summary)",
            "peerAudio=\(peerAudioState.summary)",
            "transferJobState=\(transferJobState.summary)",
            "ledgerState=\(ledgerState.summary)"
        ].joined(separator: ",")
    }

    private static func prefix(_ value: String?) -> String {
        guard let value else {
            return "missing"
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "missing" : String(trimmed.prefix(12))
    }
}

nonisolated struct RecordingUploadTransferProgressMapper {
    nonisolated static func progress(
        for recording: RecordingMetadata,
        status explicitStatus: RecordingUploadStatus? = nil
    ) -> LocalNetworkTransferProgress? {
        let status = explicitStatus ?? RecordingUploadStatus(rawMetadataValue: recording.uploadStatus)
        let hasTransferProjection = recording.uploadPhase != nil
            || recording.uploadProgressFraction != nil
            || recording.uploadProgressConfirmedBytes != nil
            || recording.uploadProgressTotalBytes != nil
            || recording.uploadProgressDescription != nil
        guard status == .uploading || (status == .failed && hasTransferProjection) else {
            return nil
        }

        let state = state(for: recording.uploadPhase, uploadStatus: status)
        let totalBytes = recording.uploadProgressTotalBytes ?? (recording.fileSize > 0 ? recording.fileSize : nil)
        let fraction = progressFraction(
            explicitFraction: recording.uploadProgressFraction,
            confirmedBytes: recording.uploadProgressConfirmedBytes,
            totalBytes: totalBytes
        )

        return LocalNetworkTransferProgress(
            objectID: "recordingAudio:\(recording.id)",
            objectKind: LocalNetworkSyncObjectKind.recordingAudio.rawValue,
            state: state,
            progressFraction: fraction,
            receivedBytes: recording.uploadProgressConfirmedBytes,
            totalBytes: totalBytes,
            sourceDeviceID: nil,
            statusText: statusText(
                description: recording.uploadProgressDescription,
                phase: recording.uploadPhase,
                state: state,
                fraction: fraction
            )
        )
    }

    private static func state(
        for phase: String?,
        uploadStatus: RecordingUploadStatus?
    ) -> LocalNetworkTransferState {
        let normalized = phase?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if uploadStatus == .failed {
            if normalized.contains("conflict") {
                return .conflict
            }
            return .failed
        }
        if normalized.contains("fatalfailed") || normalized.contains("failed") {
            return .failed
        }
        if normalized.contains("retry") {
            return .retryPending
        }
        if normalized.contains("paused") {
            return .paused
        }
        if normalized.contains("resuming") {
            return .resuming
        }
        if normalized.contains("finalizing") {
            return .verifying
        }
        if normalized.contains("completed") {
            return .complete
        }
        if normalized.contains("preparing") || normalized.contains("starting") || normalized.contains("metadata") {
            return .pending
        }
        return .transferring
    }

    private static func progressFraction(
        explicitFraction: Double?,
        confirmedBytes: Int64?,
        totalBytes: Int64?
    ) -> Double? {
        if let explicitFraction {
            return clamped(explicitFraction)
        }

        guard let confirmedBytes,
              let totalBytes,
              totalBytes > 0 else {
            return nil
        }

        return clamped(Double(confirmedBytes) / Double(totalBytes))
    }

    private static func statusText(
        description: String?,
        phase: String?,
        state: LocalNetworkTransferState,
        fraction: Double?
    ) -> String {
        let normalizedDescription = description?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalizedDescription,
           !normalizedDescription.isEmpty,
           normalizedDescription != "上传完成" {
            return normalizedDescription
        }

        switch state {
        case .pending:
            return "准备上传"
        case .paused, .pausedDisconnected, .retryPending:
            return "等待重试"
        case .resuming:
            return percentText(prefix: "续传中", fraction: fraction)
        case .verifying:
            return "正在完成上传"
        case .failed, .conflict:
            return "上传失败"
        case .complete:
            return "上传完成"
        case .transferring:
            let normalizedPhase = phase?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            if normalizedPhase.contains("preparing") {
                return "准备上传"
            }
            return percentText(prefix: "上传中", fraction: fraction)
        }
    }

    private static func percentText(prefix: String, fraction: Double?) -> String {
        guard let fraction else {
            return prefix
        }

        let percent = Int((clamped(fraction) * 100).rounded())
        return "\(prefix) \(min(max(percent, 0), 100))%"
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

extension StudyItemMetadata {
    nonisolated var localNetworkTransferProgress: LocalNetworkTransferProgress? {
        guard let stateRaw = customProperties[Self.transferStateKey],
              let state = LocalNetworkTransferState(rawValue: stateRaw),
              let objectID = customProperties[Self.transferObjectIDKey],
              let objectKind = customProperties[Self.transferObjectKindKey] else {
            return nil
        }

        return LocalNetworkTransferProgress(
            objectID: objectID,
            objectKind: objectKind,
            state: state,
            progressFraction: customProperties[Self.transferProgressKey].flatMap(Double.init),
            receivedBytes: customProperties[Self.transferReceivedBytesKey].flatMap(Int64.init),
            totalBytes: customProperties[Self.transferTotalBytesKey].flatMap(Int64.init),
            sourceDeviceID: customProperties[Self.transferSourceDeviceIDKey],
            statusText: customProperties[Self.transferStatusTextKey]
        )
    }

    nonisolated func withLocalNetworkTransferProgress(_ progress: LocalNetworkTransferProgress?) -> StudyItemMetadata {
        var copy = self
        Self.transferKeys.forEach { copy.customProperties.removeValue(forKey: $0) }

        guard let progress, progress.state != .complete else {
            return copy
        }

        copy.customProperties[Self.transferStateKey] = progress.state.rawValue
        copy.customProperties[Self.transferObjectIDKey] = progress.objectID
        copy.customProperties[Self.transferObjectKindKey] = progress.objectKind
        if let progressFraction = progress.progressFraction {
            copy.customProperties[Self.transferProgressKey] = String(progressFraction)
        }
        if let receivedBytes = progress.receivedBytes {
            copy.customProperties[Self.transferReceivedBytesKey] = String(receivedBytes)
        }
        if let totalBytes = progress.totalBytes {
            copy.customProperties[Self.transferTotalBytesKey] = String(totalBytes)
        }
        if let sourceDeviceID = progress.sourceDeviceID {
            copy.customProperties[Self.transferSourceDeviceIDKey] = sourceDeviceID
        }
        if let statusText = progress.statusText {
            copy.customProperties[Self.transferStatusTextKey] = statusText
        }
        return copy
    }

    nonisolated func withRecordingUploadTransferProgress(_ recording: RecordingMetadata) -> StudyItemMetadata {
        if let progress = Self.recordingUploadTransferProgress(for: recording) {
            return withLocalNetworkTransferProgress(progress)
        }

        guard localNetworkTransferProgress?.objectKind == LocalNetworkSyncObjectKind.recordingAudio.rawValue else {
            return self
        }

        return withLocalNetworkTransferProgress(nil)
    }

    nonisolated static func recordingUploadTransferProgress(
        for recording: RecordingMetadata,
        status: RecordingUploadStatus? = nil
    ) -> LocalNetworkTransferProgress? {
        RecordingUploadTransferProgressMapper.progress(for: recording, status: status)
    }

    nonisolated private static var transferKeys: [String] {
        [
            transferStateKey,
            transferObjectIDKey,
            transferObjectKindKey,
            transferProgressKey,
            transferReceivedBytesKey,
            transferTotalBytesKey,
            transferSourceDeviceIDKey,
            transferStatusTextKey
        ]
    }

    nonisolated private static let transferStateKey = "localNetworkTransferState"
    nonisolated private static let transferObjectIDKey = "localNetworkTransferObjectID"
    nonisolated private static let transferObjectKindKey = "localNetworkTransferObjectKind"
    nonisolated private static let transferProgressKey = "localNetworkTransferProgressFraction"
    nonisolated private static let transferReceivedBytesKey = "localNetworkTransferReceivedBytes"
    nonisolated private static let transferTotalBytesKey = "localNetworkTransferTotalBytes"
    nonisolated private static let transferSourceDeviceIDKey = "localNetworkTransferSourceDeviceID"
    nonisolated private static let transferStatusTextKey = "localNetworkTransferStatusText"
}

struct StudyLibrarySyncState: Codable, Equatable {
    var deviceID: String
    var lastPulledAt: Date?
    var lastPushedAt: Date?
    var lastSuccessfulSyncAt: Date?
    var lastRemoteManifestHash: String?
    var lastKnownRemoteCommitID: String?
    var pendingLocalChanges: Int
    var pendingUploads: Int
    var failedChanges: Int
    var lastError: String?
    var activeSyncRunID: String?
    var syncControlPlaneState: LocalNetworkSyncControlPlaneState?
    var syncControlPlaneUpdatedAt: Date?

    init(
        deviceID: String = "",
        lastPulledAt: Date? = nil,
        lastPushedAt: Date? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        lastRemoteManifestHash: String? = nil,
        lastKnownRemoteCommitID: String? = nil,
        pendingLocalChanges: Int = 0,
        pendingUploads: Int = 0,
        failedChanges: Int = 0,
        lastError: String? = nil,
        activeSyncRunID: String? = nil,
        syncControlPlaneState: LocalNetworkSyncControlPlaneState? = nil,
        syncControlPlaneUpdatedAt: Date? = nil
    ) {
        self.deviceID = deviceID
        self.lastPulledAt = lastPulledAt
        self.lastPushedAt = lastPushedAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastRemoteManifestHash = lastRemoteManifestHash
        self.lastKnownRemoteCommitID = lastKnownRemoteCommitID
        self.pendingLocalChanges = pendingLocalChanges
        self.pendingUploads = pendingUploads
        self.failedChanges = failedChanges
        self.lastError = lastError
        self.activeSyncRunID = activeSyncRunID
        self.syncControlPlaneState = syncControlPlaneState
        self.syncControlPlaneUpdatedAt = syncControlPlaneUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case lastPulledAt
        case lastPushedAt
        case lastSuccessfulSyncAt
        case lastRemoteManifestHash
        case lastKnownRemoteCommitID
        case pendingLocalChanges
        case pendingUploads
        case failedChanges
        case lastError
        case activeSyncRunID
        case syncControlPlaneState
        case syncControlPlaneUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
        lastPulledAt = try container.decodeIfPresent(Date.self, forKey: .lastPulledAt)
        lastPushedAt = try container.decodeIfPresent(Date.self, forKey: .lastPushedAt)
        lastSuccessfulSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSyncAt)
        lastRemoteManifestHash = try container.decodeIfPresent(String.self, forKey: .lastRemoteManifestHash)
        lastKnownRemoteCommitID = try container.decodeIfPresent(String.self, forKey: .lastKnownRemoteCommitID)
        pendingLocalChanges = try container.decodeIfPresent(Int.self, forKey: .pendingLocalChanges) ?? 0
        pendingUploads = try container.decodeIfPresent(Int.self, forKey: .pendingUploads) ?? 0
        failedChanges = try container.decodeIfPresent(Int.self, forKey: .failedChanges) ?? 0
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        activeSyncRunID = try container.decodeIfPresent(String.self, forKey: .activeSyncRunID)
        syncControlPlaneState = try container.decodeIfPresent(LocalNetworkSyncControlPlaneState.self, forKey: .syncControlPlaneState)
        syncControlPlaneUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .syncControlPlaneUpdatedAt)
    }
}

enum StudyLibrarySyncEntityKind: String, Codable, Equatable {
    case item
    case folder
}

enum StudyLibrarySyncOperation: String, Codable, Equatable {
    case upsert
    case delete
    case trash
    case restore
    case deleteMetadataOnly
}

nonisolated enum PendingRecordingUploadStatus: String, Codable, Equatable {
    case pending
    case uploading
    case uploaded
    case failed
}

nonisolated struct PendingRecordingUpload: Codable, Equatable, Identifiable {
    var id: String
    var itemID: StudyItemID
    var recordingID: String
    var localAudioRelativePath: String
    var targetDeviceID: String
    var status: PendingRecordingUploadStatus
    var createdAt: Date
    var updatedAt: Date
    var lastAttemptAt: Date?
    var retryCount: Int
    var lastError: String?

    init(
        id: String? = nil,
        itemID: StudyItemID,
        recordingID: String,
        localAudioRelativePath: String,
        targetDeviceID: String,
        status: PendingRecordingUploadStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id ?? "\(itemID):\(recordingID)"
        self.itemID = itemID
        self.recordingID = recordingID
        self.localAudioRelativePath = localAudioRelativePath
        self.targetDeviceID = targetDeviceID
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAttemptAt = lastAttemptAt
        self.retryCount = retryCount
        self.lastError = lastError
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case itemID
        case recordingID
        case localAudioRelativePath
        case targetDeviceID
        case status
        case createdAt
        case updatedAt
        case lastAttemptAt
        case retryCount
        case lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try container.decodeIfPresent(StudyItemID.self, forKey: .itemID) ?? ""
        recordingID = try container.decodeIfPresent(String.self, forKey: .recordingID) ?? itemID
        localAudioRelativePath = try container.decodeIfPresent(String.self, forKey: .localAudioRelativePath) ?? ""
        targetDeviceID = try container.decodeIfPresent(String.self, forKey: .targetDeviceID) ?? ""
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "\(itemID):\(recordingID)"
        status = try container.decodeIfPresent(PendingRecordingUploadStatus.self, forKey: .status) ?? .pending
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}

nonisolated struct StudyLibrarySyncTombstone: Codable, Equatable, Identifiable {
    var id: String
    var entityKind: StudyLibrarySyncEntityKind
    var entityID: String
    var operation: StudyLibrarySyncOperation
    var updatedAt: Date
    var modifiedByDeviceID: String?
}

struct StudyLibrarySyncChange: Codable, Equatable, Identifiable {
    var id: String
    var entityKind: StudyLibrarySyncEntityKind
    var entityID: String
    var operation: StudyLibrarySyncOperation
    var updatedAt: Date
    var modifiedByDeviceID: String?
    var itemPayload: StudyItemMetadata?
    var folderPayload: StudyFolderMetadata?
}

nonisolated struct StudyLibrarySyncManifest: Codable, Equatable {
    var deviceID: String
    var generatedAt: Date
    var libraryVersion: Int
    var items: [StudyItemMetadata]
    var folders: [StudyFolderMetadata]
    var tombstones: [StudyLibrarySyncTombstone]
    var pendingUploads: [PendingRecordingUpload]
    var recordings: [LocalNetworkSyncRecordingEntry]
    var baseCommitID: String?
    var commitID: String?
    var localManifestHash: String?
    var checksum: String

    nonisolated static func make(
        deviceID: String,
        generatedAt: Date = Date(),
        libraryVersion: Int = 1,
        items: [StudyItemMetadata],
        folders: [StudyFolderMetadata],
        tombstones: [StudyLibrarySyncTombstone] = [],
        pendingUploads: [PendingRecordingUpload] = [],
        recordings: [LocalNetworkSyncRecordingEntry] = [],
        baseCommitID: String? = nil,
        commitID: String? = nil,
        localManifestHash: String? = nil
    ) -> StudyLibrarySyncManifest {
        var manifest = StudyLibrarySyncManifest(
            deviceID: deviceID,
            generatedAt: generatedAt,
            libraryVersion: libraryVersion,
            items: items.sorted { $0.itemID.localizedStandardCompare($1.itemID) == .orderedAscending },
            folders: folders.sorted { $0.folderID.localizedStandardCompare($1.folderID) == .orderedAscending },
            tombstones: tombstones.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending },
            pendingUploads: pendingUploads.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending },
            recordings: recordings.sorted { $0.recordingID.localizedStandardCompare($1.recordingID) == .orderedAscending },
            baseCommitID: baseCommitID,
            commitID: commitID,
            localManifestHash: localManifestHash,
            checksum: ""
        )
        manifest.checksum = manifest.computedChecksum()
        return manifest
    }

    nonisolated func computedChecksum() -> String {
        let payload = StudyLibrarySyncChecksumPayload(
            deviceID: deviceID,
            generatedAt: generatedAt,
            libraryVersion: libraryVersion,
            items: items,
            folders: folders,
            tombstones: tombstones,
            pendingUploads: pendingUploads,
            recordings: recordings
        )
        let data = (try? Self.checksumEncoder.encode(payload)) ?? Data()
        return Data(SHA256.hash(data: data)).hexString
    }

    var hasValidChecksum: Bool {
        checksum == computedChecksum() || checksum == legacyComputedChecksum()
    }

    var summaryText: String {
        let uploadText = pendingUploads.isEmpty ? nil : "\(pendingUploads.count) 个待上传"
        let recordingText = recordings.isEmpty ? nil : "\(recordings.count) 个录音存在性"
        return (["\(items.count) 项", "\(folders.count) 个文件夹"] + [uploadText, recordingText].compactMap { $0 })
            .joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case generatedAt
        case libraryVersion
        case items
        case folders
        case tombstones
        case pendingUploads
        case recordings
        case baseCommitID
        case commitID
        case localManifestHash
        case checksum
    }

    init(
        deviceID: String,
        generatedAt: Date,
        libraryVersion: Int,
        items: [StudyItemMetadata],
        folders: [StudyFolderMetadata],
        tombstones: [StudyLibrarySyncTombstone],
        pendingUploads: [PendingRecordingUpload],
        recordings: [LocalNetworkSyncRecordingEntry] = [],
        baseCommitID: String? = nil,
        commitID: String? = nil,
        localManifestHash: String? = nil,
        checksum: String
    ) {
        self.deviceID = deviceID
        self.generatedAt = generatedAt
        self.libraryVersion = libraryVersion
        self.items = items
        self.folders = folders
        self.tombstones = tombstones
        self.pendingUploads = pendingUploads
        self.recordings = recordings
        self.baseCommitID = baseCommitID
        self.commitID = commitID
        self.localManifestHash = localManifestHash
        self.checksum = checksum
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        libraryVersion = try container.decodeIfPresent(Int.self, forKey: .libraryVersion) ?? 1
        items = try container.decodeIfPresent([StudyItemMetadata].self, forKey: .items) ?? []
        folders = try container.decodeIfPresent([StudyFolderMetadata].self, forKey: .folders) ?? []
        tombstones = try container.decodeIfPresent([StudyLibrarySyncTombstone].self, forKey: .tombstones) ?? []
        pendingUploads = try container.decodeIfPresent([PendingRecordingUpload].self, forKey: .pendingUploads) ?? []
        recordings = try container.decodeIfPresent([LocalNetworkSyncRecordingEntry].self, forKey: .recordings) ?? []
        baseCommitID = try container.decodeIfPresent(String.self, forKey: .baseCommitID)
        commitID = try container.decodeIfPresent(String.self, forKey: .commitID)
        localManifestHash = try container.decodeIfPresent(String.self, forKey: .localManifestHash)
        checksum = try container.decodeIfPresent(String.self, forKey: .checksum) ?? ""
    }

    private static let checksumEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private func legacyComputedChecksum() -> String {
        let payload = StudyLibrarySyncLegacyChecksumPayload(
            deviceID: deviceID,
            generatedAt: generatedAt,
            libraryVersion: libraryVersion,
            items: items,
            folders: folders,
            tombstones: tombstones
        )
        let data = (try? Self.checksumEncoder.encode(payload)) ?? Data()
        return Data(SHA256.hash(data: data)).hexString
    }
}

private nonisolated struct StudyLibrarySyncChecksumPayload: Encodable {
    var deviceID: String
    var generatedAt: Date
    var libraryVersion: Int
    var items: [StudyItemMetadata]
    var folders: [StudyFolderMetadata]
    var tombstones: [StudyLibrarySyncTombstone]
    var pendingUploads: [PendingRecordingUpload]
    var recordings: [LocalNetworkSyncRecordingEntry]
}

private nonisolated struct StudyLibrarySyncLegacyChecksumPayload: Encodable {
    var deviceID: String
    var generatedAt: Date
    var libraryVersion: Int
    var items: [StudyItemMetadata]
    var folders: [StudyFolderMetadata]
    var tombstones: [StudyLibrarySyncTombstone]
}

struct StudyLibrarySyncApplyResult: Codable, Equatable {
    var appliedItemCount: Int = 0
    var appliedFolderCount: Int = 0
    var tombstoneCount: Int = 0
    var conflictCount: Int = 0
    var skippedOlderCount: Int = 0
    var failedChanges: Int = 0

    var summaryText: String {
        if failedChanges > 0 {
            return "同步失败 \(failedChanges) 项"
        }
        if appliedItemCount == 0, appliedFolderCount == 0, tombstoneCount == 0, conflictCount == 0 {
            return "已是最新"
        }

        var parts: [String] = []
        if appliedItemCount > 0 {
            parts.append("\(appliedItemCount) 项")
        }
        if appliedFolderCount > 0 {
            parts.append("\(appliedFolderCount) 个文件夹")
        }
        if tombstoneCount > 0 {
            parts.append("\(tombstoneCount) 个废纸篓状态")
        }
        if conflictCount > 0 {
            parts.append("\(conflictCount) 个冲突已保留")
        }
        return parts.joined(separator: " · ")
    }
}

struct StudyLibrarySyncStatusSummary: Codable, Equatable {
    var lastSyncAt: Date?
    var statusText: String?
    var pendingLocalChanges: Int
    var pendingUploads: Int

    init(lastSyncAt: Date?, statusText: String?, pendingLocalChanges: Int, pendingUploads: Int = 0) {
        self.lastSyncAt = lastSyncAt
        self.statusText = statusText
        self.pendingLocalChanges = pendingLocalChanges
        self.pendingUploads = pendingUploads
    }

    private enum CodingKeys: String, CodingKey {
        case lastSyncAt
        case statusText
        case pendingLocalChanges
        case pendingUploads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText)
        pendingLocalChanges = try container.decodeIfPresent(Int.self, forKey: .pendingLocalChanges) ?? 0
        pendingUploads = try container.decodeIfPresent(Int.self, forKey: .pendingUploads) ?? 0
    }
}

struct DeviceStatusRequest: Codable, Equatable {
    var displayName: String
    var clientState: String
    var generatedAt: Date
    var syncSummary: StudyLibrarySyncStatusSummary?
    var statusExchangeEnvelope: CanonicalStatusExchangeEnvelope? = nil
}

struct DeviceStatusResponse: Codable, Equatable {
    var ok: Bool
    var status: DeviceConnectionStatus?
    var syncState: StudyLibrarySyncState?
    var syncRequested: Bool
    var syncStartSignal: LocalNetworkSyncStartSignal?
    var statusExchangeEnvelope: CanonicalStatusExchangeEnvelope?
    var error: String?

    init(
        ok: Bool,
        status: DeviceConnectionStatus?,
        syncState: StudyLibrarySyncState?,
        syncRequested: Bool = false,
        syncStartSignal: LocalNetworkSyncStartSignal? = nil,
        statusExchangeEnvelope: CanonicalStatusExchangeEnvelope? = nil,
        error: String?
    ) {
        self.ok = ok
        self.status = status
        self.syncState = syncState
        self.syncRequested = syncRequested
        self.syncStartSignal = syncStartSignal
        self.statusExchangeEnvelope = statusExchangeEnvelope
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case status
        case syncState
        case syncRequested
        case syncStartSignal
        case statusExchangeEnvelope
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        status = try container.decodeIfPresent(DeviceConnectionStatus.self, forKey: .status)
        syncState = try container.decodeIfPresent(StudyLibrarySyncState.self, forKey: .syncState)
        syncRequested = (try? container.decode(Bool.self, forKey: .syncRequested)) ?? false
        syncStartSignal = try container.decodeIfPresent(LocalNetworkSyncStartSignal.self, forKey: .syncStartSignal)
        statusExchangeEnvelope = try container.decodeIfPresent(CanonicalStatusExchangeEnvelope.self, forKey: .statusExchangeEnvelope)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

struct ConnectionHeartbeatRequest: Codable, Equatable {
    var deviceID: String
    var deviceName: String
    var platform: LocalNetworkSyncPlatform
    var appInstanceID: String?
    var sequenceNumber: UInt64
    var sentAt: Date
    var lastKnownPeerStatusRevision: Int?
    var statusExchangeEnvelope: CanonicalStatusExchangeEnvelope? = nil
    var syncRunStatus: LocalNetworkSyncRunStatus? = nil
}

struct LocalNetworkSyncRunStatus: Codable, Equatable {
    var syncRunID: String
    var state: LocalNetworkSyncControlPlaneState
    var updatedAt: Date
    var errorCode: String?
}

struct ConnectionHeartbeatResponse: Codable, Equatable {
    var ok: Bool
    var disposition: String
    var peerDeviceID: String
    var serverTime: Date
    var receivedSequenceNumber: UInt64
    var connectionStatusRevision: Int
    var minimumSuggestedInterval: TimeInterval?
    var syncRequested: Bool?
    var syncStartSignal: LocalNetworkSyncStartSignal? = nil
    var statusExchangeEnvelope: CanonicalStatusExchangeEnvelope? = nil
    var status: DeviceConnectionStatus?
    var error: String?
}

struct LocalNetworkSyncStartSignal: Codable, Equatable {
    var syncRunID: String
    var initiatorDeviceID: String
    var initiatorPlatform: LocalNetworkSyncPlatform
    var requestedAt: Date
    var reason: String
}

struct LocalNetworkSyncStartRequest: Codable, Equatable {
    var syncRunID: String
    var deviceID: String
    var platform: LocalNetworkSyncPlatform
    var requestedAt: Date
    var reason: String
}

struct LocalNetworkSyncStartResponse: Codable, Equatable {
    var ok: Bool
    var syncRunID: String?
    var peerDeviceID: String?
    var ackAt: Date?
    var disposition: String?
    var error: String?
}

struct LocalNetworkSyncStartAckRequest: Codable, Equatable {
    var syncRunID: String
    var deviceID: String
    var platform: LocalNetworkSyncPlatform
    var acknowledgedAt: Date
    var disposition: String
}

struct LocalNetworkSyncStartAckResponse: Codable, Equatable {
    var ok: Bool
    var syncRunID: String?
    var peerDeviceID: String?
    var ackReceivedAt: Date?
    var error: String?
}

struct StudyLibrarySyncManifestRequest: Codable, Equatable {
    var manifest: StudyLibrarySyncManifest
    var syncRunID: String? = nil
}

struct StudyLibrarySyncManifestResponse: Codable, Equatable {
    var ok: Bool
    var manifest: StudyLibrarySyncManifest?
    var syncState: StudyLibrarySyncState?
    var deviceStatus: DeviceConnectionStatus?
    var applyResult: StudyLibrarySyncApplyResult?
    var baseCommitID: String?
    var newCommitID: String?
    var remoteChanges: [StudyLibrarySyncChange]?
    var rejectedChanges: [StudyLibrarySyncChange]?
    var error: String?
}

extension StudyLibrarySyncManifest {
    var changesApproximation: [StudyLibrarySyncChange] {
        let itemChanges = items.map { item in
            StudyLibrarySyncChange(
                id: "item:\(item.itemID)",
                entityKind: .item,
                entityID: item.itemID,
                operation: item.isTrashed ? .trash : .upsert,
                updatedAt: item.updatedAt,
                modifiedByDeviceID: item.modifiedByDeviceID ?? deviceID,
                itemPayload: item,
                folderPayload: nil
            )
        }
        let folderChanges = folders.map { folder in
            StudyLibrarySyncChange(
                id: "folder:\(folder.folderID)",
                entityKind: .folder,
                entityID: folder.folderID,
                operation: folder.isTrashed ? .trash : .upsert,
                updatedAt: folder.updatedAt,
                modifiedByDeviceID: folder.modifiedByDeviceID ?? deviceID,
                itemPayload: nil,
                folderPayload: folder
            )
        }
        let tombstoneChanges = tombstones.map { tombstone in
            StudyLibrarySyncChange(
                id: tombstone.id,
                entityKind: tombstone.entityKind,
                entityID: tombstone.entityID,
                operation: tombstone.operation,
                updatedAt: tombstone.updatedAt,
                modifiedByDeviceID: tombstone.modifiedByDeviceID ?? deviceID,
                itemPayload: nil,
                folderPayload: nil
            )
        }
        return itemChanges + folderChanges + tombstoneChanges
    }
}

extension StudyItemMetadata {
    nonisolated func syncSanitized(modifiedByDeviceID fallbackDeviceID: String? = nil) -> StudyItemMetadata {
        var copy = self
        copy.modifiedByDeviceID = copy.modifiedByDeviceID ?? fallbackDeviceID
        copy.customProperties = StudyLibrarySyncSanitizer.filteredCustomProperties(customProperties)
        return copy
    }
}

extension StudyFolderMetadata {
    nonisolated func syncSanitized(modifiedByDeviceID fallbackDeviceID: String? = nil) -> StudyFolderMetadata {
        var copy = self
        copy.modifiedByDeviceID = copy.modifiedByDeviceID ?? fallbackDeviceID
        copy.customProperties = StudyLibrarySyncSanitizer.filteredCustomProperties(customProperties)
        copy.itemIDs = StudyItemMetadata.uniqueIDs(itemIDs)
        copy.childFolderIDs = StudyItemMetadata.uniqueIDs(childFolderIDs)
        return copy
    }
}

nonisolated enum StudyLibrarySyncSanitizer {
    nonisolated static func filteredCustomProperties(_ properties: [String: String]) -> [String: String] {
        properties.filter { key, _ in
            let normalized = key.lowercased()
            return !normalized.contains("apikey")
                && !normalized.contains("api_key")
                && !normalized.contains("secret")
                && !normalized.contains("hmac")
                && !normalized.contains("pairing")
                && !normalized.contains("rawresponse")
                && !normalized.contains("raw_response")
                && !normalized.contains("providerresponse")
                && !normalized.contains("provider_response")
                && !normalized.contains("fulltranscript")
                && !normalized.contains("full_transcript")
                && !normalized.contains("fullnote")
                && !normalized.contains("full_note")
                && !normalized.contains("prompt")
                && !normalized.contains("debug")
                && !normalized.contains("rawjson")
                && !normalized.contains("raw_json")
                && !normalized.contains("localnetworktransfer")
                && normalized != "syncedmetadataonly"
                && normalized != "notesummarypreview"
                && normalized != "notekeypointspreview"
        }
    }
}

enum LocalNetworkSyncPlatform: String, Codable, Equatable, Sendable {
    case iPhone
    case Mac
}

enum LocalNetworkSyncArtifactKind: String, Codable, Equatable, Sendable {
    case metadataJSON
    case receiveJSON
    case transcriptMarkdown
    case transcriptJSON
    case noteMarkdown
    case noteJSON
    case summaryMarkdown
    case summaryJSON
    case audio

    var isAutoDownloadAllowed: Bool {
        switch self {
        case .metadataJSON, .receiveJSON, .transcriptMarkdown, .transcriptJSON, .noteMarkdown, .noteJSON, .summaryMarkdown, .summaryJSON:
            return true
        case .audio:
            return false
        }
    }
}

enum LocalNetworkSyncArtifactAvailability: String, Codable, Equatable, Sendable {
    case local
    case availableOnPeer
    case missing
    case transferring
    case complete
}

enum LocalNetworkSyncObjectKind: String, Codable, Equatable, Sendable {
    case recordingAudio
    case recordingMetadata
    case receiveRecord
    case transcriptMarkdown
    case transcriptJSON
    case noteMarkdown
    case noteJSON
    case summaryMarkdown
    case summaryJSON
    case studyItem
    case studyFolder
}

struct LocalNetworkSyncObjectEntry: Codable, Equatable, Identifiable {
    var id: String { objectID }

    var objectID: String
    var objectKind: LocalNetworkSyncObjectKind
    var ownerID: String?
    var displayTitle: String?
    var fileName: String?
    var logicalName: String?
    var sha256: String?
    var size: Int64?
    var updatedAt: Date
    var deleted: Bool
    var tombstone: Bool?
    var sourceDeviceID: String?
    var logicalPathToken: String?
    var availability: LocalNetworkSyncArtifactAvailability
    var transferState: LocalNetworkTransferState?
    var transferProgress: Double?
    var conflictStatus: String?
    var autoDownloadAllowed: Bool?
}

struct LocalNetworkSyncInventory: Codable, Equatable {
    static let appSchemaVersion = 1

    var schemaVersion: Int
    var sourceDeviceID: String
    var sourcePlatform: LocalNetworkSyncPlatform
    var generatedAt: Date
    var inventoryRevision: String
    var lastKnownPeerRevision: String?
    var device: LocalNetworkSyncDeviceSection
    var recordings: [LocalNetworkSyncRecordingEntry]
    var folders: [LocalNetworkSyncFolderEntry]
    var studyItems: [LocalNetworkSyncStudyItemEntry]
    var artifacts: [LocalNetworkSyncArtifactEntry]
    var objects: [LocalNetworkSyncObjectEntry]
    var studyManifest: StudyLibrarySyncManifest?
    var canonicalManifest: CanonicalManifest?

    var inventoryHash: String {
        let payload = LocalNetworkSyncInventoryChecksumPayload(
            schemaVersion: schemaVersion,
            sourceDeviceID: sourceDeviceID,
            sourcePlatform: sourcePlatform,
            generatedAt: generatedAt,
            inventoryRevision: inventoryRevision,
            lastKnownPeerRevision: lastKnownPeerRevision,
            device: device,
            recordings: recordings,
            folders: folders,
            studyItems: studyItems,
            artifacts: artifacts,
            objects: objects,
            canonicalManifest: canonicalManifest
        )
        let data = (try? Self.encoder.encode(payload)) ?? Data()
        return Data(SHA256.hash(data: data)).hexString
    }

    static func make(
        device: LocalNetworkSyncDeviceSection,
        recordings: [LocalNetworkSyncRecordingEntry] = [],
        folders: [LocalNetworkSyncFolderEntry] = [],
        studyItems: [LocalNetworkSyncStudyItemEntry] = [],
        artifacts: [LocalNetworkSyncArtifactEntry] = [],
        objects: [LocalNetworkSyncObjectEntry] = [],
        studyManifest: StudyLibrarySyncManifest? = nil,
        canonicalManifest: CanonicalManifest? = nil
    ) -> LocalNetworkSyncInventory {
        let inventoryRevision = LocalNetworkSyncMetadataHash.hash(device)
        let sortedRecordings = recordings.sorted { $0.recordingID.localizedStandardCompare($1.recordingID) == .orderedAscending }
        let sortedFolders = folders.sorted { $0.folderID.localizedStandardCompare($1.folderID) == .orderedAscending }
        let sortedStudyItems = studyItems.sorted { $0.itemID.localizedStandardCompare($1.itemID) == .orderedAscending }
        let sortedArtifacts = artifacts.sorted { $0.artifactID.localizedStandardCompare($1.artifactID) == .orderedAscending }
        let sortedObjects = (objects.isEmpty
            ? makeObjectEntries(recordings: sortedRecordings, folders: sortedFolders, studyItems: sortedStudyItems, artifacts: sortedArtifacts)
            : objects
        ).sorted { $0.objectID.localizedStandardCompare($1.objectID) == .orderedAscending }
        return LocalNetworkSyncInventory(
            schemaVersion: appSchemaVersion,
            sourceDeviceID: device.deviceID,
            sourcePlatform: device.platform,
            generatedAt: device.generatedAt,
            inventoryRevision: inventoryRevision,
            lastKnownPeerRevision: device.lastKnownPeerRevision,
            device: device,
            recordings: sortedRecordings,
            folders: sortedFolders,
            studyItems: sortedStudyItems,
            artifacts: sortedArtifacts,
            objects: sortedObjects,
            studyManifest: studyManifest,
            canonicalManifest: canonicalManifest
        )
    }

    init(
        schemaVersion: Int,
        sourceDeviceID: String,
        sourcePlatform: LocalNetworkSyncPlatform,
        generatedAt: Date,
        inventoryRevision: String,
        lastKnownPeerRevision: String?,
        device: LocalNetworkSyncDeviceSection,
        recordings: [LocalNetworkSyncRecordingEntry],
        folders: [LocalNetworkSyncFolderEntry],
        studyItems: [LocalNetworkSyncStudyItemEntry],
        artifacts: [LocalNetworkSyncArtifactEntry],
        objects: [LocalNetworkSyncObjectEntry],
        studyManifest: StudyLibrarySyncManifest?,
        canonicalManifest: CanonicalManifest?
    ) {
        self.schemaVersion = schemaVersion
        self.sourceDeviceID = sourceDeviceID
        self.sourcePlatform = sourcePlatform
        self.generatedAt = generatedAt
        self.inventoryRevision = inventoryRevision
        self.lastKnownPeerRevision = lastKnownPeerRevision
        self.device = device
        self.recordings = recordings
        self.folders = folders
        self.studyItems = studyItems
        self.artifacts = artifacts
        self.objects = objects
        self.studyManifest = studyManifest
        self.canonicalManifest = canonicalManifest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.appSchemaVersion
        sourceDeviceID = try container.decode(String.self, forKey: .sourceDeviceID)
        sourcePlatform = try container.decode(LocalNetworkSyncPlatform.self, forKey: .sourcePlatform)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        inventoryRevision = try container.decode(String.self, forKey: .inventoryRevision)
        lastKnownPeerRevision = try container.decodeIfPresent(String.self, forKey: .lastKnownPeerRevision)
        device = try container.decode(LocalNetworkSyncDeviceSection.self, forKey: .device)
        recordings = try container.decodeIfPresent([LocalNetworkSyncRecordingEntry].self, forKey: .recordings) ?? []
        folders = try container.decodeIfPresent([LocalNetworkSyncFolderEntry].self, forKey: .folders) ?? []
        studyItems = try container.decodeIfPresent([LocalNetworkSyncStudyItemEntry].self, forKey: .studyItems) ?? []
        artifacts = try container.decodeIfPresent([LocalNetworkSyncArtifactEntry].self, forKey: .artifacts) ?? []
        objects = try container.decodeIfPresent([LocalNetworkSyncObjectEntry].self, forKey: .objects)
            ?? Self.makeObjectEntries(recordings: recordings, folders: folders, studyItems: studyItems, artifacts: artifacts)
        studyManifest = try container.decodeIfPresent(StudyLibrarySyncManifest.self, forKey: .studyManifest)
        canonicalManifest = try container.decodeIfPresent(CanonicalManifest.self, forKey: .canonicalManifest)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sourceDeviceID
        case sourcePlatform
        case generatedAt
        case inventoryRevision
        case lastKnownPeerRevision
        case device
        case recordings
        case folders
        case studyItems
        case artifacts
        case objects
        case studyManifest
        case canonicalManifest
    }

    private static func makeObjectEntries(
        recordings: [LocalNetworkSyncRecordingEntry],
        folders: [LocalNetworkSyncFolderEntry],
        studyItems: [LocalNetworkSyncStudyItemEntry],
        artifacts: [LocalNetworkSyncArtifactEntry]
    ) -> [LocalNetworkSyncObjectEntry] {
        let recordingObjects = recordings.map { recording in
            LocalNetworkSyncObjectEntry(
                objectID: "recordingMetadata:\(recording.recordingID)",
                objectKind: .recordingMetadata,
                ownerID: recording.recordingID,
                displayTitle: recording.title,
                fileName: nil,
                logicalName: recording.recordingID,
                sha256: recording.metadataHash,
                size: nil,
                updatedAt: recording.updatedAt,
                deleted: recording.deleted,
                tombstone: recording.tombstone,
                sourceDeviceID: recording.sourceDeviceID,
                logicalPathToken: nil,
                availability: .local,
                transferState: nil,
                transferProgress: nil,
                conflictStatus: nil,
                autoDownloadAllowed: true
            )
        }
        let recordingAudioObjects = recordings.compactMap { recording -> LocalNetworkSyncObjectEntry? in
            guard recording.audioAvailable || recording.audioSize != nil || recording.audioAvailability != nil else {
                return nil
            }
            return LocalNetworkSyncObjectEntry(
                objectID: "recordingAudio:\(recording.recordingID)",
                objectKind: .recordingAudio,
                ownerID: recording.recordingID,
                displayTitle: recording.title,
                fileName: nil,
                logicalName: recording.recordingID,
                sha256: recording.audioChecksum,
                size: recording.audioSize,
                updatedAt: recording.updatedAt,
                deleted: recording.deleted,
                tombstone: recording.tombstone,
                sourceDeviceID: recording.sourceDeviceID,
                logicalPathToken: recording.audioLogicalPathToken,
                availability: recording.audioAvailability ?? (recording.audioAvailable ? .local : .missing),
                transferState: nil,
                transferProgress: nil,
                conflictStatus: nil,
                autoDownloadAllowed: false
            )
        }
        let folderObjects = folders.map { folder in
            LocalNetworkSyncObjectEntry(
                objectID: "studyFolder:\(folder.folderID)",
                objectKind: .studyFolder,
                ownerID: folder.folderID,
                displayTitle: folder.name,
                fileName: nil,
                logicalName: folder.path ?? folder.folderID,
                sha256: folder.revisionHash,
                size: nil,
                updatedAt: folder.updatedAt,
                deleted: folder.deleted,
                tombstone: folder.deleted,
                sourceDeviceID: nil,
                logicalPathToken: folder.path,
                availability: .local,
                transferState: nil,
                transferProgress: nil,
                conflictStatus: nil,
                autoDownloadAllowed: true
            )
        }
        let studyItemObjects = studyItems.map { item in
            LocalNetworkSyncObjectEntry(
                objectID: "studyItem:\(item.itemID)",
                objectKind: .studyItem,
                // `ownerID` is the identity copied into a legacy diff action.
                // A recording-backed item's recording relationship already lives
                // on `LocalNetworkSyncStudyItemEntry`; using it here loses the
                // actual item ID when an action-scoped manifest is constructed.
                ownerID: item.itemID,
                displayTitle: item.title,
                fileName: nil,
                logicalName: item.path ?? item.itemID,
                sha256: item.revisionHash,
                size: nil,
                updatedAt: item.updatedAt,
                deleted: item.deleted,
                tombstone: item.deleted,
                sourceDeviceID: nil,
                logicalPathToken: item.path,
                availability: .local,
                transferState: nil,
                transferProgress: nil,
                conflictStatus: item.conflictStatus,
                autoDownloadAllowed: true
            )
        }
        let artifactObjects = artifacts.map { artifact in
            LocalNetworkSyncObjectEntry(
                objectID: artifact.artifactID,
                objectKind: objectKind(for: artifact.kind),
                ownerID: artifact.ownerID,
                displayTitle: artifact.ownerID,
                fileName: fileName(for: artifact),
                logicalName: artifact.logicalPathToken,
                sha256: artifact.checksum,
                size: artifact.size,
                updatedAt: artifact.updatedAt,
                deleted: false,
                tombstone: false,
                sourceDeviceID: nil,
                logicalPathToken: artifact.logicalPathToken,
                availability: artifact.availability,
                transferState: nil,
                transferProgress: nil,
                conflictStatus: nil,
                autoDownloadAllowed: artifact.autoDownloadAllowed ?? artifact.kind.isAutoDownloadAllowed
            )
        }
        return recordingObjects + recordingAudioObjects + folderObjects + studyItemObjects + artifactObjects
    }

    private static func objectKind(for artifactKind: LocalNetworkSyncArtifactKind) -> LocalNetworkSyncObjectKind {
        switch artifactKind {
        case .metadataJSON:
            return .recordingMetadata
        case .receiveJSON:
            return .receiveRecord
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
        case .audio:
            return .recordingAudio
        }
    }

    private static func fileName(for artifact: LocalNetworkSyncArtifactEntry) -> String? {
        switch artifact.kind {
        case .metadataJSON:
            return "metadata.json"
        default:
            return artifact.logicalPathToken.split(separator: "/").last.map(String.init)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private struct LocalNetworkSyncInventoryChecksumPayload: Encodable {
    var schemaVersion: Int
    var sourceDeviceID: String
    var sourcePlatform: LocalNetworkSyncPlatform
    var generatedAt: Date
    var inventoryRevision: String
    var lastKnownPeerRevision: String?
    var device: LocalNetworkSyncDeviceSection
    var recordings: [LocalNetworkSyncRecordingEntry]
    var folders: [LocalNetworkSyncFolderEntry]
    var studyItems: [LocalNetworkSyncStudyItemEntry]
    var artifacts: [LocalNetworkSyncArtifactEntry]
    var objects: [LocalNetworkSyncObjectEntry]
    var canonicalManifest: CanonicalManifest?
}

extension LocalNetworkSyncInventory {
    var syncCoreInventory: SyncInventory {
        SyncInventory.make(
            schemaVersion: schemaVersion,
            sourceDeviceID: sourceDeviceID,
            sourcePlatform: sourcePlatform.rawValue,
            generatedAt: generatedAt,
            inventoryRevision: inventoryRevision,
            lastKnownPeerRevision: lastKnownPeerRevision,
            objects: objects.map(\.syncObject),
            directories: folders.map(\.syncDirectory),
            deviceSummary: [
                "deviceName": device.deviceName,
                "appSchemaVersion": String(device.appSchemaVersion)
            ]
        )
    }
}

extension LocalNetworkSyncObjectEntry {
    var syncObject: SyncObject {
        SyncObject(
            objectID: objectID,
            objectKind: objectKind.rawValue,
            ownerID: ownerID ?? inferredOwnerID,
            displayTitle: displayTitle,
            fileName: fileName,
            logicalName: logicalName,
            sha256: sha256,
            size: size,
            updatedAt: updatedAt,
            tombstone: tombstone ?? deleted,
            deleted: deleted,
            sourceDeviceID: sourceDeviceID,
            logicalPathToken: logicalPathToken,
            availability: SyncObjectAvailability(rawValue: availability.rawValue) ?? .missing,
            transferState: transferState.flatMap { SyncTransferState(rawValue: $0.rawValue) },
            transferProgress: transferProgress,
            conflictStatus: conflictStatus,
            autoDownloadAllowed: autoDownloadAllowed ?? true,
            metadata: [:]
        )
    }

    private var inferredOwnerID: String {
        if let logicalName, !logicalName.isEmpty {
            return logicalName
        }
        return objectID.split(separator: ":", maxSplits: 1).last.map(String.init) ?? objectID
    }
}

extension LocalNetworkSyncFolderEntry {
    var syncDirectory: SyncDirectory {
        SyncDirectory(
            directoryID: folderID,
            parentID: parentID,
            pathComponents: path?.split(separator: "/").map(String.init) ?? [name],
            name: name,
            colorToken: colorToken,
            updatedAt: updatedAt,
            tombstone: deleted,
            revisionHash: revisionHash
        )
    }
}

struct LocalNetworkSyncDeviceSection: Codable, Equatable {
    var deviceID: String
    var deviceName: String
    var platform: LocalNetworkSyncPlatform
    var generatedAt: Date
    var lastKnownPeerRevision: String?
    var appSchemaVersion: Int
    var appInstanceID: String? = nil
}

nonisolated struct LocalNetworkSyncRecordingEntry: Codable, Equatable, Identifiable {
    var id: String { recordingID }

    var recordingID: String
    var metadataHash: String?
    var audioAvailable: Bool
    var audioChecksum: String?
    var audioSize: Int64?
    var uploadLedgerState: String?
    var receiveStatus: String?
    var processingStatus: String?
    var updatedAt: Date
    var deleted: Bool
    var title: String? = nil
    var createdAt: Date? = nil
    var tombstone: Bool? = nil
    var audioAvailability: LocalNetworkSyncArtifactAvailability? = nil
    var uploadStatus: String? = nil
    var transcriptionStatus: String? = nil
    var noteStatus: String? = nil
    var sourceDeviceID: String? = nil
    var artifactRefs: [String]? = nil
    var audioLogicalPathToken: String? = nil

    init(
        recordingID: String,
        metadataHash: String?,
        audioAvailable: Bool = false,
        audioChecksum: String?,
        audioSize: Int64?,
        uploadLedgerState: String?,
        receiveStatus: String?,
        processingStatus: String?,
        updatedAt: Date,
        deleted: Bool,
        title: String? = nil,
        createdAt: Date? = nil,
        tombstone: Bool? = nil,
        audioAvailability: LocalNetworkSyncArtifactAvailability? = nil,
        uploadStatus: String? = nil,
        transcriptionStatus: String? = nil,
        noteStatus: String? = nil,
        sourceDeviceID: String? = nil,
        artifactRefs: [String]? = nil,
        audioLogicalPathToken: String? = nil
    ) {
        self.recordingID = recordingID
        self.metadataHash = metadataHash
        self.audioAvailable = audioAvailable
        self.audioChecksum = audioChecksum
        self.audioSize = audioSize
        self.uploadLedgerState = uploadLedgerState
        self.receiveStatus = receiveStatus
        self.processingStatus = processingStatus
        self.updatedAt = updatedAt
        self.deleted = deleted
        self.title = title
        self.createdAt = createdAt
        self.tombstone = tombstone
        self.audioAvailability = audioAvailability
        self.uploadStatus = uploadStatus
        self.transcriptionStatus = transcriptionStatus
        self.noteStatus = noteStatus
        self.sourceDeviceID = sourceDeviceID
        self.artifactRefs = artifactRefs
        self.audioLogicalPathToken = audioLogicalPathToken
    }

    private enum CodingKeys: String, CodingKey {
        case recordingID
        case metadataHash
        case audioAvailable
        case audioChecksum
        case audioSize
        case uploadLedgerState
        case receiveStatus
        case processingStatus
        case updatedAt
        case deleted
        case title
        case createdAt
        case tombstone
        case audioAvailability
        case uploadStatus
        case transcriptionStatus
        case noteStatus
        case sourceDeviceID
        case artifactRefs
        case audioLogicalPathToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordingID = try container.decode(String.self, forKey: .recordingID)
        metadataHash = try container.decodeIfPresent(String.self, forKey: .metadataHash)
        audioAvailable = try container.decodeIfPresent(Bool.self, forKey: .audioAvailable) ?? false
        audioChecksum = try container.decodeIfPresent(String.self, forKey: .audioChecksum)
        audioSize = try container.decodeIfPresent(Int64.self, forKey: .audioSize)
        uploadLedgerState = try container.decodeIfPresent(String.self, forKey: .uploadLedgerState)
        receiveStatus = try container.decodeIfPresent(String.self, forKey: .receiveStatus)
        processingStatus = try container.decodeIfPresent(String.self, forKey: .processingStatus)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        title = try container.decodeIfPresent(String.self, forKey: .title)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        tombstone = try container.decodeIfPresent(Bool.self, forKey: .tombstone)
        audioAvailability = try container.decodeIfPresent(LocalNetworkSyncArtifactAvailability.self, forKey: .audioAvailability)
        uploadStatus = try container.decodeIfPresent(String.self, forKey: .uploadStatus)
        transcriptionStatus = try container.decodeIfPresent(String.self, forKey: .transcriptionStatus)
        noteStatus = try container.decodeIfPresent(String.self, forKey: .noteStatus)
        sourceDeviceID = try container.decodeIfPresent(String.self, forKey: .sourceDeviceID)
        artifactRefs = try container.decodeIfPresent([String].self, forKey: .artifactRefs)
        audioLogicalPathToken = try container.decodeIfPresent(String.self, forKey: .audioLogicalPathToken)
    }
}

struct LocalNetworkSyncFolderEntry: Codable, Equatable, Identifiable {
    var id: String { folderID }

    var folderID: String
    var parentID: String?
    var path: String?
    var name: String
    var colorToken: String?
    var updatedAt: Date
    var revisionHash: String
    var deleted: Bool
}

struct LocalNetworkSyncStudyItemEntry: Codable, Equatable, Identifiable {
    var id: String { itemID }

    var itemID: String
    var kind: StudyItemKind
    var title: String
    var folderIDs: [StudyFolderID]
    var recordingID: String?
    var updatedAt: Date
    var revisionHash: String
    var deleted: Bool
    var path: String? = nil
    var conflictStatus: String? = nil
}

struct LocalNetworkSyncArtifactEntry: Codable, Equatable, Identifiable {
    var id: String { artifactID }

    var artifactID: String
    var kind: LocalNetworkSyncArtifactKind
    var ownerID: String
    var checksum: String?
    var size: Int64?
    var updatedAt: Date
    var availability: LocalNetworkSyncArtifactAvailability
    var logicalPathToken: String
    var localAvailability: LocalNetworkSyncArtifactAvailability? = nil
    var peerAvailability: LocalNetworkSyncArtifactAvailability? = nil
    var autoDownloadAllowed: Bool? = nil
}

struct LocalNetworkSyncInventoryRequest: Codable, Equatable {
    var deviceID: String
    var generatedAt: Date
    var localInventoryHash: String?
    var syncRunID: String? = nil
    var statusExchangeEnvelope: CanonicalStatusExchangeEnvelope? = nil
}

struct LocalNetworkSyncInventoryResponse: Codable, Equatable {
    var ok: Bool
    var inventory: LocalNetworkSyncInventory?
    var statusExchangeEnvelope: CanonicalStatusExchangeEnvelope? = nil
    var error: String?
}

struct LocalNetworkSyncArtifactRequest: Codable, Equatable {
    var artifactID: String
    var offset: Int64? = nil
    var length: Int? = nil
    var syncRunID: String? = nil
}

struct LocalNetworkSyncArtifactResponse: Codable, Equatable {
    var ok: Bool
    var artifactID: String?
    var kind: LocalNetworkSyncArtifactKind?
    var checksum: String?
    var size: Int64?
    var logicalPathToken: String?
    var dataBase64: String?
    var offset: Int64? = nil
    var totalSize: Int64? = nil
    var isFinalChunk: Bool? = nil
    var error: String?
}

struct LocalNetworkSyncArtifactPutRequest: Codable, Equatable {
    var artifactID: String
    var kind: LocalNetworkSyncArtifactKind
    var ownerID: String
    var checksum: String
    var size: Int64
    var updatedAt: Date
    var logicalPathToken: String
    var dataBase64: String
    var offset: Int64? = nil
    var chunkSize: Int? = nil
    var totalSize: Int64? = nil
    var isFinalChunk: Bool? = nil
    var syncRunID: String? = nil
}

struct LocalNetworkSyncArtifactPutResponse: Codable, Equatable {
    var ok: Bool
    var artifactID: String?
    var disposition: String?
    var checksum: String?
    var size: Int64?
    var confirmedBytes: Int64? = nil
    var error: String?
}

struct LocalNetworkSyncArtifactStatusRequest: Codable, Equatable {
    var artifactID: String
    var kind: LocalNetworkSyncArtifactKind? = nil
    var ownerID: String? = nil
    var logicalPathToken: String? = nil
    var checksum: String? = nil
    var size: Int64? = nil
    var syncRunID: String? = nil
}

struct LocalNetworkSyncArtifactStatusResponse: Codable, Equatable {
    var ok: Bool
    var artifactID: String?
    var checksum: String?
    var size: Int64?
    var confirmedBytes: Int64?
    var nextOffset: Int64?
    var state: LocalNetworkTransferState?
    var error: String?
}

enum LocalNetworkSyncDiffActionKind: String, Codable, Equatable {
    case uploadMetadata
    case uploadArtifact
    case downloadMetadata
    case downloadArtifact
    case uploadRecordingAudio
    case conflict
    case noOp
}

struct LocalNetworkSyncDiffAction: Codable, Equatable, Identifiable {
    var id: String
    var kind: LocalNetworkSyncDiffActionKind
    var entityKind: String
    var entityID: String
    var reason: String
}

struct LocalNetworkSyncDiffPlan: Codable, Equatable {
    var uploadMetadataActions: [LocalNetworkSyncDiffAction] = []
    var uploadArtifactActions: [LocalNetworkSyncDiffAction] = []
    var downloadMetadataActions: [LocalNetworkSyncDiffAction] = []
    var downloadArtifactActions: [LocalNetworkSyncDiffAction] = []
    var uploadRecordingAudioActions: [LocalNetworkSyncDiffAction] = []
    var conflictActions: [LocalNetworkSyncDiffAction] = []
    var noOps: [LocalNetworkSyncDiffAction] = []

    var existingUploadActions: [LocalNetworkSyncDiffAction] {
        uploadRecordingAudioActions
    }
}

nonisolated struct LocalNetworkSyncDiffPlanner {
    func plan(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        lastSuccessfulSyncAt: Date?
    ) -> LocalNetworkSyncDiffPlan {
        let corePlan = SyncDiffPlanner().plan(
            local: local.syncCoreInventory,
            peer: peer.syncCoreInventory,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt
        )
        var plan = makeCompatibilityPlan(from: corePlan)
        appendRecordingReceiveStatusNoOps(local: local, peer: peer, plan: &plan)
        suppressUploadsForPeerAvailableAudio(local: local, peer: peer, plan: &plan)
        return plan
    }

    private func makeCompatibilityPlan(from corePlan: SyncDiffPlan) -> LocalNetworkSyncDiffPlan {
        var plan = LocalNetworkSyncDiffPlan()
        for action in corePlan.actions {
            append(action, to: &plan)
        }
        return plan
    }

    private func append(_ action: SyncDiffAction, to plan: inout LocalNetworkSyncDiffPlan) {
        guard let objectKind = LocalNetworkSyncObjectKind(rawValue: action.objectKind) else {
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: "object", entityID: action.objectID, reason: "unknown_object_kind"))
            return
        }

        switch objectKind {
        case .recordingAudio:
            appendRecordingAudioAction(action, to: &plan)
        case .recordingMetadata:
            appendMetadataAction(action, entityKind: "recording", entityID: action.ownerID, to: &plan)
        case .studyFolder:
            appendMetadataAction(action, entityKind: "folder", entityID: action.ownerID, to: &plan)
        case .studyItem:
            appendMetadataAction(
                action,
                entityKind: "studyItem",
                entityID: studyItemID(for: action),
                to: &plan
            )
        case .receiveRecord, .transcriptMarkdown, .transcriptJSON, .noteMarkdown, .noteJSON, .summaryMarkdown, .summaryJSON:
            appendArtifactAction(action, to: &plan)
        }
    }

    private func appendRecordingAudioAction(_ action: SyncDiffAction, to plan: inout LocalNetworkSyncDiffPlan) {
        switch action.kind {
        case .uploadObject:
            plan.uploadRecordingAudioActions.append(legacyAction(.uploadRecordingAudio, action: action, entityKind: "recording", entityID: action.ownerID, reason: "peer_missing_audio_use_existing_upload"))
        case .downloadObject:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: isArtifactID(action.objectID) ? "artifact" : "recording", entityID: isArtifactID(action.objectID) ? action.objectID : action.ownerID, reason: "audio_auto_download_disabled"))
        case .conflict:
            plan.uploadRecordingAudioActions.append(legacyAction(.uploadRecordingAudio, action: action, entityKind: "recording", entityID: action.ownerID, reason: "peer_audio_signature_mismatch_use_existing_upload"))
        case .noOp, .skip:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: isArtifactID(action.objectID) ? "artifact" : "recording", entityID: isArtifactID(action.objectID) ? action.objectID : action.ownerID, reason: action.reason))
        case .applyTombstone:
            appendMetadataAction(action, entityKind: "recording", entityID: action.ownerID, to: &plan)
        case .updateMetadata, .useExistingUploadPath:
            plan.uploadRecordingAudioActions.append(legacyAction(.uploadRecordingAudio, action: action, entityKind: "recording", entityID: action.ownerID, reason: "peer_missing_audio_use_existing_upload"))
        }
    }

    private func appendMetadataAction(
        _ action: SyncDiffAction,
        entityKind: String,
        entityID: String,
        to plan: inout LocalNetworkSyncDiffPlan
    ) {
        switch action.kind {
        case .uploadObject, .updateMetadata:
            plan.uploadMetadataActions.append(legacyAction(.uploadMetadata, action: action, entityKind: entityKind, entityID: entityID, reason: metadataReason(action.reason, entityKind: entityKind, uploading: true)))
        case .downloadObject:
            plan.downloadMetadataActions.append(legacyAction(.downloadMetadata, action: action, entityKind: entityKind, entityID: entityID, reason: metadataReason(action.reason, entityKind: entityKind, uploading: false)))
        case .applyTombstone:
            if action.direction == .upload {
                plan.uploadMetadataActions.append(legacyAction(.uploadMetadata, action: action, entityKind: entityKind, entityID: entityID, reason: action.reason))
            } else {
                plan.downloadMetadataActions.append(legacyAction(.downloadMetadata, action: action, entityKind: entityKind, entityID: entityID, reason: action.reason))
            }
        case .conflict:
            plan.conflictActions.append(legacyAction(.conflict, action: action, entityKind: entityKind, entityID: entityID, reason: action.reason))
        case .noOp:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: entityKind, entityID: entityID, reason: entityKind == "recording" && action.reason == "checksum_equal" ? "metadata_equal" : action.reason))
        case .skip:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: entityKind, entityID: entityID, reason: action.reason))
        case .useExistingUploadPath:
            plan.uploadMetadataActions.append(legacyAction(.uploadMetadata, action: action, entityKind: entityKind, entityID: entityID, reason: action.reason))
        }
    }

    private func appendArtifactAction(_ action: SyncDiffAction, to plan: inout LocalNetworkSyncDiffPlan) {
        switch action.kind {
        case .uploadObject:
            plan.uploadArtifactActions.append(legacyAction(.uploadArtifact, action: action, entityKind: "artifact", entityID: action.objectID, reason: artifactReason(action.reason, uploading: true)))
        case .downloadObject:
            plan.downloadArtifactActions.append(legacyAction(.downloadArtifact, action: action, entityKind: "artifact", entityID: action.objectID, reason: artifactReason(action.reason, uploading: false)))
        case .conflict:
            plan.conflictActions.append(legacyAction(.conflict, action: action, entityKind: "artifact", entityID: action.objectID, reason: "artifact_checksum_conflict"))
        case .noOp:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: "artifact", entityID: action.objectID, reason: action.reason))
        case .skip:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: "artifact", entityID: action.objectID, reason: action.reason))
        case .applyTombstone, .updateMetadata, .useExistingUploadPath:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: "artifact", entityID: action.objectID, reason: action.reason))
        }
    }

    /// Mixed-version peers may still advertise a recording ID as a study
    /// item's owner. The object ID has always carried the stable item ID, so it
    /// is the authoritative source for a study-item action.
    private func studyItemID(for action: SyncDiffAction) -> String {
        let prefix = "studyItem:"
        guard action.objectID.hasPrefix(prefix) else {
            return action.ownerID
        }
        let itemID = String(action.objectID.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return itemID.isEmpty ? action.ownerID : itemID
    }

    private func appendRecordingReceiveStatusNoOps(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        for peerRecording in peer.recordings {
            guard !plan.uploadRecordingAudioActions.contains(where: { $0.entityID == peerRecording.recordingID }) else {
                continue
            }
            let localAudio = localAudioDecisionState(recordingID: peerRecording.recordingID, in: local)
            let peerAudio = peerAudioDecisionState(recordingID: peerRecording.recordingID, in: peer, localAudioState: localAudio)
            let decision = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
                localAudioState: localAudio,
                peerAudioState: peerAudio,
                transferJobState: .none,
                ledgerState: .none,
                triggerSource: .periodicSync,
                syncRunID: nil,
                objectID: "recordingAudio:\(peerRecording.recordingID)",
                recordingID: peerRecording.recordingID
            )
            if decision.shouldCreateUploadJob {
                plan.uploadRecordingAudioActions.append(action(.uploadRecordingAudio, entityKind: "recording", entityID: peerRecording.recordingID, reason: decision.reasonCode))
            } else {
                plan.noOps.append(action(.noOp, entityKind: "recording", entityID: peerRecording.recordingID, reason: decision.reasonCode))
            }
        }
    }

    private func suppressUploadsForPeerAvailableAudio(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        var retainedActions: [LocalNetworkSyncDiffAction] = []
        for action in plan.uploadRecordingAudioActions {
            let localAudio = localAudioDecisionState(recordingID: action.entityID, in: local)
            let peerAudio = peerAudioDecisionState(recordingID: action.entityID, in: peer, localAudioState: localAudio)
            let decision = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
                localAudioState: localAudio,
                peerAudioState: peerAudio,
                transferJobState: .none,
                ledgerState: .none,
                triggerSource: .periodicSync,
                syncRunID: nil,
                objectID: "recordingAudio:\(action.entityID)",
                recordingID: action.entityID
            )
            if decision.shouldCreateUploadJob {
                var retained = action
                retained.reason = decision.reasonCode
                retainedActions.append(retained)
            } else {
                plan.noOps.append(
                    self.action(
                        .noOp,
                        entityKind: action.entityKind,
                        entityID: action.entityID,
                        reason: decision.reasonCode
                    )
                )
            }
        }
        plan.uploadRecordingAudioActions = retainedActions
    }

    private func localAudioDecisionState(
        recordingID: String,
        in inventory: LocalNetworkSyncInventory
    ) -> RecordingLocalAudioState {
        guard let recording = inventory.recordings.first(where: { $0.recordingID == recordingID }) else {
            return .missing
        }
        if recording.deleted || recording.tombstone == true {
            return .deleted
        }
        let state = recordingAudioState(recordingID: recordingID, in: inventory)
        guard state.isAvailable else {
            return .missing
        }
        return .available(RecordingAudioSignature(sha256: state.checksum, size: state.size))
    }

    private func peerAudioDecisionState(
        recordingID: String,
        in inventory: LocalNetworkSyncInventory,
        localAudioState: RecordingLocalAudioState
    ) -> RecordingPeerAudioState {
        let recording = inventory.recordings.first { $0.recordingID == recordingID }
        let object = inventory.objects.first { $0.objectID == "recordingAudio:\(recordingID)" }
        if recording?.deleted == true || recording?.tombstone == true {
            return .deleted
        }
        let state = recordingAudioState(recordingID: recordingID, in: inventory)
        if state.isAvailable {
            let signature = RecordingAudioSignature(sha256: state.checksum, size: state.size)
            if let localSignature = localAudioState.signature, !localSignature.matches(signature) {
                return .different(signature)
            }
            return .available(signature)
        }
        if isCompletedReceiveStatus(recording?.receiveStatus) {
            return .unknown
        }
        if recording != nil {
            return .metadataOnly
        }
        if object != nil {
            return .missing
        }
        return .missing
    }

    private func recordingAudioState(
        recordingID: String,
        in inventory: LocalNetworkSyncInventory
    ) -> (isAvailable: Bool, checksum: String?, size: Int64?) {
        let recording = inventory.recordings.first { $0.recordingID == recordingID }
        let object = inventory.objects.first { $0.objectID == "recordingAudio:\(recordingID)" }
        let checksum = recording?.audioChecksum ?? object?.sha256
        let size = recording?.audioSize ?? object?.size
        let availability = recording?.audioAvailability ?? object?.availability
        let isAvailable = (recording?.audioAvailable == true)
            || availability == .local
            || availability == .availableOnPeer
            || availability == .complete
        return (isAvailable, checksum, size)
    }

    private func isCompletedReceiveStatus(_ value: String?) -> Bool {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return normalized == "completed" || normalized == "complete"
    }

    private func audioSignaturesMatch(
        _ local: (isAvailable: Bool, checksum: String?, size: Int64?),
        _ peer: (isAvailable: Bool, checksum: String?, size: Int64?)
    ) -> Bool {
        guard let localChecksum = local.checksum?.trimmingCharacters(in: .whitespacesAndNewlines),
              !localChecksum.isEmpty,
              let peerChecksum = peer.checksum?.trimmingCharacters(in: .whitespacesAndNewlines),
              !peerChecksum.isEmpty,
              let localSize = local.size,
              let peerSize = peer.size else {
            return false
        }
        return localChecksum == peerChecksum && localSize == peerSize
    }

    private func metadataReason(_ reason: String, entityKind: String, uploading: Bool) -> String {
        switch reason {
        case "peer_missing_object":
            return entityKind == "recording" ? "peer_missing_recording" : "peer_missing"
        case "local_missing_object":
            return entityKind == "recording" ? "local_missing_recording_metadata" : "local_missing"
        case "local_object_newer", "local_object_more_complete":
            return entityKind == "recording" ? "local_recording_newer" : "local_newer"
        case "peer_object_newer", "peer_object_more_complete":
            return entityKind == "recording" ? "peer_recording_newer" : "peer_newer"
        default:
            return reason
        }
    }

    private func artifactReason(_ reason: String, uploading: Bool) -> String {
        switch reason {
        case "peer_missing_object":
            return "peer_missing_artifact"
        case "local_missing_object":
            return "local_missing_artifact"
        case "local_object_newer", "local_object_more_complete":
            return "local_artifact_newer"
        case "peer_object_newer", "peer_object_more_complete":
            return "peer_artifact_newer"
        default:
            return reason
        }
    }

    private func legacyAction(
        _ kind: LocalNetworkSyncDiffActionKind,
        action: SyncDiffAction,
        entityKind: String,
        entityID: String,
        reason: String
    ) -> LocalNetworkSyncDiffAction {
        LocalNetworkSyncDiffAction(
            id: "\(kind.rawValue):\(entityKind):\(entityID):\(reason)",
            kind: kind,
            entityKind: entityKind,
            entityID: entityID,
            reason: reason
        )
    }

    private func isArtifactID(_ objectID: String) -> Bool {
        objectID.hasPrefix("artifact_")
    }

    private func compareRecordings(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        lastSuccessfulSyncAt: Date?,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        let localByID = Dictionary(uniqueKeysWithValues: local.recordings.map { ($0.recordingID, $0) })
        let peerByID = Dictionary(uniqueKeysWithValues: peer.recordings.map { ($0.recordingID, $0) })
        for recordingID in Set(localByID.keys).union(peerByID.keys).sorted() {
            let localRecording = localByID[recordingID]
            let peerRecording = peerByID[recordingID]
            switch (localRecording, peerRecording) {
            case let (.some(localRecording), .some(peerRecording)):
                if localRecording.metadataHash == peerRecording.metadataHash {
                    plan.noOps.append(action(.noOp, entityKind: "recording", entityID: recordingID, reason: "metadata_equal"))
                } else if lastSuccessfulSyncAt.map({ localRecording.updatedAt > $0 && peerRecording.updatedAt > $0 }) == true {
                    plan.conflictActions.append(action(.conflict, entityKind: "recording", entityID: recordingID, reason: "both_changed_after_last_sync"))
                } else if peerRecording.deleted, peerRecording.updatedAt >= localRecording.updatedAt {
                    plan.downloadMetadataActions.append(action(.downloadMetadata, entityKind: "recording", entityID: recordingID, reason: "peer_tombstone_wins"))
                } else if localRecording.deleted, localRecording.updatedAt >= peerRecording.updatedAt {
                    plan.uploadMetadataActions.append(action(.uploadMetadata, entityKind: "recording", entityID: recordingID, reason: "local_tombstone_wins"))
                } else if localRecording.updatedAt > peerRecording.updatedAt {
                    plan.uploadMetadataActions.append(action(.uploadMetadata, entityKind: "recording", entityID: recordingID, reason: "local_recording_newer"))
                } else {
                    plan.downloadMetadataActions.append(action(.downloadMetadata, entityKind: "recording", entityID: recordingID, reason: "peer_recording_newer"))
                }

                if localRecording.audioAvailable, !peerRecording.audioAvailable {
                    plan.uploadRecordingAudioActions.append(action(.uploadRecordingAudio, entityKind: "recording", entityID: recordingID, reason: "peer_missing_audio_use_existing_upload"))
                }
            case (.some, .none):
                plan.uploadMetadataActions.append(action(.uploadMetadata, entityKind: "recording", entityID: recordingID, reason: "peer_missing_recording"))
            case (.none, .some):
                plan.downloadMetadataActions.append(action(.downloadMetadata, entityKind: "recording", entityID: recordingID, reason: "local_missing_recording_metadata"))
            case (.none, .none):
                break
            }
        }
    }

    private func compareFolders(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        lastSuccessfulSyncAt: Date?,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        let localByID = Dictionary(uniqueKeysWithValues: local.folders.map { ($0.folderID, $0) })
        let peerByID = Dictionary(uniqueKeysWithValues: peer.folders.map { ($0.folderID, $0) })
        for folderID in Set(localByID.keys).union(peerByID.keys).sorted() {
            compareMetadataEntity(
                entityKind: "folder",
                entityID: folderID,
                localHash: localByID[folderID]?.revisionHash,
                peerHash: peerByID[folderID]?.revisionHash,
                localUpdatedAt: localByID[folderID]?.updatedAt,
                peerUpdatedAt: peerByID[folderID]?.updatedAt,
                localDeleted: localByID[folderID]?.deleted ?? false,
                peerDeleted: peerByID[folderID]?.deleted ?? false,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                plan: &plan
            )
        }
    }

    private func compareStudyItems(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        lastSuccessfulSyncAt: Date?,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        let localByID = Dictionary(uniqueKeysWithValues: local.studyItems.map { ($0.itemID, $0) })
        let peerByID = Dictionary(uniqueKeysWithValues: peer.studyItems.map { ($0.itemID, $0) })
        for itemID in Set(localByID.keys).union(peerByID.keys).sorted() {
            compareMetadataEntity(
                entityKind: "studyItem",
                entityID: itemID,
                localHash: localByID[itemID]?.revisionHash,
                peerHash: peerByID[itemID]?.revisionHash,
                localUpdatedAt: localByID[itemID]?.updatedAt,
                peerUpdatedAt: peerByID[itemID]?.updatedAt,
                localDeleted: localByID[itemID]?.deleted ?? false,
                peerDeleted: peerByID[itemID]?.deleted ?? false,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                plan: &plan
            )
        }
    }

    private func compareMetadataEntity(
        entityKind: String,
        entityID: String,
        localHash: String?,
        peerHash: String?,
        localUpdatedAt: Date?,
        peerUpdatedAt: Date?,
        localDeleted: Bool,
        peerDeleted: Bool,
        lastSuccessfulSyncAt: Date?,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        switch (localHash, peerHash) {
        case let (.some(localHash), .some(peerHash)) where localHash == peerHash:
            plan.noOps.append(action(.noOp, entityKind: entityKind, entityID: entityID, reason: "checksum_equal"))
        case (.some, .none):
            plan.uploadMetadataActions.append(action(.uploadMetadata, entityKind: entityKind, entityID: entityID, reason: "peer_missing"))
        case (.none, .some):
            plan.downloadMetadataActions.append(action(.downloadMetadata, entityKind: entityKind, entityID: entityID, reason: "local_missing"))
        case (.some, .some):
            let localDate = localUpdatedAt ?? .distantPast
            let peerDate = peerUpdatedAt ?? .distantPast
            let localChangedAfterSync = lastSuccessfulSyncAt.map { localDate > $0 } ?? false
            let peerChangedAfterSync = lastSuccessfulSyncAt.map { peerDate > $0 } ?? false

            if localChangedAfterSync, peerChangedAfterSync {
                plan.conflictActions.append(action(.conflict, entityKind: entityKind, entityID: entityID, reason: "both_changed_after_last_sync"))
            } else if peerDeleted, peerDate >= localDate {
                plan.downloadMetadataActions.append(action(.downloadMetadata, entityKind: entityKind, entityID: entityID, reason: "peer_tombstone_wins"))
            } else if localDeleted, localDate >= peerDate {
                plan.uploadMetadataActions.append(action(.uploadMetadata, entityKind: entityKind, entityID: entityID, reason: "local_tombstone_wins"))
            } else if peerDate > localDate {
                plan.downloadMetadataActions.append(action(.downloadMetadata, entityKind: entityKind, entityID: entityID, reason: "peer_newer"))
            } else {
                plan.uploadMetadataActions.append(action(.uploadMetadata, entityKind: entityKind, entityID: entityID, reason: "local_newer"))
            }
        case (.none, .none):
            break
        }
    }

    private func compareArtifacts(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        let localByID = Dictionary(uniqueKeysWithValues: local.artifacts.map { ($0.artifactID, $0) })
        let peerByID = Dictionary(uniqueKeysWithValues: peer.artifacts.map { ($0.artifactID, $0) })
        for artifactID in Set(localByID.keys).union(peerByID.keys).sorted() {
            let localArtifact = localByID[artifactID]
            let peerArtifact = peerByID[artifactID]
            switch (localArtifact, peerArtifact) {
            case let (.some(localArtifact), .some(peerArtifact)):
                if localArtifact.checksum == peerArtifact.checksum {
                    plan.noOps.append(action(.noOp, entityKind: "artifact", entityID: artifactID, reason: "checksum_equal"))
                } else if peerArtifact.updatedAt > localArtifact.updatedAt, peerArtifact.kind.isAutoDownloadAllowed {
                    plan.downloadArtifactActions.append(action(.downloadArtifact, entityKind: "artifact", entityID: artifactID, reason: "peer_artifact_newer"))
                } else if localArtifact.updatedAt > peerArtifact.updatedAt, localArtifact.kind != .audio {
                    plan.uploadArtifactActions.append(action(.uploadArtifact, entityKind: "artifact", entityID: artifactID, reason: "local_artifact_newer"))
                } else if localArtifact.kind == .audio || peerArtifact.kind == .audio {
                    plan.noOps.append(action(.noOp, entityKind: "artifact", entityID: artifactID, reason: "audio_uses_recording_upload"))
                } else {
                    plan.conflictActions.append(action(.conflict, entityKind: "artifact", entityID: artifactID, reason: "artifact_checksum_conflict"))
                }
            case let (.some(localArtifact), .none):
                if localArtifact.kind == .audio {
                    plan.noOps.append(action(.noOp, entityKind: "artifact", entityID: artifactID, reason: "audio_uses_recording_upload"))
                } else {
                    plan.uploadArtifactActions.append(action(.uploadArtifact, entityKind: "artifact", entityID: artifactID, reason: "peer_missing_artifact"))
                }
            case let (.none, .some(peerArtifact)):
                if peerArtifact.kind.isAutoDownloadAllowed {
                    plan.downloadArtifactActions.append(action(.downloadArtifact, entityKind: "artifact", entityID: artifactID, reason: "local_missing_artifact"))
                } else {
                    plan.noOps.append(action(.noOp, entityKind: "artifact", entityID: artifactID, reason: "audio_auto_download_disabled"))
                }
            case (.none, .none):
                break
            }
        }
    }

    private func action(
        _ kind: LocalNetworkSyncDiffActionKind,
        entityKind: String,
        entityID: String,
        reason: String
    ) -> LocalNetworkSyncDiffAction {
        LocalNetworkSyncDiffAction(
            id: "\(kind.rawValue):\(entityKind):\(entityID):\(reason)",
            kind: kind,
            entityKind: entityKind,
            entityID: entityID,
            reason: reason
        )
    }
}

struct LocalNetworkSyncState: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var localDeviceID: String?
    var peerDeviceID: String?
    var lastSyncStartedAt: Date?
    var lastSyncCompletedAt: Date?
    var lastSyncAt: Date?
    var lastSuccessfulSyncAt: Date?
    var lastPeerDeviceID: String?
    var lastLocalInventoryHash: String?
    var lastPeerInventoryHash: String?
    var lastAppliedPeerRevision: String?
    var consecutiveFailureCount: Int
    var nextAllowedSyncAt: Date?
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var pendingUploadCount: Int
    var pendingDownloadCount: Int
    var lastPlanSummary: String?
    var lastConflictCount: Int?
    var activeTransfers: [LocalNetworkTransferProgress]
    var activeSyncRunID: String?
    var controlPlaneState: LocalNetworkSyncControlPlaneState?
    var lastControlPlaneUpdatedAt: Date?

    static var empty: LocalNetworkSyncState {
        LocalNetworkSyncState(
            version: currentVersion,
            localDeviceID: nil,
            peerDeviceID: nil,
            lastSyncStartedAt: nil,
            lastSyncCompletedAt: nil,
            lastSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastPeerDeviceID: nil,
            lastLocalInventoryHash: nil,
            lastPeerInventoryHash: nil,
            lastAppliedPeerRevision: nil,
            consecutiveFailureCount: 0,
            nextAllowedSyncAt: nil,
            lastErrorCode: nil,
            lastErrorMessage: nil,
            pendingUploadCount: 0,
            pendingDownloadCount: 0,
            lastPlanSummary: nil,
            lastConflictCount: nil,
            activeTransfers: [],
            activeSyncRunID: nil,
            controlPlaneState: .idle,
            lastControlPlaneUpdatedAt: nil
        )
    }
}

enum LocalNetworkSyncArtifactValidationError: LocalizedError, Equatable {
    case invalidArtifactID
    case pathTraversal
    case absolutePath
    case unsafeResolvedPath
    case unsupportedArtifactKind
    case artifactNotFound

    var errorDescription: String? {
        switch self {
        case .invalidArtifactID:
            return "invalid_artifact_id"
        case .pathTraversal:
            return "artifact_path_traversal"
        case .absolutePath:
            return "artifact_absolute_path"
        case .unsafeResolvedPath:
            return "artifact_path_escape"
        case .unsupportedArtifactKind:
            return "unsupported_artifact_kind"
        case .artifactNotFound:
            return "artifact_not_found"
        }
    }
}

nonisolated enum LocalNetworkSyncArtifactID {
    nonisolated static func make(kind: LocalNetworkSyncArtifactKind, ownerID: String, logicalPathToken: String) -> String {
        let payload = "\(kind.rawValue)|\(ownerID)|\(logicalPathToken)"
        return "artifact_\(Data(SHA256.hash(data: Data(payload.utf8))).hexString)"
    }

    static func validate(_ artifactID: String) throws {
        guard artifactID.count == 73,
              artifactID.hasPrefix("artifact_"),
              artifactID.dropFirst("artifact_".count).allSatisfy(\.isHexDigit) else {
            throw LocalNetworkSyncArtifactValidationError.invalidArtifactID
        }
    }

    static func validateLogicalPathToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LocalNetworkSyncArtifactValidationError.artifactNotFound
        }
        guard !trimmed.hasPrefix("/") else {
            throw LocalNetworkSyncArtifactValidationError.absolutePath
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains("..") else {
            throw LocalNetworkSyncArtifactValidationError.pathTraversal
        }
    }

    static func validateLogicalPathToken(_ token: String, for kind: LocalNetworkSyncArtifactKind) throws {
        try validateLogicalPathToken(token)
        let lowercasedToken = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isValidForKind: Bool
        switch kind {
        case .metadataJSON:
            isValidForKind = lowercasedToken.hasSuffix("/metadata.json")
                || lowercasedToken == "metadata.json"
                || (lowercasedToken.hasPrefix("metadata/") && lowercasedToken.hasSuffix(".json"))
        case .receiveJSON:
            isValidForKind = lowercasedToken.hasSuffix("/receive.json") || lowercasedToken == "receive.json"
        case .transcriptMarkdown:
            isValidForKind = lowercasedToken.hasPrefix("transcripts/") && lowercasedToken.hasSuffix(".md")
        case .transcriptJSON:
            isValidForKind = lowercasedToken.hasPrefix("transcripts/") && lowercasedToken.hasSuffix(".json")
        case .noteMarkdown, .summaryMarkdown:
            isValidForKind = lowercasedToken.hasPrefix("notes/") && lowercasedToken.hasSuffix(".md")
        case .noteJSON, .summaryJSON:
            isValidForKind = lowercasedToken.hasPrefix("notes/") && lowercasedToken.hasSuffix(".json")
        case .audio:
            isValidForKind = false
        }
        guard isValidForKind else {
            throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
        }
    }
}

nonisolated enum LocalNetworkSyncArtifactFileService {
    static func safeFileURL(rootURL: URL, logicalPathToken: String, fileManager: FileManager = .default) throws -> URL {
        try LocalNetworkSyncArtifactID.validateLogicalPathToken(logicalPathToken)
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let standardizedCandidate = root
            .appendingPathComponent(logicalPathToken, isDirectory: false)
            .standardizedFileURL
        let resolvedParent = standardizedCandidate
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
        let candidate = resolvedParent
            .appendingPathComponent(standardizedCandidate.lastPathComponent, isDirectory: false)
            .standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : "\(root.path)/"
        guard candidate.path.hasPrefix(rootPath), resolvedParent.path.hasPrefix(rootPath) else {
            throw LocalNetworkSyncArtifactValidationError.unsafeResolvedPath
        }
        return candidate
    }

    static func safeFileURL(rootURL: URL, logicalPathToken: String, kind: LocalNetworkSyncArtifactKind, fileManager: FileManager = .default) throws -> URL {
        try LocalNetworkSyncArtifactID.validateLogicalPathToken(logicalPathToken, for: kind)
        return try safeFileURL(rootURL: rootURL, logicalPathToken: logicalPathToken, fileManager: fileManager)
    }

    static func metadata(for url: URL, fileManager: FileManager = .default) -> (size: Int64, updatedAt: Date)? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let updatedAt = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        return (size, updatedAt)
    }

}

nonisolated enum LocalNetworkSyncMetadataHash {
    nonisolated static func hash<Value: Encodable>(_ value: Value) -> String {
        let data = (try? encoder.encode(value)) ?? Data()
        return Data(SHA256.hash(data: data)).hexString
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

extension StudyItemMetadata {
    nonisolated var localNetworkRecordingBusinessFieldsV2: LocalNetworkRecordingBusinessFieldsV2 {
        localNetworkRecordingBusinessFieldsV2(
            explicitBusinessCustomPropertyKeys: LocalNetworkBusinessSignatureV2.explicitBusinessCustomPropertyKeys
        )
    }

    nonisolated func localNetworkRecordingBusinessFieldsV2(
        explicitBusinessCustomPropertyKeys: Set<String>
    ) -> LocalNetworkRecordingBusinessFieldsV2 {
        LocalNetworkRecordingBusinessFieldsV2(
            recordingID: recordingID ?? itemID,
            title: title,
            filing: localNetworkBusinessFilingV2,
            tags: localNetworkBusinessTagsV2,
            isDeleted: isTrashed,
            customProperties: LocalNetworkBusinessSignatureV2.filteredBusinessCustomProperties(
                customProperties,
                explicitBusinessKeys: explicitBusinessCustomPropertyKeys
            )
        )
    }

    nonisolated var localNetworkRecordingBusinessSignatureV2: String {
        LocalNetworkBusinessSignatureV2.recording(localNetworkRecordingBusinessFieldsV2)
    }

    nonisolated var localNetworkStudyItemBusinessFieldsV2: LocalNetworkStudyItemBusinessFieldsV2 {
        localNetworkStudyItemBusinessFieldsV2(
            explicitBusinessCustomPropertyKeys: LocalNetworkBusinessSignatureV2.explicitBusinessCustomPropertyKeys
        )
    }

    nonisolated func localNetworkStudyItemBusinessFieldsV2(
        explicitBusinessCustomPropertyKeys: Set<String>
    ) -> LocalNetworkStudyItemBusinessFieldsV2 {
        LocalNetworkStudyItemBusinessFieldsV2(
            itemID: itemID,
            itemKind: kind.rawValue,
            title: title,
            filing: localNetworkBusinessFilingV2,
            tags: localNetworkBusinessTagsV2,
            recordingID: recordingID,
            isTrashed: isTrashed,
            customProperties: LocalNetworkBusinessSignatureV2.filteredBusinessCustomProperties(
                customProperties,
                explicitBusinessKeys: explicitBusinessCustomPropertyKeys
            )
        )
    }

    nonisolated var localNetworkStudyItemBusinessSignatureV2: String {
        LocalNetworkBusinessSignatureV2.studyItem(localNetworkStudyItemBusinessFieldsV2)
    }

    nonisolated func hasSameLocalNetworkBusinessFieldsV2(as other: StudyItemMetadata) -> Bool {
        localNetworkStudyItemBusinessSignatureV2 == other.localNetworkStudyItemBusinessSignatureV2
    }

    /// Applies peer-owned business metadata while retaining device-local file,
    /// processing, preview and conflict state. Derived folder IDs are rebuilt
    /// from the incoming filing rather than copied from a peer-local list.
    nonisolated func mergingRemoteBusinessFieldsV2(
        from remote: StudyItemMetadata,
        explicitBusinessCustomPropertyKeys: Set<String> = LocalNetworkBusinessSignatureV2.explicitBusinessCustomPropertyKeys
    ) -> StudyItemMetadata {
        guard itemID == remote.itemID else {
            return self
        }
        if let localRecordingID = recordingID,
           let remoteRecordingID = remote.recordingID,
           localRecordingID != remoteRecordingID {
            return self
        }

        var merged = self
        merged.kind = remote.kind
        merged.title = remote.title
        merged.filing = remote.filing
        merged.tags = StudyTagList.unique(remote.tags.map { remoteTag in
            let localTag = tags.first { $0 == remoteTag }
            return StudyTag(
                id: localTag?.id,
                namespace: remoteTag.namespace,
                value: remoteTag.value,
                displayName: remoteTag.displayName,
                createdAt: localTag?.createdAt
            )
        })
        merged.folderIDs = StudyItemMetadata.defaultFolderIDs(for: remote.filing)
        if merged.recordingID == nil {
            merged.recordingID = remote.recordingID
        }
        merged.customProperties = LocalNetworkBusinessSignatureV2.mergingBusinessCustomProperties(
            local: customProperties,
            remote: remote.customProperties,
            explicitBusinessKeys: explicitBusinessCustomPropertyKeys
        )
        merged.isTrashed = remote.isTrashed
        merged.trashedAt = remote.isTrashed ? remote.trashedAt : nil
        merged.updatedAt = remote.updatedAt
        merged.modifiedByDeviceID = remote.modifiedByDeviceID
        return merged
    }

    private nonisolated var localNetworkBusinessFilingV2: LocalNetworkBusinessFilingV2 {
        LocalNetworkBusinessFilingV2(
            type: filing.type,
            subject: filing.subject,
            chapter: filing.chapter,
            topic: filing.topic
        )
    }

    private nonisolated var localNetworkBusinessTagsV2: [LocalNetworkBusinessTagV2] {
        tags.map {
            LocalNetworkBusinessTagV2(
                namespace: $0.namespace,
                value: $0.value,
                displayName: $0.displayName
            )
        }
    }
}

extension StudyFolderMetadata {
    nonisolated var localNetworkFolderBusinessFieldsV2: LocalNetworkFolderBusinessFieldsV2 {
        localNetworkFolderBusinessFieldsV2(
            explicitBusinessCustomPropertyKeys: LocalNetworkBusinessSignatureV2.explicitBusinessCustomPropertyKeys
        )
    }

    nonisolated func localNetworkFolderBusinessFieldsV2(
        explicitBusinessCustomPropertyKeys: Set<String>
    ) -> LocalNetworkFolderBusinessFieldsV2 {
        LocalNetworkFolderBusinessFieldsV2(
            folderID: folderID,
            name: name,
            level: level.rawValue,
            parentFolderID: parentFolderID,
            colorToken: colorToken?.rawValue,
            isTrashed: isTrashed,
            customProperties: LocalNetworkBusinessSignatureV2.filteredBusinessCustomProperties(
                customProperties,
                explicitBusinessKeys: explicitBusinessCustomPropertyKeys
            )
        )
    }

    nonisolated var localNetworkFolderBusinessSignatureV2: String {
        LocalNetworkBusinessSignatureV2.folder(localNetworkFolderBusinessFieldsV2)
    }

    nonisolated func hasSameLocalNetworkBusinessFieldsV2(as other: StudyFolderMetadata) -> Bool {
        localNetworkFolderBusinessSignatureV2 == other.localNetworkFolderBusinessSignatureV2
    }

    /// Applies peer-owned business metadata while retaining local membership
    /// lists, local custom state and local conflict diagnostics.
    nonisolated func mergingRemoteBusinessFieldsV2(
        from remote: StudyFolderMetadata,
        explicitBusinessCustomPropertyKeys: Set<String> = LocalNetworkBusinessSignatureV2.explicitBusinessCustomPropertyKeys
    ) -> StudyFolderMetadata {
        guard folderID == remote.folderID else {
            return self
        }

        var merged = self
        merged.name = remote.name
        merged.level = remote.level
        merged.path = remote.path
        merged.parentFolderID = remote.parentFolderID
        merged.colorToken = remote.colorToken
        merged.customProperties = LocalNetworkBusinessSignatureV2.mergingBusinessCustomProperties(
            local: customProperties,
            remote: remote.customProperties,
            explicitBusinessKeys: explicitBusinessCustomPropertyKeys
        )
        merged.isTrashed = remote.isTrashed
        merged.trashedAt = remote.isTrashed ? remote.trashedAt : nil
        merged.updatedAt = remote.updatedAt
        merged.modifiedByDeviceID = remote.modifiedByDeviceID
        return merged
    }
}

/// Compatibility wrapper for call sites that still pass an Encodable value to
/// `LocalNetworkSyncMetadataHash`. New inventory code should use
/// `businessSignature` directly so the wire-visible version prefix is retained.
nonisolated struct LocalNetworkSyncRecordingMetadataSignature: Codable, Equatable {
    let businessSignature: String

    nonisolated init(item: StudyItemMetadata) {
        businessSignature = item.localNetworkRecordingBusinessSignatureV2
    }
}
