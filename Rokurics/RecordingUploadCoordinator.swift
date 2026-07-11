//
//  RecordingUploadCoordinator.swift
//  Rokurics
//
//  Created by Codex on 2026/5/12.
//

import Combine
import Foundation

extension Notification.Name {
    static let recordingUploadJobLedgerDidChange = Notification.Name("RokuricsRecordingUploadJobLedgerDidChange")
}

@MainActor
final class RecordingUploadCoordinator: ObservableObject {
    typealias CanonicalAudioUploadPortFactory = (
        _ settings: SecureMacConnectionSnapshot,
        _ configuration: CanonicalAudioUploadRuntimeConfiguration
    ) -> any CanonicalProductionUploadPort
    typealias CanonicalTransferRuntimePortFactory = (
        _ settings: SecureMacConnectionSnapshot,
        _ configuration: CanonicalTransferRuntimeConfiguration
    ) -> any CanonicalTransferRuntimePort

    @Published private(set) var activeStatuses: [String: RecordingUploadStatus] = [:]
    @Published private(set) var errorMessages: [String: String] = [:]
    @Published private(set) var effectiveSyncStatusByObjectID: [CanonicalObjectID: CanonicalEffectiveSyncStatus] = [:]
    @Published private(set) var displaySyncStateByObjectID: [CanonicalObjectID: CanonicalDisplaySyncState] = [:]

    private let uploadClient: RecordingUploadClientProtocol
    private let jobStore: RecordingUploadJobStore
    private let retryPolicy: RecordingUploadRetryPolicy
    private let canonicalKernelSwitchResultProvider: (() -> CanonicalKernelSwitchResult)?
    private let canonicalAudioUploadJobStore: CanonicalAudioUploadJobStore
    private let canonicalAudioUploadExecutor: CanonicalAudioUploadRuntimeExecutor
    private let canonicalAudioUploadPortFactory: CanonicalAudioUploadPortFactory
    private let canonicalTransferRuntimePortFactory: CanonicalTransferRuntimePortFactory
    private let canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime
    private let canonicalChecksumRuntime: CanonicalChecksumRuntime
    private var uploadTasks: [String: Task<Void, Never>] = [:]

    init(
        uploadClient: RecordingUploadClientProtocol? = nil,
        jobStore: RecordingUploadJobStore? = nil,
        retryPolicy: RecordingUploadRetryPolicy = .standard,
        canonicalKernelSwitchResultProvider: (() -> CanonicalKernelSwitchResult)? = nil,
        canonicalAudioUploadJobStore: CanonicalAudioUploadJobStore? = nil,
        canonicalAudioUploadExecutor: CanonicalAudioUploadRuntimeExecutor = CanonicalAudioUploadRuntimeExecutor(),
        canonicalAudioUploadPortFactory: CanonicalAudioUploadPortFactory? = nil,
        canonicalTransferRuntimePortFactory: CanonicalTransferRuntimePortFactory? = nil,
        canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime? = nil,
        canonicalChecksumRuntime: CanonicalChecksumRuntime? = nil
    ) {
        let resolvedJobStore = jobStore ?? RecordingUploadJobStore()
        self.uploadClient = uploadClient ?? RecordingUploadClient()
        self.jobStore = resolvedJobStore
        self.retryPolicy = retryPolicy
        self.canonicalKernelSwitchResultProvider = canonicalKernelSwitchResultProvider
        self.canonicalAudioUploadJobStore = canonicalAudioUploadJobStore
            ?? CanonicalAudioUploadJobStore(persistenceURL: Self.defaultCanonicalAudioUploadLedgerURL(jobStore: resolvedJobStore))
        self.canonicalAudioUploadExecutor = canonicalAudioUploadExecutor
        self.canonicalStatusTruthRuntime = canonicalStatusTruthRuntime ?? CanonicalStatusTruthRuntime()
        self.canonicalChecksumRuntime = canonicalChecksumRuntime ?? CanonicalChecksumRuntime()
        self.canonicalAudioUploadPortFactory = canonicalAudioUploadPortFactory ?? { settings, configuration in
            IPhoneCanonicalSecureAudioUploadPort(
                settings: settings,
                transport: SecureMacUploadClient(),
                chunkSizePolicy: configuration.policy.chunkSize
            )
        }
        self.canonicalTransferRuntimePortFactory = canonicalTransferRuntimePortFactory ?? { settings, configuration in
            IPhoneCanonicalTransferAdapter(
                settings: settings,
                transport: SecureMacUploadClient(),
                chunkSizePolicy: configuration.policy.chunkSize
            )
        }
        preloadDisplaySnapshotsFromLedger()
    }

    func displayStatus(for metadata: RecordingMetadata) -> RecordingUploadStatus {
        Self.recordingUploadStatus(for: displaySyncState(for: metadata))
    }

    func displaySyncState(for metadata: RecordingMetadata) -> CanonicalDisplaySyncState {
        let objectID = Self.canonicalAudioObjectID(recordingID: metadata.id)
        if let cached = displaySyncStateByObjectID[objectID] {
            return cached
        }
        return Self.conservativeDisplaySyncState(metadata: metadata, activeStatus: activeStatuses[metadata.id])
    }

    func refreshDisplaySnapshot(for metadata: RecordingMetadata) {
        updateDisplaySnapshot(metadata: metadata, activeStatus: activeStatuses[metadata.id], job: try? jobStore.loadJob(recordingID: metadata.id))
    }

    func errorMessage(for metadata: RecordingMetadata) -> String? {
        errorMessages[metadata.id]
    }

    var canonicalStatusTruthReadPathAvailable: Bool {
        true
    }

    func produceCanonicalStatusFact(_ fact: CanonicalStatusFact) async -> CanonicalStatusFactMergeResult {
        let result = await canonicalStatusTruthRuntime.produce(fact)
        await refreshEffectiveSyncStatusSnapshot(for: fact.objectID)
        return result
    }

    func applyCanonicalStatusProjection(_ snapshot: CanonicalStatusProjectionSnapshot) {
        updateDisplaySnapshot(
            status: snapshot.effectiveStatus,
            displayState: CanonicalEffectiveStatusUIProjection.project(snapshot.effectiveStatus),
            objectID: snapshot.objectID
        )
    }

    func effectiveSyncStatus(for objectID: CanonicalObjectID) -> CanonicalEffectiveSyncStatus? {
        effectiveSyncStatusByObjectID[objectID]
    }

    func canonicalDisplaySyncState(for objectID: CanonicalObjectID) -> CanonicalDisplaySyncState? {
        displaySyncStateByObjectID[objectID]
    }

    func hasActiveUploadInFlight() -> Bool {
        if activeStatuses.values.contains(.uploading) {
            return true
        }
        guard let jobs = try? jobStore.loadJobs() else {
            return false
        }
        return jobs.contains(where: Self.isActiveUploadJob)
    }

    private var canonicalFullSyncDisplayBindingAllowed: Bool {
        let result = canonicalKernelSwitchResultProvider?()
            ?? CanonicalKernelSwitchConfiguration.runtimeConfigurationFromStoredDefaults().resolve()
        return result.effectiveMode == .canonicalFullSync && !result.isBlocked
    }

    private func canonicalAudioUploadRuntimePort(
        settings: SecureMacConnectionSnapshot,
        configuration: CanonicalAudioUploadRuntimeConfiguration,
        switchResult: CanonicalKernelSwitchResult
    ) -> any CanonicalProductionUploadPort {
        let port = canonicalAudioUploadPortFactory(settings, configuration)
        guard switchResult.effectiveMode == .canonicalFullSync,
              !switchResult.isBlocked,
              configuration.mode == .canonicalUploadWithLegacyFallback,
              (port.isDryRunOnly || port is IPhoneCanonicalProductionUploadPort) else {
            return port
        }
        return IPhoneCanonicalSecureAudioUploadPort(
            settings: settings,
            transport: SecureMacUploadClient(),
            chunkSizePolicy: configuration.policy.chunkSize
        )
    }

    private static func recordingUploadStatus(for displayState: CanonicalDisplaySyncState) -> RecordingUploadStatus {
        switch displayState.kind {
        case .completed, .peerVerified:
            return .uploaded
        case .uploading, .finalizing:
            return .uploading
        case .blocked, .conflict, .failed:
            return .failed
        case .hidden, .deferred, .uploadNeeded, .stale:
            return .localOnly
        }
    }

    private func refreshEffectiveSyncStatusSnapshot(for objectID: CanonicalObjectID) async {
        guard let snapshot = await canonicalStatusTruthRuntime.projectionSnapshot(for: objectID) else {
            return
        }
        updateDisplaySnapshot(
            status: snapshot.effectiveStatus,
            displayState: CanonicalEffectiveStatusUIProjection.project(snapshot.effectiveStatus),
            objectID: objectID
        )
    }

    private func updateDisplaySnapshot(
        metadata: RecordingMetadata,
        activeStatus: RecordingUploadStatus?,
        job: RecordingUploadJob?
    ) {
        let provenSignature = Self.provenUploadSignature(from: job)
        let localSignature = Self.localDisplaySignature(metadata: metadata, job: job)
        let snapshot = LegacySyncStatusToCanonicalEffectiveStatusAdapter.iPhoneUploadSnapshot(
            recordingID: metadata.id,
            localAudioHash: localSignature.hash,
            localAudioByteSize: localSignature.byteSize,
            provenUploadHash: provenSignature.hash,
            provenUploadByteSize: provenSignature.byteSize,
            legacyStatus: activeStatus?.rawValue ?? metadata.uploadStatus,
            legacyPhase: metadata.uploadPhase,
            activeUploadInFlight: activeStatus == .uploading,
            activeFailure: activeStatus == .failed,
            viewRefresh: false
        )
        let status = LegacySyncStatusToCanonicalEffectiveStatusAdapter.effectiveStatus(for: snapshot)
        let displayState = canonicalFullSyncDisplayBindingAllowed
            ? CanonicalEffectiveStatusUIProjection.project(status)
            : LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(for: status)
        let objectID = snapshot.objectID
        updateDisplaySnapshot(status: displayState.effectiveStatus, displayState: displayState, objectID: objectID)
    }

    private func setActiveStatus(
        _ status: RecordingUploadStatus?,
        for metadata: RecordingMetadata,
        job: RecordingUploadJob? = nil
    ) {
        updateActiveStatus(status, for: metadata.id)
        updateDisplaySnapshot(metadata: metadata, activeStatus: status, job: job)
    }

    private func publishDecisionDisplayState(
        _ decision: RecordingAudioUploadDecision,
        metadata: RecordingMetadata,
        recordingManager: RecordingManager? = nil,
        peerAudioState: RecordingPeerAudioState,
        ledgerState: RecordingUploadLedgerState
    ) {
        let objectID = Self.canonicalAudioObjectID(recordingID: metadata.id)
        let displayState = Self.canonicalDisplayState(
            for: decision,
            objectID: objectID,
            peerAudioState: peerAudioState,
            ledgerState: ledgerState
        )
        updateDisplaySnapshot(status: displayState.effectiveStatus, displayState: displayState, objectID: objectID)

        switch decision.displayState {
        case .preparing, .uploading, .finalizing:
            updateActiveStatus(.uploading, for: metadata.id)
            updateErrorMessage(nil, for: metadata.id)
        case .conflict, .fatalFailed, .failed:
            updateActiveStatus(.failed, for: metadata.id)
            updateErrorMessage(decision.reasonCode, for: metadata.id)
        case .waiting, .retryPending, .manualRetryAvailable, .hidden:
            updateActiveStatus(nil, for: metadata.id)
            updateErrorMessage(decision.reasonCode, for: metadata.id)
        case .uploaded:
            updateActiveStatus(nil, for: metadata.id)
            updateErrorMessage(nil, for: metadata.id)
        }

        updateRecordingProgressForDecision(
            decision,
            metadata: metadata,
            recordingManager: recordingManager
        )
    }

    private func updateRecordingProgressForDecision(
        _ decision: RecordingAudioUploadDecision,
        metadata: RecordingMetadata,
        recordingManager: RecordingManager?
    ) {
        guard let recordingManager else {
            return
        }

        let totalBytes = metadata.fileSize > 0 ? metadata.fileSize : nil
        switch decision.displayState {
        case .preparing:
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .uploading)
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: metadata.uploadProgressFraction,
                confirmedBytes: metadata.uploadProgressConfirmedBytes,
                totalBytes: metadata.uploadProgressTotalBytes ?? totalBytes,
                phase: "preparing",
                description: "准备上传"
            )
        case .uploading:
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .uploading)
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: nil,
                confirmedBytes: nil,
                totalBytes: totalBytes,
                phase: "uploading",
                description: "上传进行中"
            )
        case .finalizing:
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .uploading)
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: nil,
                confirmedBytes: nil,
                totalBytes: totalBytes,
                phase: "finalizing",
                description: "正在确认上传"
            )
        case .waiting:
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: nil,
                confirmedBytes: nil,
                totalBytes: totalBytes,
                phase: "deferred",
                description: "等待对端音频状态"
            )
        case .retryPending, .manualRetryAvailable:
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: nil,
                confirmedBytes: nil,
                totalBytes: totalBytes,
                phase: "retryPending",
                description: "等待自动重试"
            )
        case .hidden:
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: nil,
                confirmedBytes: nil,
                totalBytes: totalBytes,
                phase: "deferred",
                description: decision.reasonCode
            )
        case .conflict:
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: nil,
                confirmedBytes: nil,
                totalBytes: totalBytes,
                phase: "conflict",
                description: "上传冲突"
            )
        case .fatalFailed:
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: nil,
                confirmedBytes: nil,
                totalBytes: totalBytes,
                phase: "fatalFailed",
                description: decision.reasonCode
            )
        case .failed:
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: nil,
                confirmedBytes: nil,
                totalBytes: totalBytes,
                phase: "failed",
                description: decision.reasonCode
            )
        case .uploaded:
            break
        }
    }

    private static func canonicalDisplayState(
        for decision: RecordingAudioUploadDecision,
        objectID: CanonicalObjectID,
        peerAudioState: RecordingPeerAudioState,
        ledgerState: RecordingUploadLedgerState
    ) -> CanonicalDisplaySyncState {
        let status = canonicalEffectiveStatus(
            for: decision,
            objectID: objectID,
            peerAudioState: peerAudioState,
            ledgerState: ledgerState
        )
        return CanonicalEffectiveStatusUIProjection.project(status)
    }

    private static func canonicalEffectiveStatus(
        for decision: RecordingAudioUploadDecision,
        objectID: CanonicalObjectID,
        peerAudioState: RecordingPeerAudioState,
        ledgerState: RecordingUploadLedgerState
    ) -> CanonicalEffectiveSyncStatus {
        let observedAt = CanonicalTimestamp(Date())
        let proof = canonicalProof(
            for: decision,
            objectID: objectID,
            peerAudioState: peerAudioState,
            ledgerState: ledgerState,
            observedAt: observedAt
        )
        let phase: CanonicalStatusPhase
        let displayState: CanonicalStatusDisplayState
        let blocker: CanonicalStatusBlocker?
        let canDisplayAsComplete: Bool
        let canSuppressLegacyDuplicate: Bool

        switch decision.displayState {
        case .preparing, .uploading:
            phase = .uploading
            displayState = .uploading
            blocker = nil
            canDisplayAsComplete = false
            canSuppressLegacyDuplicate = false
        case .finalizing:
            phase = .finalizing
            displayState = .finalizing
            blocker = nil
            canDisplayAsComplete = false
            canSuppressLegacyDuplicate = false
        case .uploaded:
            phase = proof.map { completionPhase(for: $0) } ?? .deferred
            displayState = proof == nil ? .waiting : .complete
            blocker = proof == nil ? .completedLedgerRejectedAsPeerProof : nil
            canDisplayAsComplete = proof != nil
            canSuppressLegacyDuplicate = proof != nil
        case .conflict:
            phase = .conflict
            displayState = .conflict
            blocker = .existingDifferentAudioConflict
            canDisplayAsComplete = false
            canSuppressLegacyDuplicate = false
        case .fatalFailed, .failed:
            phase = .blocked
            displayState = .blocked
            blocker = .viewRefreshCannotCreateUploadJob
            canDisplayAsComplete = false
            canSuppressLegacyDuplicate = false
        case .waiting, .retryPending, .manualRetryAvailable, .hidden:
            phase = .deferred
            displayState = .waiting
            if decision.reasonCode.contains("retry") {
                blocker = .retryDrainerRequiresExistingEligibleJob
            } else if decision.reasonCode == "trigger_cannot_create_upload" || decision.reasonCode == "view_refresh_only" {
                blocker = .viewRefreshCannotCreateUploadJob
            } else {
                blocker = .peerProofUnavailable
            }
            canDisplayAsComplete = false
            canSuppressLegacyDuplicate = false
        }

        return CanonicalEffectiveSyncStatus(
            objectID: objectID,
            domain: .audioUpload,
            phase: phase,
            displayState: displayState,
            proof: proof,
            canDisplayAsComplete: canDisplayAsComplete,
            canCreateUploadJob: decision.shouldCreateUploadJob,
            canSuppressLegacyDuplicate: canSuppressLegacyDuplicate,
            blocker: blocker
        )
    }

    private static func canonicalProof(
        for decision: RecordingAudioUploadDecision,
        objectID: CanonicalObjectID,
        peerAudioState: RecordingPeerAudioState,
        ledgerState: RecordingUploadLedgerState,
        observedAt: CanonicalTimestamp
    ) -> CanonicalStatusProof? {
        guard decision.displayState == .uploaded else {
            return nil
        }
        if case .available(let signature) = peerAudioState,
           let hash = signature.normalizedSHA256,
           let byteSize = signature.size {
            return CanonicalStatusProof(
                kind: .sameHashAndByteSize,
                objectID: objectID,
                hash: CanonicalHash(hash),
                byteSize: byteSize,
                observedAt: observedAt
            )
        }
        return nil
    }

    private static func completionPhase(for proof: CanonicalStatusProof) -> CanonicalStatusPhase {
        switch proof.kind {
        case .sameHashAndByteSize, .peerHashSize, .peerInventoryHashSizeMatch:
            return .peerVerified
        case .finalizeProof, .dualAckProofChain:
            return .completed
        default:
            return .deferred
        }
    }

    private func preloadDisplaySnapshotsFromLedger() {
        guard let jobs = try? jobStore.loadJobs() else {
            return
        }
        for job in jobs {
            let provenSignature = Self.provenUploadSignature(from: job)
            let status = Self.effectiveStatusFromLedgerSnapshot(
                recordingID: job.recordingID,
                job: job,
                provenHash: provenSignature.hash,
                provenByteSize: provenSignature.byteSize
            )
            let displayState = CanonicalEffectiveStatusUIProjection.project(status)
            updateDisplaySnapshot(status: displayState.effectiveStatus, displayState: displayState, objectID: status.objectID)
        }
    }

    private func updateDisplaySnapshot(
        status: CanonicalEffectiveSyncStatus,
        displayState: CanonicalDisplaySyncState,
        objectID: CanonicalObjectID
    ) {
        if effectiveSyncStatusByObjectID[objectID] != status {
            effectiveSyncStatusByObjectID[objectID] = status
        }
        if displaySyncStateByObjectID[objectID] != displayState {
            displaySyncStateByObjectID[objectID] = displayState
        }
    }

    private func updateActiveStatus(_ status: RecordingUploadStatus?, for recordingID: String) {
        guard activeStatuses[recordingID] != status else {
            return
        }
        activeStatuses[recordingID] = status
    }

    private func updateErrorMessage(_ message: String?, for recordingID: String) {
        guard errorMessages[recordingID] != message else {
            return
        }
        errorMessages[recordingID] = message
    }

    private static func conservativeDisplaySyncState(
        metadata: RecordingMetadata,
        activeStatus: RecordingUploadStatus?
    ) -> CanonicalDisplaySyncState {
        let objectID = canonicalAudioObjectID(recordingID: metadata.id)
        let proof = CanonicalStatusProof(
            kind: activeStatus == .uploading ? .metadataOnly : .peerUnknown,
            objectID: objectID,
            byteSize: metadata.fileSize > 0 ? metadata.fileSize : nil,
            observedAt: CanonicalTimestamp(Date())
        )
        let phase: CanonicalStatusPhase
        let displayState: CanonicalStatusDisplayState
        let blocker: CanonicalStatusBlocker?
        switch activeStatus ?? RecordingUploadStatus(rawMetadataValue: metadata.uploadStatus) {
        case .uploading:
            phase = .uploading
            displayState = .uploading
            blocker = nil
        case .failed:
            phase = .blocked
            displayState = .blocked
            blocker = .viewRefreshCannotCreateUploadJob
        case .uploaded, .localOnly:
            phase = .peerUnknown
            displayState = .waiting
            blocker = .peerProofUnavailable
        }

        let status = CanonicalEffectiveSyncStatus(
            objectID: objectID,
            domain: .audioUpload,
            phase: phase,
            displayState: displayState,
            proof: proof,
            canDisplayAsComplete: false,
            canCreateUploadJob: false,
            canSuppressLegacyDuplicate: false,
            blocker: blocker
        )
        return CanonicalEffectiveStatusUIProjection.project(status)
    }

    private static func effectiveStatusFromLedgerSnapshot(
        recordingID: String,
        job: RecordingUploadJob,
        provenHash: String?,
        provenByteSize: Int64?
    ) -> CanonicalEffectiveSyncStatus {
        let snapshot = LegacySyncStatusToCanonicalEffectiveStatusAdapter.iPhoneUploadSnapshot(
            recordingID: recordingID,
            provenUploadHash: provenHash,
            provenUploadByteSize: provenByteSize,
            legacyStatus: job.overallState == .succeeded ? RecordingUploadStatus.uploaded.rawValue : nil,
            legacyPhase: job.resumableState?.rawValue,
            activeUploadInFlight: job.overallState == .inProgress,
            activeFailure: job.overallState == .retryableFailed || job.overallState == .fatalFailed,
            viewRefresh: false
        )
        return LegacySyncStatusToCanonicalEffectiveStatusAdapter.effectiveStatus(for: snapshot)
    }

    private static func provenUploadSignature(from job: RecordingUploadJob?) -> (hash: String?, byteSize: Int64?) {
        guard let job,
              (job.overallState == .succeeded || job.audioStage == .succeeded),
              let hash = job.audioTotalSHA256?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hash.isEmpty,
              let byteSize = job.audioTotalBytes,
              byteSize > 0 else {
            return (nil, nil)
        }
        return (hash, byteSize)
    }

    private static func localDisplaySignature(
        metadata: RecordingMetadata,
        job: RecordingUploadJob?
    ) -> (hash: String?, byteSize: Int64?) {
        let byteSize = metadata.fileSize > 0 ? metadata.fileSize : job?.audioTotalBytes
        let hash = job?.audioTotalSHA256?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (hash?.isEmpty == false ? hash : nil, byteSize)
    }

    func upload(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        recordingManager: RecordingManager,
        traceID: String? = nil,
        triggerSource: RecordingAudioSyncTriggerSource = .manualUploadButton,
        peerAudioState: RecordingPeerAudioState = .unknown,
        syncRunID: String? = nil
    ) {
        let resolvedTraceID = traceID ?? UploadFlightRecorder.currentTraceID ?? UploadFlightRecorder.makeTraceID()
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "uploadCoordinatorEntered",
            traceID: resolvedTraceID,
            recordingID: metadata.id,
            eventResult: "begin",
            uploadStatus: metadata.uploadStatus
        )
        guard uploadTasks[metadata.id] == nil else {
            setActiveStatus(.uploading, for: metadata, job: try? jobStore.loadJob(recordingID: metadata.id))
            updateErrorMessage(nil, for: metadata.id)
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorSkippedWithReason",
                traceID: resolvedTraceID,
                recordingID: metadata.id,
                eventResult: "skip",
                reasonCode: "active_upload_exists",
                uploadStatus: metadata.uploadStatus
            )
            return
        }

        uploadTasks[metadata.id] = Task { [weak self, weak recordingManager] in
            guard let self, let recordingManager else {
                return
            }

            _ = await UploadFlightRecorder.$currentTraceID.withValue(resolvedTraceID) {
                await self.uploadAndWait(
                    metadata: metadata,
                    settings: settings,
                    recordingManager: recordingManager,
                    traceID: resolvedTraceID,
                    triggerSource: triggerSource,
                    peerAudioState: peerAudioState,
                    transferJobState: .none,
                    syncRunID: syncRunID
                )
            }
            self.uploadTasks[metadata.id] = nil
        }
    }

    @discardableResult
    func uploadAndWait(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        recordingManager: RecordingManager,
        traceID: String? = nil,
        triggerSource: RecordingAudioSyncTriggerSource = .manualUploadButton,
        peerAudioState: RecordingPeerAudioState = .unknown,
        transferJobState: RecordingTransferJobState = .none,
        syncRunID: String? = nil
    ) async -> RecordingUploadStatus {
        let resolvedTraceID = traceID ?? UploadFlightRecorder.currentTraceID ?? UploadFlightRecorder.makeTraceID()
        return await UploadFlightRecorder.$currentTraceID.withValue(resolvedTraceID) {
            await uploadAndWaitWithActiveTrace(
                metadata: metadata,
                settings: settings,
                recordingManager: recordingManager,
                traceID: resolvedTraceID,
                triggerSource: triggerSource,
                peerAudioState: peerAudioState,
                transferJobState: transferJobState,
                syncRunID: syncRunID
            )
        }
    }

    private func uploadAndWaitWithActiveTrace(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        recordingManager: RecordingManager,
        traceID: String,
        triggerSource: RecordingAudioSyncTriggerSource,
        peerAudioState: RecordingPeerAudioState,
        transferJobState providedTransferJobState: RecordingTransferJobState,
        syncRunID: String?
    ) async -> RecordingUploadStatus {
        let perfStartedAt = Date()
        var perfStages = CanonicalPerfLog.StageDurations.empty
        ConnectionDiagnosticsStore.shared.recordPerfLog(
            CanonicalPerfLog.started(operation: .upload),
            deviceID: settings.deviceID,
            syncRunID: syncRunID
        )
        defer {
            let totalMs = CanonicalPerfLog.elapsedMs(since: perfStartedAt)
            for record in CanonicalPerfLog.finishedRecords(
                operation: .upload,
                totalMs: totalMs,
                stages: perfStages
            ) {
                ConnectionDiagnosticsStore.shared.recordPerfLog(
                    record,
                    deviceID: settings.deviceID,
                    syncRunID: syncRunID
                )
            }
        }
        let recordingIDPrefix = String(metadata.id.prefix(12))
        print("[RokuricsRecordingUpload] coordinator called recordingIDPrefix=\(recordingIDPrefix), localStatus=\(metadata.uploadStatus)")
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "uploadCoordinatorEntered",
            traceID: traceID,
            recordingID: metadata.id,
            eventResult: "begin",
            uploadStatus: metadata.uploadStatus
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "uploadCoordinatorMetadataLoaded",
            traceID: traceID,
            recordingID: metadata.id,
            eventResult: "success",
            uploadStatus: metadata.uploadStatus,
            fileSize: metadata.fileSize,
            resolvedRelativePathToken: metadata.relativeAudioPath
        )

        if activeStatuses[metadata.id] == .uploading {
            setActiveStatus(.uploading, for: metadata, job: try? jobStore.loadJob(recordingID: metadata.id))
            updateErrorMessage(nil, for: metadata.id)
            print("[RokuricsRecordingUpload] coordinator skipped active upload recordingIDPrefix=\(recordingIDPrefix)")
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorSkippedWithReason",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "skip",
                reasonCode: "active_status_uploading",
                uploadStatus: metadata.uploadStatus
            )
            return .uploading
        }

        let existingLedgerJob = try? jobStore.loadJob(recordingID: metadata.id)
        let ledgerDecisionState = uploadLedgerState(existingLedgerJob)
        let localAudioDecision = await localAudioDecisionState(for: metadata, traceID: traceID)
        let localAudioState = localAudioDecision.state
        perfStages.set(.hashMs, durationMs: localAudioDecision.hashDurationMs)
        if localAudioDecision.hashDurationMs > 0 {
            ConnectionDiagnosticsStore.shared.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .upload,
                    subphase: .hashMs,
                    durationMs: localAudioDecision.hashDurationMs,
                    result: "localAudioSignature"
                ),
                deviceID: settings.deviceID,
                syncRunID: syncRunID
            )
        }
        let decision = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
            localAudioState: localAudioState,
            peerAudioState: peerAudioState,
            transferJobState: providedTransferJobState,
            ledgerState: ledgerDecisionState,
            triggerSource: triggerSource,
            syncRunID: syncRunID,
            objectID: Self.audioObjectID(recordingID: metadata.id),
            recordingID: metadata.id
        )
        recordDecision(
            decision,
            metadata: metadata,
            traceID: traceID,
            triggerSource: triggerSource,
            localAudioState: localAudioState,
            peerAudioState: peerAudioState,
            transferJobState: providedTransferJobState,
            ledgerState: ledgerDecisionState,
            syncRunID: syncRunID
        )
        guard decision.shouldCreateUploadJob else {
            publishDecisionDisplayState(
                decision,
                metadata: metadata,
                recordingManager: recordingManager,
                peerAudioState: peerAudioState,
                ledgerState: ledgerDecisionState
            )
            switch decision.displayState {
            case .uploaded:
                return .uploaded
            case .preparing, .uploading, .finalizing, .waiting, .retryPending:
                return .uploading
            case .conflict, .fatalFailed, .failed:
                return .failed
            case .hidden, .manualRetryAvailable:
                return .localOnly
            }
        }

        guard settings.isPaired else {
            setActiveStatus(.failed, for: metadata)
            updateErrorMessage(RecordingUploadError.notPaired.localizedDescription, for: metadata.id)
            print("[RokuricsRecordingUpload] coordinator rejected unpaired recordingIDPrefix=\(recordingIDPrefix)")
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorSkippedWithReason",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "mac_not_paired",
                uploadStatus: metadata.uploadStatus,
                safeErrorMessage: RecordingUploadError.notPaired.localizedDescription
            )
            return .failed
        }

        do {
            try jobStore.recoverStaleInProgressJobs(now: Date())
            let existingJob = try jobStore.ensureJob(for: metadata, settings: settings, now: Date())
            print("[RokuricsRecordingUpload] upload ledger ready recordingIDPrefix=\(recordingIDPrefix), overall=\(existingJob.overallState.rawValue), metadataStage=\(existingJob.metadataStage.rawValue), audioStage=\(existingJob.audioStage.rawValue)")
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorLedgerLoaded",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus,
                ledgerState: "\(existingJob.overallState.rawValue)/\(existingJob.metadataStage.rawValue)/\(existingJob.audioStage.rawValue)",
                jobID: existingJob.id
            )
            if existingJob.overallState == .fatalFailed {
                setActiveStatus(.failed, for: metadata, job: existingJob)
                updateErrorMessage(existingJob.lastErrorMessage ?? "上传已失败，需要先处理冲突。", for: metadata.id)
                try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
                print("[RokuricsRecordingUpload] coordinator rejected fatal ledger recordingIDPrefix=\(recordingIDPrefix), errorCode=\(existingJob.lastErrorCode ?? "unknown")")
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "uploadCoordinatorSkippedWithReason",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "fail",
                    reasonCode: existingJob.lastErrorCode ?? "fatal_ledger",
                    uploadStatus: metadata.uploadStatus,
                    ledgerState: existingJob.overallState.rawValue,
                    jobID: existingJob.id,
                    safeErrorMessage: existingJob.lastErrorMessage
                )
                return .failed
            }
            if RecordingUploadStatus(rawMetadataValue: metadata.uploadStatus) == .uploaded {
                print("[RokuricsRecordingUpload] local uploaded status will re-drive true audio upload path recordingIDPrefix=\(recordingIDPrefix)")
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "uploadCoordinatorLedgerCompletedDetected",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "success",
                    reasonCode: "local_uploaded_status_redriven",
                    uploadStatus: metadata.uploadStatus,
                    ledgerState: existingJob.overallState.rawValue,
                    jobID: existingJob.id
                )
            }
        } catch {
            setActiveStatus(.failed, for: metadata)
            updateErrorMessage("上传任务账本读取失败：\(error.localizedDescription)", for: metadata.id)
            print("[RokuricsRecordingUpload] upload ledger failed recordingIDPrefix=\(recordingIDPrefix), error=\(error.localizedDescription)")
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorSkippedWithReason",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "ledger_read_failed",
                uploadStatus: metadata.uploadStatus,
                errorDomain: "RecordingUploadJobStore",
                safeErrorMessage: error.localizedDescription
            )
            return .failed
        }

        if let canonicalStatus = await uploadViaCanonicalAudioRuntimeIfEnabled(
            metadata: metadata,
            settings: settings,
            recordingManager: recordingManager,
            traceID: traceID,
            triggerSource: triggerSource,
            localAudioState: localAudioState,
            peerAudioState: peerAudioState,
            ledgerState: uploadLedgerState(try? jobStore.loadJob(recordingID: metadata.id)),
            syncRunID: syncRunID
        ) {
            return canonicalStatus
        }

        do {
            let fallbackJob = try jobStore.ensureJob(for: metadata, settings: settings, now: Date())
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorFallbackLedgerReady",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus,
                ledgerState: "\(fallbackJob.overallState.rawValue)/\(fallbackJob.metadataStage.rawValue)/\(fallbackJob.audioStage.rawValue)",
                jobID: fallbackJob.id
            )
        } catch {
            setActiveStatus(.failed, for: metadata)
            updateErrorMessage("创建上传任务失败：\(error.localizedDescription)", for: metadata.id)
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorFallbackEnsureJobFailed",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "fallback_ensure_job_failed",
                uploadStatus: metadata.uploadStatus,
                errorDomain: "RecordingUploadJobStore",
                safeErrorMessage: error.localizedDescription
            )
            return .failed
        }

        setActiveStatus(.uploading, for: metadata)
        updateErrorMessage(nil, for: metadata.id)

        do {
            let audioURL = try jobStore.audioURL(for: metadata)
            let fileExists = jobStore.fileExists(at: audioURL)
            let fileSize = fileExists ? (try? jobStore.fileSize(at: audioURL)) : nil
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: fileExists ? "uploadCoordinatorAudioResolved" : "uploadCoordinatorAudioMissing",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: fileExists ? "success" : "fail",
                reasonCode: fileExists ? nil : "audio_file_missing",
                uploadStatus: metadata.uploadStatus,
                fileExists: fileExists,
                fileSize: fileSize,
                resolvedRelativePathToken: metadata.relativeAudioPath
            )
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorFileSizeChecked",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: (fileSize ?? 0) > 0 ? "success" : "fail",
                reasonCode: (fileSize ?? 0) > 0 ? nil : "audio_file_empty_or_missing",
                uploadStatus: metadata.uploadStatus,
                fileExists: fileExists,
                fileSize: fileSize
            )
            let uploadJob = try jobStore.markAttemptStarted(recordingID: metadata.id, now: Date())
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorJobCreated",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus,
                ledgerState: uploadJob.overallState.rawValue,
                jobID: uploadJob.id
            )
            try recordingManager.updateUploadStatus(recordingID: metadata.id, status: .uploading)
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorStatusUpdated",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: RecordingUploadStatus.uploading.rawValue,
                ledgerState: uploadJob.overallState.rawValue,
                jobID: uploadJob.id
            )
            print("[RokuricsRecordingUpload] upload attempt started recordingIDPrefix=\(recordingIDPrefix), attempt=\(uploadJob.attemptCount)")
            let progress: RecordingUploadProgressHandler = { [weak self] event in
                guard let self else {
                    return
                }

                let updatedJob = try self.jobStore.applyProgress(recordingID: metadata.id, event: event, now: Date())
                Self.recordProgressTrace(event, metadata: metadata, job: updatedJob, traceID: traceID)
                if let progressUpdate = Self.metadataProgressUpdate(for: event, job: updatedJob) {
                    try? recordingManager.updateUploadProgress(
                        recordingID: metadata.id,
                        fraction: progressUpdate.fraction,
                        confirmedBytes: progressUpdate.confirmedBytes,
                        totalBytes: progressUpdate.totalBytes,
                        phase: progressUpdate.phase,
                        description: progressUpdate.description
                    )
                }
            }
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorClientCallStarted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "begin",
                uploadStatus: RecordingUploadStatus.uploading.rawValue,
                ledgerState: uploadJob.overallState.rawValue,
                jobID: uploadJob.id
            )
            var resumeContext = uploadJob.resumeContext
            if let localSignature = localAudioState.signature {
                resumeContext.audioTotalSHA256 = localSignature.normalizedSHA256
                resumeContext.audioTotalBytes = localSignature.size ?? resumeContext.audioTotalBytes
            }
            let result = try await uploadClient.uploadRecording(
                metadata: metadata.updatingUploadStatus(.uploading),
                settings: settings,
                progress: progress,
                resumeContext: resumeContext
            )
            let completedJob = try markUploadSucceeded(
                recordingID: metadata.id,
                result: result,
                now: Date(),
                proofSignature: localAudioState.signature
            )
            try recordingManager.updateUploadStatus(recordingID: metadata.id, status: .uploaded)
            print("[RokuricsRecordingUpload] upload attempt completed recordingIDPrefix=\(recordingIDPrefix), metadataDisposition=\(result.metadataDisposition ?? "unknown"), audioDisposition=\(result.audioDisposition ?? "unknown")")
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorClientCallCompleted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                reasonCode: result.audioDisposition,
                uploadStatus: RecordingUploadStatus.uploaded.rawValue,
                ledgerState: completedJob.overallState.rawValue,
                jobID: completedJob.id,
                confirmedBytes: completedJob.audioConfirmedBytes,
                totalBytes: completedJob.audioTotalBytes
            )
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorStatusUpdated",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: RecordingUploadStatus.uploaded.rawValue,
                ledgerState: completedJob.overallState.rawValue,
                jobID: completedJob.id
            )
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: 1,
                confirmedBytes: completedJob.audioTotalBytes,
                totalBytes: completedJob.audioTotalBytes,
                phase: "completed",
                description: "上传完成"
            )
            _ = await produceLocalUploadSucceededFactIfPresent(
                recordingID: metadata.id,
                job: completedJob
            )
            let latestMetadata = latestUploadedMetadata(
                recordingID: metadata.id,
                fallback: metadata,
                recordingManager: recordingManager
            )
            setActiveStatus(nil, for: latestMetadata, job: completedJob)
            updateErrorMessage(nil, for: metadata.id)
            return .uploaded
        } catch is CancellationError {
            let failedJob = try? jobStore.markRetryableFailure(
                recordingID: metadata.id,
                classification: RecordingUploadFailureClassification(
                    code: "upload_cancelled",
                    message: "上传已中断，可重试。",
                    isFatal: false
                ),
                retryPolicy: retryPolicy,
                now: Date()
            )
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: failedJob?.currentProgressFraction,
                confirmedBytes: failedJob?.audioConfirmedBytes,
                totalBytes: failedJob?.audioTotalBytes ?? (metadata.fileSize > 0 ? metadata.fileSize : nil),
                phase: "retryPending",
                description: "上传已中断，可重试。"
            )
            setActiveStatus(nil, for: metadata, job: failedJob)
            print("[RokuricsRecordingUpload] upload cancelled recordingIDPrefix=\(recordingIDPrefix)")
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorClientCallFailed",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "upload_cancelled",
                uploadStatus: RecordingUploadStatus.failed.rawValue
            )
            return .failed
        } catch {
            if let storeError = error as? RecordingUploadJobStoreError,
               case let .jobNotFound(missingRecordingID) = storeError {
                let lastReadError = jobStore.lastReadError ?? "none"
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "uploadCoordinatorJobNotFoundDiagnostic",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "fail",
                    reasonCode: "job_not_found_on_fallback",
                    uploadStatus: RecordingUploadStatus.failed.rawValue,
                    ledgerState: "ledgerFileExists=\(jobStore.ledgerFileExists)",
                    errorDomain: "RecordingUploadJobStore",
                    errorCode: "jobNotFound",
                    safeErrorMessage: "missingRecordingID=\(String(missingRecordingID.prefix(12)));lastReadError=\(String(lastReadError.prefix(96)))"
                )
            }
            let classification = RecordingUploadFailureClassification.classify(error)
            let failedJob = try? jobStore.markFailure(
                recordingID: metadata.id,
                classification: classification,
                retryPolicy: retryPolicy,
                now: Date()
            )
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
            let failedPhase: String
            let failedDescription: String
            if classification.code.contains("conflict") {
                failedPhase = "conflict"
                failedDescription = "上传冲突"
            } else if classification.isFatal {
                failedPhase = "fatalFailed"
                failedDescription = classification.message
            } else {
                failedPhase = "retryPending"
                failedDescription = "传输失败，可重试"
            }
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: failedJob?.currentProgressFraction,
                confirmedBytes: failedJob?.audioConfirmedBytes,
                totalBytes: failedJob?.audioTotalBytes ?? (metadata.fileSize > 0 ? metadata.fileSize : nil),
                phase: failedPhase,
                description: failedDescription
            )
            setActiveStatus(.failed, for: metadata, job: failedJob)
            updateErrorMessage(error.localizedDescription, for: metadata.id)
            print("[RokuricsRecordingUpload] upload attempt failed recordingIDPrefix=\(recordingIDPrefix), errorCode=\(classification.code)")
            if classification.code.contains("conflict") {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "audioConflictDetected",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "fail",
                    reasonCode: classification.code,
                    uploadStatus: RecordingUploadStatus.failed.rawValue,
                    safeErrorMessage: "上传冲突"
                )
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "uploadConflictDetected",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "fail",
                    reasonCode: classification.code,
                    uploadStatus: RecordingUploadStatus.failed.rawValue,
                    safeErrorMessage: "上传冲突"
                )
            }
            if triggerSource == .retryDrainer {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "retryJobFailed",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "fail",
                    reasonCode: classification.code,
                    uploadStatus: RecordingUploadStatus.failed.rawValue,
                    safeErrorMessage: classification.message
                )
            }
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorClientCallFailed",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: classification.code,
                uploadStatus: RecordingUploadStatus.failed.rawValue,
                errorDomain: "RecordingUploadCoordinator",
                errorCode: classification.code,
                safeErrorMessage: error.localizedDescription
            )
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorStatusUpdated",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: classification.code,
                uploadStatus: RecordingUploadStatus.failed.rawValue
            )
            return .failed
        }
    }

    private func markUploadSucceeded(
        recordingID: String,
        result: RecordingUploadResult,
        now: Date,
        proofSignature: RecordingAudioSignature?
    ) throws -> RecordingUploadJob {
        let succeededJob = try jobStore.markSucceeded(recordingID: recordingID, result: result, now: now)
        guard let proofSignature else {
            return succeededJob
        }

        return (try? jobStore.recordCompletedAudioProof(
            recordingID: recordingID,
            signature: proofSignature,
            now: now
        )) ?? succeededJob
    }

    private func latestUploadedMetadata(
        recordingID: String,
        fallback metadata: RecordingMetadata,
        recordingManager: RecordingManager
    ) -> RecordingMetadata {
        recordingManager.recordings.first(where: { $0.id == recordingID }) ?? metadata.updatingUploadStatus(.uploaded)
    }

    private func uploadViaCanonicalAudioRuntimeIfEnabled(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        recordingManager: RecordingManager,
        traceID: String,
        triggerSource: RecordingAudioSyncTriggerSource,
        localAudioState: RecordingLocalAudioState,
        peerAudioState: RecordingPeerAudioState,
        ledgerState: RecordingUploadLedgerState,
        syncRunID: String?
    ) async -> RecordingUploadStatus? {
        let switchResult = canonicalKernelSwitchResultProvider?()
            ?? CanonicalKernelSwitchConfiguration.runtimeConfigurationFromStoredDefaults().resolve()
        if let transferStatus = await uploadViaCanonicalTransferRuntimeIfEnabled(
            switchResult: switchResult,
            metadata: metadata,
            settings: settings,
            recordingManager: recordingManager,
            traceID: traceID,
            triggerSource: triggerSource,
            localAudioState: localAudioState,
            syncRunID: syncRunID
        ) {
            return transferStatus
        }
        let configuration = switchResult.effectiveConfiguration.audioUploadRuntimeConfiguration
        guard configuration.mode == .canonicalUploadWithLegacyFallback
                || configuration.mode == .testTransportUpload else {
            return nil
        }
        guard !switchResult.isBlocked else {
            recordCanonicalAudioUploadRuntimeEvent(
                stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: "kernelSwitchBlocked"
            )
            return nil
        }
        let productionPortInjection = IPhoneCanonicalProductionPortFactory.make(
            result: switchResult,
            productionRootURL: recordingManager.studyLibraryStore.libraryRootURL
        )
        guard productionPortInjection.audioUploadExecutorEnabled else {
            recordCanonicalAudioUploadRuntimeEvent(
                stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: productionPortInjection.diagnosticsSummary
            )
            return nil
        }

        let source: IPhoneCanonicalAudioUploadFileSource
        do {
            source = try await IPhoneCanonicalAudioUploadFileSource(
                metadata: metadata,
                audioFileStore: recordingManager.audioFileStore,
                preferredChunkSize: configuration.policy.chunkSize,
                precomputedSignature: localAudioState.signature
            )
        } catch {
            recordCanonicalAudioUploadRuntimeEvent(
                stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: "sourceUnavailable"
            )
            return nil
        }

        let trigger = Self.canonicalAudioUploadTrigger(from: triggerSource)
        let existingRetryRecord = await canonicalAudioUploadJobStore.record(for: metadata.id)
        let retryTruth = CanonicalAudioUploadRetryTruth(
            hasExistingEligibleRetry: await canonicalAudioUploadJobStore.hasEligibleRetry(objectID: metadata.id, now: Date()),
            retryPending: existingRetryRecord != nil,
            canFreshCreateJob: triggerSource.canCreateUploadJob
        )
        let candidate = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: metadata.id,
            localTruth: CanonicalAudioUploadLocalTruth.available(
                hash: source.contentHash,
                byteSize: source.byteSize,
                logicalPathToken: metadata.relativeAudioPath,
                sourceDeviceID: settings.deviceID
            ),
            peerTruth: Self.canonicalPeerAudioTruth(from: peerAudioState),
            ledgerTruth: Self.canonicalLedgerTruth(from: ledgerState),
            retryTruth: retryTruth,
            trigger: trigger
        )
        let stateTruth = CanonicalUploadStateTruth.fromCutoverCandidate(
            candidate,
            canonicalJobState: existingRetryRecord?.state,
            canonicalJobAttemptCount: existingRetryRecord?.attemptCount ?? 0
        )
        let stateReport = stateTruth.reconcile()
        for diagnostic in stateReport.diagnostics.prefix(16) {
            recordCanonicalAudioUploadRuntimeEvent(
                stage: diagnostic.kind.rawValue,
                metadata: metadata,
                traceID: traceID,
                result: diagnostic.diagnosticsSummary
            )
        }
        let statusProjection = CanonicalUploadStatusProjectionResult(report: stateReport)
        for diagnostic in statusProjection.diagnostics.suffix(1) {
            recordCanonicalAudioUploadRuntimeEvent(
                stage: diagnostic.kind.rawValue,
                metadata: metadata,
                traceID: traceID,
                result: diagnostic.diagnosticsSummary
            )
        }
        let port = canonicalAudioUploadRuntimePort(
            settings: settings,
            configuration: configuration,
            switchResult: switchResult
        )
        let cutoverExecutor = IPhoneAudioUploadCutoverExecutor(
            source: source,
            uploadPort: port,
            jobStore: canonicalAudioUploadJobStore,
            runtimeExecutor: canonicalAudioUploadExecutor
        )
        let cutoverResult = await cutoverExecutor.execute(
            CanonicalAudioUploadCutoverExecutionRequest(
                candidate: candidate,
                configuration: configuration,
                syncRunID: syncRunID,
                nodeRole: .iPhone,
                legacyFallbackAvailable: configuration.policy.legacyFallbackEnabled
            )
        )
        let result = cutoverResult.runtimeResult ?? CanonicalAudioUploadRuntimeResult(
            mode: configuration.mode,
            outcome: cutoverResult.outcome,
            objectID: candidate.objectID,
            legacyFallbackReason: cutoverResult.failure?.reason,
            diagnostics: cutoverResult.diagnostics
        )
        for diagnostic in result.diagnostics.prefix(64) {
            recordCanonicalAudioUploadRuntimeEvent(
                stage: diagnostic.kind.rawValue,
                metadata: metadata,
                traceID: traceID,
                result: diagnostic.diagnosticsSummary
            )
        }
        if cutoverResult.failure?.kind == .securityFailure {
            return await failCanonicalAudioUpload(
                metadata: metadata,
                recordingManager: recordingManager,
                traceID: traceID,
                result: result,
                phase: "fatalFailed",
                description: cutoverResult.failure?.reason ?? "canonical_audio_upload_security_failure"
            )
        }
        if Self.shouldUseLegacyUploadForCanonicalDisabledPort(result) {
            recordCanonicalAudioUploadRuntimeEvent(
                stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: result.legacyFallbackReason ?? "iphoneProductionUploadDisabled"
            )
            return nil
        }

        switch result.outcome {
        case .legacyFallback:
            recordCanonicalAudioUploadRuntimeEvent(
                stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: result.legacyFallbackReason ?? "legacyFallback"
            )
            return nil
        case .uploaded, .noOp:
            if result.outcome == .uploaded, !cutoverResult.postcondition.finalizeProofAccepted {
                recordCanonicalAudioUploadRuntimeEvent(
                    stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
                    metadata: metadata,
                    traceID: traceID,
                    result: result,
                    reason: "canonical_audio_upload_finalize_proof_missing"
                )
                return nil
            }
            if result.outcome == .noOp, !cutoverResult.postcondition.peerSameHashAndByteSizeProofAccepted {
                recordCanonicalAudioUploadRuntimeEvent(
                    stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
                    metadata: metadata,
                    traceID: traceID,
                    result: result,
                    reason: "canonical_audio_upload_noop_peer_proof_missing"
                )
                return nil
            }
            let legacyResult = RecordingUploadResult(
                recordingID: metadata.id,
                metadataFileName: nil,
                audioFileName: metadata.relativeAudioPath,
                metadataDisposition: "canonicalMetadataLegacyReadable",
                audioDisposition: result.outcome == .noOp ? "canonicalAudioNoOpPeerMatches" : "canonicalAudioFinalizeVerified"
            )
            let completedJob = try? markUploadSucceeded(
                recordingID: metadata.id,
                result: legacyResult,
                now: Date(),
                proofSignature: localAudioState.signature
            )
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .uploaded)
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: 1,
                confirmedBytes: result.confirmedBytes > 0 ? result.confirmedBytes : source.byteSize,
                totalBytes: source.byteSize,
                phase: "completed",
                description: "上传完成"
            )
            if let completedJob {
                _ = await produceLocalUploadSucceededFactIfPresent(
                    recordingID: metadata.id,
                    job: completedJob
                )
            }
            let latestMetadata = latestUploadedMetadata(
                recordingID: metadata.id,
                fallback: metadata,
                recordingManager: recordingManager
            )
            setActiveStatus(nil, for: latestMetadata, job: completedJob ?? (try? jobStore.loadJob(recordingID: latestMetadata.id)))
            updateErrorMessage(nil, for: metadata.id)
            return .uploaded
        case .diagnosticsOnly, .noCommit:
            recordCanonicalAudioUploadRuntimeEvent(
                stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: result,
                reason: result.outcome.rawValue
            )
            return nil
        case .deferred:
            recordCanonicalAudioUploadRuntimeEvent(
                stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: result,
                reason: "deferred"
            )
            return nil
        case .retryScheduled:
            recordCanonicalAudioUploadRuntimeEvent(
                stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: result,
                reason: "retryScheduled"
            )
            return nil
        case .conflict:
            recordCanonicalAudioUploadRuntimeEvent(
                stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: result,
                reason: "conflict"
            )
            return nil
        case .blocked, .failed:
            recordCanonicalAudioUploadRuntimeEvent(
                stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: result,
                reason: result.legacyFallbackReason ?? result.outcome.rawValue
            )
            return nil
        }
    }

    private func uploadViaCanonicalTransferRuntimeIfEnabled(
        switchResult: CanonicalKernelSwitchResult,
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        recordingManager: RecordingManager,
        traceID: String,
        triggerSource: RecordingAudioSyncTriggerSource,
        localAudioState: RecordingLocalAudioState,
        syncRunID: String?
    ) async -> RecordingUploadStatus? {
        let configuration = switchResult.effectiveConfiguration.transferRuntimeConfiguration
        guard configuration.mode == .canonicalTransferWithLegacyFallback else {
            return nil
        }
        guard switchResult.effectiveMode == .canonicalFullSync, !switchResult.isBlocked else {
            recordCanonicalAudioUploadRuntimeEvent(
                stage: "canonicalTransferRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: "kernelSwitchBlocked"
            )
            return nil
        }

        let retryRuntime = CanonicalTransferRetryRuntime(policy: configuration.policy.retryPolicy)
        if triggerSource.isViewRefreshOnly {
            let evaluation = retryRuntime.evaluate(
                trigger: .viewRefresh,
                job: nil,
                now: Date(),
                statusRouteAvailable: configuration.policy.requireExistingSecureUploadRoutes
            )
            recordCanonicalTransferRuntimeEvent(
                stage: "canonicalTransferRetryBlocked",
                metadata: metadata,
                traceID: traceID,
                result: evaluation.blockers.map(\.rawValue).joined(separator: "|")
            )
            setActiveStatus(nil, for: metadata)
            updateErrorMessage(nil, for: metadata.id)
            return nil
        }

        if triggerSource == .retryDrainer {
            let existingJob = try? jobStore.loadJob(recordingID: metadata.id)
            let evaluation = retryRuntime.evaluate(
                trigger: .retryDrainer,
                job: Self.canonicalTransferRetryJob(from: existingJob),
                now: Date(),
                statusRouteAvailable: configuration.policy.requireExistingSecureUploadRoutes
            )
            if evaluation.decision == .blocked || evaluation.decision == .noExistingEligibleJob {
                recordCanonicalTransferRuntimeEvent(
                    stage: "canonicalTransferRetryBlocked",
                    metadata: metadata,
                    traceID: traceID,
                    result: evaluation.blockers.map(\.rawValue).joined(separator: "|")
                )
                setActiveStatus(nil, for: metadata, job: existingJob)
                updateErrorMessage(nil, for: metadata.id)
                return nil
            }
        }

        let productionPortInjection = IPhoneCanonicalProductionPortFactory.make(
            result: switchResult,
            productionRootURL: recordingManager.studyLibraryStore.libraryRootURL
        )
        guard productionPortInjection.audioUploadExecutorEnabled else {
            recordCanonicalTransferRuntimeEvent(
                stage: "canonicalTransferRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: productionPortInjection.diagnosticsSummary
            )
            return nil
        }

        let audioSource: IPhoneCanonicalAudioUploadFileSource
        do {
            audioSource = try await IPhoneCanonicalAudioUploadFileSource(
                metadata: metadata,
                audioFileStore: recordingManager.audioFileStore,
                preferredChunkSize: configuration.policy.chunkSize,
                precomputedSignature: localAudioState.signature
            )
        } catch {
            recordCanonicalTransferRuntimeEvent(
                stage: "canonicalTransferRuntimeBlocked",
                metadata: metadata,
                traceID: traceID,
                result: "sourceUnavailable"
            )
            return nil
        }

        let transferSource = IPhoneCanonicalTransferFileSource(source: audioSource)
        let sourceNodeID = CanonicalNodeID("iphone-\(settings.deviceID)")
        let destinationNodeID = CanonicalNodeID("mac-\(settings.deviceID)")
        let port = canonicalTransferRuntimePortFactory(settings, configuration)
        let runtime = CanonicalTransferRuntime(
            configuration: configuration,
            port: port,
            sourceNodeID: sourceNodeID,
            destinationNodeID: destinationNodeID
        )

        setActiveStatus(.uploading, for: metadata)
        updateErrorMessage(nil, for: metadata.id)

        do {
            let uploadJob = try? jobStore.markAttemptStarted(recordingID: metadata.id, now: Date())
            let progress: RecordingUploadProgressHandler = { [weak self] event in
                guard let self else {
                    return
                }

                let updatedJob = try self.jobStore.applyProgress(recordingID: metadata.id, event: event, now: Date())
                Self.recordProgressTrace(event, metadata: metadata, job: updatedJob, traceID: traceID)
                if let progressUpdate = Self.metadataProgressUpdate(for: event, job: updatedJob) {
                    try? recordingManager.updateUploadProgress(
                        recordingID: metadata.id,
                        fraction: progressUpdate.fraction,
                        confirmedBytes: progressUpdate.confirmedBytes,
                        totalBytes: progressUpdate.totalBytes,
                        phase: progressUpdate.phase,
                        description: progressUpdate.description
                    )
                }
            }
            var resumeContext = uploadJob?.resumeContext ?? (try? jobStore.loadJob(recordingID: metadata.id))?.resumeContext
            if let localSignature = localAudioState.signature {
                resumeContext?.audioTotalSHA256 = localSignature.normalizedSHA256
                if let size = localSignature.size {
                    resumeContext?.audioTotalBytes = size
                }
            }
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "canonicalTransferMetadataPreflightStarted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "begin",
                uploadStatus: RecordingUploadStatus.uploading.rawValue,
                ledgerState: uploadJob?.overallState.rawValue,
                jobID: uploadJob?.id,
                httpPath: "/upload-recording-metadata"
            )
            _ = try await uploadClient.uploadMetadataIfNeeded(
                metadata: metadata.updatingUploadStatus(.uploading),
                settings: settings,
                progress: progress,
                resumeContext: resumeContext
            )
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "canonicalTransferMetadataPreflightCompleted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: RecordingUploadStatus.uploading.rawValue,
                ledgerState: (try? jobStore.loadJob(recordingID: metadata.id))?.metadataStage.rawValue,
                jobID: uploadJob?.id,
                httpPath: "/upload-recording-metadata"
            )
            let result = try await runtime.transfer(
                source: transferSource,
                requestedAt: CanonicalTimestamp(Date())
            )
            for diagnostic in result.diagnostics.prefix(64) {
                recordCanonicalTransferRuntimeEvent(
                    stage: diagnostic.kind.rawValue,
                    metadata: metadata,
                    traceID: traceID,
                    result: diagnostic.diagnosticsSummary
                )
            }

            guard result.outcome == .uploaded,
                  let proof = result.finalizeProof,
                  proof.isReceiverAcceptedProof else {
                recordCanonicalTransferRuntimeEvent(
                    stage: "canonicalTransferRuntimeLegacyFallbackUsed",
                    metadata: metadata,
                    traceID: traceID,
                    result: result,
                    reason: "canonical_transfer_finalize_proof_missing"
                )
                return nil
            }

            await produceCanonicalTransferFinalizeProofFact(
                proof,
                producerNodeID: sourceNodeID
            )

            _ = try? jobStore.applyProgress(
                recordingID: metadata.id,
                event: .audioResumableSessionStarted(
                    sessionID: proof.sessionID.rawValue,
                    totalBytes: proof.byteSize,
                    chunkSize: configuration.policy.chunkSize,
                    totalSHA256: proof.contentHash.value,
                    confirmedBytes: result.confirmedBytes
                ),
                now: Date()
            )
            _ = try? jobStore.applyProgress(
                recordingID: metadata.id,
                event: .audioSucceeded(disposition: "canonicalTransferFinalizeVerified"),
                now: Date()
            )
            let legacyResult = RecordingUploadResult(
                recordingID: metadata.id,
                metadataFileName: nil,
                audioFileName: metadata.relativeAudioPath,
                metadataDisposition: "canonicalMetadataLegacyReadable",
                audioDisposition: "canonicalTransferFinalizeVerified"
            )
            let completedJob = try? markUploadSucceeded(
                recordingID: metadata.id,
                result: legacyResult,
                now: Date(),
                proofSignature: RecordingAudioSignature(sha256: proof.contentHash.value, size: proof.byteSize)
            )
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .uploaded)
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: 1,
                confirmedBytes: proof.byteSize,
                totalBytes: proof.byteSize,
                phase: "completed",
                description: "上传完成"
            )
            let latestMetadata = latestUploadedMetadata(
                recordingID: metadata.id,
                fallback: metadata,
                recordingManager: recordingManager
            )
            setActiveStatus(nil, for: latestMetadata, job: completedJob ?? (try? jobStore.loadJob(recordingID: latestMetadata.id)))
            updateErrorMessage(nil, for: metadata.id)
            return .uploaded
        } catch {
            if Self.isCanonicalDisabledUploadPortError(error) {
                recordCanonicalTransferRuntimeEvent(
                    stage: "canonicalTransferRuntimeLegacyFallbackUsed",
                    metadata: metadata,
                    traceID: traceID,
                    result: "iphoneProductionUploadDisabled"
                )
                return nil
            }
            let code = error.localizedDescription.lowercased()
            let isConflict = code.contains("conflict") || code.contains("mismatch")
            let result = CanonicalTransferRuntimeResult(
                mode: configuration.mode,
                outcome: isConflict ? .conflict : .failed,
                objectID: Self.canonicalAudioObjectID(recordingID: metadata.id),
                diagnostics: [
                    CanonicalTransferDiagnosticRecord(
                        kind: isConflict ? .finalizeProofRejected : .runtimeBlocked,
                        objectID: Self.canonicalAudioObjectID(recordingID: metadata.id),
                        redactedDetail: String(error.localizedDescription.prefix(96))
                    )
                ]
            )
            recordCanonicalTransferRuntimeEvent(
                stage: "canonicalTransferRuntimeLegacyFallbackUsed",
                metadata: metadata,
                traceID: traceID,
                result: result,
                reason: isConflict ? "conflict" : "runtimeError"
            )
            return nil
        }
    }

    @discardableResult
    private func produceCanonicalTransferFinalizeProofFact(
        _ proof: CanonicalTransferFinalizeProof,
        producerNodeID: CanonicalNodeID
    ) async -> CanonicalStatusFactMergeResult {
        let fact = CanonicalStatusFact(
            factID: "transfer-finalize-\(Self.safeFactToken(proof.sessionID.rawValue))-\(Self.safeFactToken(proof.objectID.rawValue))",
            objectID: proof.objectID,
            source: .transferFinalizeProof,
            producerNodeID: producerNodeID,
            logicalTime: CanonicalLogicalTime(
                counter: UInt64(max(0, proof.finalizedAt.date.timeIntervalSince1970.rounded())),
                nodeID: producerNodeID
            ),
            proof: CanonicalStatusProof(
                kind: .finalizeProof,
                objectID: proof.objectID,
                hash: proof.contentHash,
                byteSize: proof.byteSize,
                peerNodeID: proof.receiverNodeID,
                finalizeProof: proof,
                observedAt: proof.finalizedAt
            ),
            domain: .audioUpload,
            phase: .completed,
            causality: CanonicalStatusCausality(trigger: .transferFinalize)
        )
        return await produceCanonicalStatusFact(fact)
    }

    @discardableResult
    private func produceLocalUploadSucceededFactIfPresent(
        recordingID: String,
        job: RecordingUploadJob,
        acceptedAt: Date = Date()
    ) async -> CanonicalStatusFactMergeResult? {
        guard let hash = job.audioTotalSHA256?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hash.isEmpty,
              let byteSize = job.audioTotalBytes,
              byteSize > 0 else {
            return nil
        }

        let objectID = Self.canonicalAudioObjectID(recordingID: recordingID)
        let proof = CanonicalTransferFinalizeProof.v930(
            receiverNodeID: CanonicalNodeID("mac-peer"),
            sessionID: CanonicalTransferSessionID("legacy-upload-\(recordingID)"),
            objectID: objectID,
            byteSize: byteSize,
            contentHash: CanonicalHash(hash),
            finalizedAt: CanonicalTimestamp(acceptedAt),
            verified: true
        )
        return await produceCanonicalTransferFinalizeProofFact(
            proof,
            producerNodeID: CanonicalNodeID("iphone-local")
        )
    }

    private static func canonicalTransferRetryJob(from job: RecordingUploadJob?) -> CanonicalTransferRetryJob? {
        guard let job,
              let sessionID = job.resumableSessionID,
              let byteSize = job.audioTotalBytes,
              let totalHash = job.audioTotalSHA256 else {
            return nil
        }
        let state: CanonicalTransferRuntimeState
        switch job.resumableState {
        case .some(.notStarted):
            state = .started
        case .some(.starting):
            state = .started
        case .some(.uploading):
            state = .chunking
        case .some(.paused):
            state = .interrupted
        case .some(.retryableFailed):
            state = .interrupted
        case .some(.fatalFailed):
            state = .failed
        case .some(.finalizing):
            state = .finalizing
        case .some(.completed):
            state = .finalized
        case .none:
            state = job.overallState == .retryableFailed ? .interrupted : .idle
        }
        return CanonicalTransferRetryJob(
            objectID: canonicalAudioObjectID(recordingID: job.recordingID),
            sessionID: CanonicalTransferSessionID(sessionID),
            state: state,
            confirmedBytes: job.audioConfirmedBytes ?? 0,
            byteSize: byteSize,
            hashPrefix: totalHash,
            attemptCount: job.attemptCount,
            maxAttempts: 3,
            nextRetryAfter: job.nextRetryAfter.map(CanonicalTimestamp.init),
            requiresStatusRefreshBeforeResume: true,
            blockers: job.isFatal ? [.security] : []
        )
    }

    private static func safeFactToken(_ value: String) -> String {
        let allowed = value.filter { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
        return String((allowed.isEmpty ? "unknown" : allowed).prefix(48))
    }

    private static func shouldUseLegacyUploadForCanonicalDisabledPort(
        _ result: CanonicalAudioUploadRuntimeResult
    ) -> Bool {
        let diagnosticText = ([result.legacyFallbackReason] + result.diagnostics.map(\.reason) + result.diagnostics.map(\.result))
            .compactMap { $0 }
            .joined(separator: " ")
        return containsCanonicalDisabledUploadReason(diagnosticText)
    }

    private func recordCanonicalTransferRuntimeEvent(
        stage: String,
        metadata: RecordingMetadata,
        traceID: String,
        result: CanonicalTransferRuntimeResult,
        reason: String
    ) {
        recordCanonicalTransferRuntimeEvent(
            stage: stage,
            metadata: metadata,
            traceID: traceID,
            result: "reason=\(reason),outcome=\(result.outcome.rawValue),confirmedBytes=\(result.confirmedBytes)"
        )
    }

    private func recordCanonicalAudioUploadRuntimeEvent(
        stage: String,
        metadata: RecordingMetadata,
        traceID: String,
        result: CanonicalAudioUploadRuntimeResult,
        reason: String
    ) {
        recordCanonicalAudioUploadRuntimeEvent(
            stage: stage,
            metadata: metadata,
            traceID: traceID,
            result: "reason=\(reason),outcome=\(result.outcome.rawValue),startedTransport=\(result.startedTransport),confirmedBytes=\(result.confirmedBytes)"
        )
    }

    private static func isCanonicalDisabledUploadPortError(_ error: Error) -> Bool {
        containsCanonicalDisabledUploadReason("\(error) \(error.localizedDescription)")
    }

    private static func containsCanonicalDisabledUploadReason(_ value: String) -> Bool {
        let text = value.lowercased()
        return text.contains("iphoneproductionuploaddisabled")
            || text.contains("productionmutationattempted")
            || text.contains("productionuploaddisabled")
    }

    private func failCanonicalTransferRuntime(
        metadata: RecordingMetadata,
        recordingManager: RecordingManager,
        traceID: String,
        result: CanonicalTransferRuntimeResult,
        phase: String,
        description: String
    ) async -> RecordingUploadStatus {
        let isFatal = phase == "conflict" || phase == "blocked" || phase == "fatalFailed"
        _ = try? jobStore.markFailure(
            recordingID: metadata.id,
            classification: RecordingUploadFailureClassification(
                code: "canonical_transfer_\(result.outcome.rawValue)",
                message: description,
                isFatal: isFatal
            ),
            retryPolicy: retryPolicy,
            now: Date()
        )
        try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
        try? recordingManager.updateUploadProgress(
            recordingID: metadata.id,
            fraction: nil,
            confirmedBytes: result.confirmedBytes > 0 ? result.confirmedBytes : nil,
            totalBytes: metadata.fileSize > 0 ? metadata.fileSize : nil,
            phase: phase,
            description: description
        )
        setActiveStatus(.failed, for: metadata)
        updateErrorMessage(description, for: metadata.id)
        recordCanonicalTransferRuntimeEvent(
            stage: "canonicalTransferRuntimeFailed",
            metadata: metadata,
            traceID: traceID,
            result: "terminal=\(isFatal),outcome=\(result.outcome.rawValue)"
        )
        return .failed
    }

    private func failCanonicalAudioUpload(
        metadata: RecordingMetadata,
        recordingManager: RecordingManager,
        traceID: String,
        result: CanonicalAudioUploadRuntimeResult,
        phase: String,
        description: String
    ) async -> RecordingUploadStatus {
        let isFatal = phase == "conflict" || phase == "blocked" || phase == "fatalFailed"
        _ = try? jobStore.markFailure(
            recordingID: metadata.id,
            classification: RecordingUploadFailureClassification(
                code: "canonical_audio_upload_\(result.outcome.rawValue)",
                message: description,
                isFatal: isFatal
            ),
            retryPolicy: retryPolicy,
            now: Date()
        )
        try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
        try? recordingManager.updateUploadProgress(
            recordingID: metadata.id,
            fraction: nil,
            confirmedBytes: result.confirmedBytes > 0 ? result.confirmedBytes : nil,
            totalBytes: metadata.fileSize > 0 ? metadata.fileSize : nil,
            phase: phase,
            description: description
        )
        setActiveStatus(.failed, for: metadata)
        updateErrorMessage(description, for: metadata.id)
        recordCanonicalAudioUploadRuntimeEvent(
            stage: "canonicalAudioUploadRuntimeLegacyFallbackUsed",
            metadata: metadata,
            traceID: traceID,
            result: "terminal=\(isFatal),outcome=\(result.outcome.rawValue)"
        )
        return .failed
    }

    private func recordCanonicalAudioUploadRuntimeEvent(
        stage: String,
        metadata: RecordingMetadata,
        traceID: String,
        result: String
    ) {
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: stage,
            traceID: traceID,
            recordingID: metadata.id,
            eventResult: "canonical",
            reasonCode: String(result.prefix(96)),
            uploadStatus: metadata.uploadStatus
        )
    }

    private func recordCanonicalTransferRuntimeEvent(
        stage: String,
        metadata: RecordingMetadata,
        traceID: String,
        result: String
    ) {
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: stage,
            traceID: traceID,
            recordingID: metadata.id,
            eventResult: "canonicalTransfer",
            reasonCode: String(result.prefix(96)),
            uploadStatus: metadata.uploadStatus
        )
    }

    func retryQueue() -> RecordingUploadQueue {
        RecordingUploadQueue(jobStore: jobStore, retryPolicy: retryPolicy)
    }

    @discardableResult
    func drainEligibleRetryJobs(
        settings: SecureMacConnectionSnapshot,
        recordingManager: RecordingManager,
        now: Date = Date(),
        syncRunID: String? = nil
    ) async -> [String] {
        let drainerTraceID = UploadFlightRecorder.makeTraceID()
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "retryDrainerStarted",
            traceID: drainerTraceID,
            eventResult: "begin",
            reasonCode: "upload_ledger"
        )
        _ = try? jobStore.recoverStaleInProgressJobs(now: now)
        let queue = retryQueue()
        let jobs: [RecordingUploadJob]
        do {
            jobs = try queue.retryableJobs(now: now)
        } catch {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "retryJobFailed",
                traceID: drainerTraceID,
                eventResult: "fail",
                reasonCode: "retry_ledger_read_failed",
                safeErrorMessage: error.localizedDescription
            )
            return []
        }

        var drainedRecordingIDs: [String] = []
        var nextRetryAfter: Date?
        for job in jobs {
            let traceID = UploadFlightRecorder.traceID(forRecordingID: job.recordingID) ?? UploadFlightRecorder.makeTraceID()
            guard uploadTasks[job.recordingID] == nil else {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "retryJobSkippedBackoff",
                    traceID: traceID,
                    recordingID: job.recordingID,
                    eventResult: "skip",
                    reasonCode: "active_upload_exists",
                    ledgerState: job.overallState.rawValue,
                    jobID: job.id
                )
                continue
            }

            guard queue.isEligible(job, now: now) else {
                nextRetryAfter = [nextRetryAfter, job.nextRetryAfter].compactMap { $0 }.min()
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "retryJobSkippedBackoff",
                    traceID: traceID,
                    recordingID: job.recordingID,
                    eventResult: "skip",
                    reasonCode: "backoff_not_elapsed",
                    ledgerState: job.overallState.rawValue,
                    jobID: job.id
                )
                continue
            }

            guard let metadata = recordingManager.recordings.first(where: { $0.id == job.recordingID })
                    ?? (try? recordingManager.audioFileStore.loadMetadata(id: job.recordingID)) else {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "retryJobFailed",
                    traceID: traceID,
                    recordingID: job.recordingID,
                    eventResult: "fail",
                    reasonCode: "metadata_missing",
                    ledgerState: job.overallState.rawValue,
                    jobID: job.id
                )
                continue
            }

            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "retryJobEligible",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus,
                ledgerState: job.overallState.rawValue,
                jobID: job.id
            )
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "retryJobStarted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "begin",
                uploadStatus: metadata.uploadStatus,
                ledgerState: job.overallState.rawValue,
                jobID: job.id
            )
            let status = await uploadAndWait(
                metadata: metadata,
                settings: settings,
                recordingManager: recordingManager,
                traceID: traceID,
                triggerSource: .retryDrainer,
                peerAudioState: .unknown,
                transferJobState: .none,
                syncRunID: syncRunID
            )
            drainedRecordingIDs.append(metadata.id)
            if status == .uploaded {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "retryJobCompleted",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "success",
                    uploadStatus: RecordingUploadStatus.uploaded.rawValue
                )
            }
        }

        if let nextRetryAfter {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "retryDrainerScheduled",
                traceID: drainerTraceID,
                eventResult: "scheduled",
                reasonCode: "nextRetryAfter",
                safeErrorMessage: "nextRetryAfter=\(nextRetryAfter.timeIntervalSince1970)"
            )
        }

        return drainedRecordingIDs
    }

    private static func audioObjectID(recordingID: String) -> String {
        "recordingAudio:\(recordingID)"
    }

    private static func canonicalAudioObjectID(recordingID: String) -> CanonicalObjectID {
        CanonicalObjectID(audioObjectID(recordingID: recordingID))
    }

    private static func defaultCanonicalAudioUploadLedgerURL(jobStore: RecordingUploadJobStore) -> URL? {
        try? jobStore.ledgerURL()
            .deletingLastPathComponent()
            .appendingPathComponent("canonical-audio-upload-runtime-ledger", isDirectory: false)
            .appendingPathExtension("json")
            .standardizedFileURL
    }

    private static func canonicalAudioUploadTrigger(from triggerSource: RecordingAudioSyncTriggerSource) -> CanonicalAudioUploadTriggerSource {
        switch triggerSource {
        case .manualUploadButton:
            return .manualUploadButton
        case .retryDrainer:
            return .retryDrainer
        case .manualSyncIPhone:
            return .manualSyncIPhone
        case .manualSyncMacHint:
            return .manualSyncMacHint
        case .periodicSync:
            return .periodicSync
        case .appActivationRefresh:
            return .appActivationRefresh
        case .folderViewRefresh, .recordingListRefresh, .studyLibraryRefresh:
            return .viewRefresh
        }
    }

    private static func canonicalPeerAudioTruth(from state: RecordingPeerAudioState) -> CanonicalAudioUploadPeerTruth {
        switch state {
        case .unknown:
            return CanonicalAudioUploadPeerTruth(state: .unknown, diagnosticsSummary: "peerUnknown")
        case .missing:
            return CanonicalAudioUploadPeerTruth(state: .missing, diagnosticsSummary: "peerMissing")
        case .metadataOnly:
            return CanonicalAudioUploadPeerTruth(
                state: .metadataOnly,
                metadataUploaded: true,
                diagnosticsSummary: "peerMetadataOnly"
            )
        case .available(let signature):
            let contentHash = signature.normalizedSHA256.map { CanonicalHash($0) }
            return CanonicalAudioUploadPeerTruth(
                state: .available,
                contentHash: contentHash,
                byteSize: signature.size,
                diagnosticsSummary: "peerAvailable"
            )
        case .different(let signature):
            let contentHash = signature?.normalizedSHA256.map { CanonicalHash($0) }
            return CanonicalAudioUploadPeerTruth(
                state: .different,
                contentHash: contentHash,
                byteSize: signature?.size,
                diagnosticsSummary: "peerDifferent"
            )
        case .deleted:
            return CanonicalAudioUploadPeerTruth(state: .deleted, diagnosticsSummary: "peerDeleted")
        }
    }

    private static func canonicalLedgerTruth(from state: RecordingUploadLedgerState) -> CanonicalAudioUploadLedgerTruth {
        switch state {
        case .none:
            return CanonicalAudioUploadLedgerTruth()
        case .queued:
            return CanonicalAudioUploadLedgerTruth(phase: .queued)
        case .inFlight:
            return CanonicalAudioUploadLedgerTruth(phase: .inFlight)
        case .finalizing:
            return CanonicalAudioUploadLedgerTruth(phase: .finalizing)
        case .completed(let signature):
            let contentHash = signature?.normalizedSHA256.map { CanonicalHash($0) }
            return CanonicalAudioUploadLedgerTruth(
                phase: .completed,
                contentHash: contentHash,
                byteSize: signature?.size,
                uiUploaded: true
            )
        case .failed:
            return CanonicalAudioUploadLedgerTruth(phase: .failed)
        case .retryPending:
            return CanonicalAudioUploadLedgerTruth(phase: .retryPending)
        case .fatalFailed:
            return CanonicalAudioUploadLedgerTruth(phase: .fatalFailed)
        }
    }

    private struct LocalAudioDecisionOutcome {
        var state: RecordingLocalAudioState
        var hashDurationMs: Int
    }

    private func localAudioDecisionState(for metadata: RecordingMetadata, traceID: String?) async -> LocalAudioDecisionOutcome {
        let audioURL: URL
        do {
            audioURL = try jobStore.audioURL(for: metadata)
        } catch {
            return LocalAudioDecisionOutcome(
                state: .unreadable(reason: error.localizedDescription),
                hashDurationMs: 0
            )
        }

        let cacheDirectoryURL: URL
        do {
            cacheDirectoryURL = try jobStore.canonicalChecksumCacheDirectoryURL()
        } catch {
            return LocalAudioDecisionOutcome(
                state: .unreadable(reason: error.localizedDescription),
                hashDurationMs: 0
            )
        }
        let fallbackSize = metadata.fileSize > 0 ? metadata.fileSize : nil
        let relativeAudioPath = metadata.relativeAudioPath
        let result = await Self.resolveLocalAudioSignature(
            audioURL: audioURL,
            cacheDirectoryURL: cacheDirectoryURL,
            checksumRuntime: canonicalChecksumRuntime,
            relativeAudioPath: relativeAudioPath,
            fallbackSize: fallbackSize
        )

        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "localAudioSignatureResolved",
            traceID: traceID,
            recordingID: metadata.id,
            eventResult: result.state,
            reasonCode: result.cacheState,
            uploadStatus: metadata.uploadStatus,
            fileExists: result.state != "missing",
            fileSize: result.size,
            resolvedRelativePathToken: metadata.relativeAudioPath,
            safeErrorMessage: "hashDurationMs=\(result.hashDurationMs);background=true;cache=\(result.cacheState)"
        )

        switch result.state {
        case "available":
            return LocalAudioDecisionOutcome(
                state: .available(RecordingAudioSignature(sha256: result.sha256, size: result.size ?? fallbackSize)),
                hashDurationMs: result.hashDurationMs
            )
        case "missing":
            return LocalAudioDecisionOutcome(state: .missing, hashDurationMs: result.hashDurationMs)
        default:
            return LocalAudioDecisionOutcome(
                state: .unreadable(reason: result.reason ?? "local_audio_signature_failed"),
                hashDurationMs: result.hashDurationMs
            )
        }
    }

    private nonisolated static func resolveLocalAudioSignature(
        audioURL: URL,
        cacheDirectoryURL: URL,
        checksumRuntime: CanonicalChecksumRuntime,
        relativeAudioPath: String,
        fallbackSize: Int64?
    ) async -> (state: String, sha256: String?, size: Int64?, reason: String?, hashDurationMs: Int, cacheState: String) {
        let existsStartedAt = Date()
        let exists = await Task.detached(priority: .utility) {
            FileManager.default.fileExists(atPath: audioURL.path)
        }.value
        let existsDurationMs = CanonicalPerfLog.elapsedMs(since: existsStartedAt)
        if existsDurationMs > 0 {
            Task { @MainActor in
                ConnectionDiagnosticsStore.shared.recordPerfLog(
                    CanonicalPerfLog.subphaseMeasured(
                        operation: .upload,
                        subphase: .waitBackgroundMs,
                        durationMs: existsDurationMs,
                        result: "localAudioExists"
                    )
                )
            }
        }
        guard exists else {
            return ("missing", nil, nil, nil, 0, "notApplicable")
        }

        let result = await checksumRuntime.checksum(
            fileURL: audioURL,
            logicalToken: relativeAudioPath,
            nodeRole: .iPhone,
            cacheDirectoryURL: cacheDirectoryURL
        )
        let durationMs = result.hashDurationMs
        let cacheState = result.event.rawValue
        guard let checksum = result.sha256 else {
            return (
                "unreadable",
                nil,
                fallbackSize,
                result.failure?.rawValue ?? "local_audio_signature_failed",
                durationMs,
                cacheState
            )
        }
        return ("available", checksum, result.byteSize > 0 ? result.byteSize : fallbackSize, nil, durationMs, cacheState)
    }

    private func uploadLedgerState(_ job: RecordingUploadJob?) -> RecordingUploadLedgerState {
        guard let job else {
            return .none
        }
        if job.overallState == .fatalFailed {
            return .fatalFailed(reason: job.lastErrorCode ?? job.lastErrorMessage)
        }
        if job.overallState == .retryableFailed {
            return .retryPending
        }
        if job.overallState == .succeeded || job.audioStage == .succeeded {
            return .completed(RecordingAudioSignature(sha256: job.audioTotalSHA256, size: job.audioTotalBytes))
        }
        if job.audioStage == .inProgress || job.overallState == .inProgress {
            if job.resumableState == .finalizing {
                return .finalizing
            }
            return .inFlight
        }
        return .none
    }

    private static func isActiveUploadJob(_ job: RecordingUploadJob) -> Bool {
        if job.overallState == .inProgress
            || job.metadataStage == .inProgress
            || job.audioStage == .inProgress {
            return true
        }
        switch job.resumableState {
        case .starting, .uploading, .finalizing:
            return true
        case .notStarted, .paused, .retryableFailed, .completed, .fatalFailed, .none:
            return false
        }
    }

    private func recordDecision(
        _ decision: RecordingAudioUploadDecision,
        metadata: RecordingMetadata,
        traceID: String,
        triggerSource: RecordingAudioSyncTriggerSource,
        localAudioState: RecordingLocalAudioState,
        peerAudioState: RecordingPeerAudioState,
        transferJobState: RecordingTransferJobState,
        ledgerState: RecordingUploadLedgerState,
        syncRunID: String?
    ) {
        let summary = RecordingAudioUploadDecisionDiagnostics.result(
            recordingID: metadata.id,
            objectID: Self.audioObjectID(recordingID: metadata.id),
            logicalPathToken: metadata.relativeAudioPath,
            triggerSource: triggerSource,
            decision: decision,
            localAudioState: localAudioState,
            peerAudioState: peerAudioState,
            transferJobState: transferJobState,
            ledgerState: ledgerState
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "uploadStateEvaluated",
            traceID: traceID,
            recordingID: metadata.id,
            eventResult: decision.kind.rawValue,
            reasonCode: decision.reasonCode,
            uploadStatus: metadata.uploadStatus,
            ledgerState: ledgerState.summary,
            resolvedRelativePathToken: metadata.relativeAudioPath,
            safeErrorMessage: summary
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "uploadDecisionComputed",
            traceID: traceID,
            recordingID: metadata.id,
            eventResult: decision.kind.rawValue,
            reasonCode: decision.reasonCode,
            uploadStatus: metadata.uploadStatus,
            ledgerState: ledgerState.summary,
            resolvedRelativePathToken: metadata.relativeAudioPath,
            safeErrorMessage: summary
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: decision.diagnosticStage,
            traceID: traceID,
            recordingID: metadata.id,
            eventResult: decision.kind.rawValue,
            reasonCode: decision.reasonCode,
            uploadStatus: metadata.uploadStatus,
            ledgerState: ledgerState.summary,
            resolvedRelativePathToken: metadata.relativeAudioPath,
            safeErrorMessage: summary
        )
        if decision.reasonCode == "peer_audio_conflict" {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "audioConflictDetected",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: decision.kind.rawValue,
                reasonCode: decision.reasonCode,
                uploadStatus: metadata.uploadStatus,
                safeErrorMessage: summary
            )
        }
        if decision.reasonCode == "peer_audio_unknown_deferred" {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "peerAudioUnknownDeferred",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: decision.kind.rawValue,
                reasonCode: decision.reasonCode,
                uploadStatus: metadata.uploadStatus,
                safeErrorMessage: summary
            )
        }
        _ = syncRunID
    }

    private struct MetadataProgressUpdate {
        let fraction: Double?
        let confirmedBytes: Int64?
        let totalBytes: Int64?
        let phase: String?
        let description: String?
    }

    private static func metadataProgressUpdate(
        for event: RecordingUploadProgressEvent,
        job: RecordingUploadJob
    ) -> MetadataProgressUpdate? {
        switch event {
        case .audioResumableSessionStarted:
            return MetadataProgressUpdate(
                fraction: job.currentProgressFraction,
                confirmedBytes: job.audioConfirmedBytes,
                totalBytes: job.audioTotalBytes,
                phase: job.resumableState?.rawValue ?? "uploading",
                description: Self.progressDescription(for: job)
            )
        case .audioResumableProgress:
            return MetadataProgressUpdate(
                fraction: job.currentProgressFraction,
                confirmedBytes: job.audioConfirmedBytes,
                totalBytes: job.audioTotalBytes,
                phase: "uploading",
                description: Self.progressDescription(for: job)
            )
        case .audioResumableFinalizing:
            return MetadataProgressUpdate(
                fraction: job.currentProgressFraction,
                confirmedBytes: job.audioConfirmedBytes,
                totalBytes: job.audioTotalBytes,
                phase: "finalizing",
                description: "正在完成上传"
            )
        case .audioSucceeded:
            return MetadataProgressUpdate(
                fraction: 1,
                confirmedBytes: job.audioTotalBytes,
                totalBytes: job.audioTotalBytes,
                phase: "completed",
                description: "上传完成"
            )
        case .metadataStarted, .metadataSucceeded, .audioStarted:
            return nil
        }
    }

    private static func recordProgressTrace(
        _ event: RecordingUploadProgressEvent,
        metadata: RecordingMetadata,
        job: RecordingUploadJob,
        traceID: String
    ) {
        switch event {
        case .metadataStarted:
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "metadataUploadStarted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "begin",
                uploadStatus: metadata.uploadStatus,
                ledgerState: job.metadataStage.rawValue,
                jobID: job.id
            )
        case .metadataSucceeded(let disposition):
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "metadataUploadCompleted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                reasonCode: disposition,
                uploadStatus: metadata.uploadStatus,
                ledgerState: job.metadataStage.rawValue,
                jobID: job.id
            )
        case .audioStarted:
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "audioUploadStarted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "begin",
                uploadStatus: metadata.uploadStatus,
                ledgerState: job.audioStage.rawValue,
                jobID: job.id
            )
        case .audioResumableSessionStarted(let sessionID, let totalBytes, let chunkSize, _, let confirmedBytes):
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "resumableStartCompleted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus,
                ledgerState: job.resumableState?.rawValue,
                jobID: job.id,
                sessionID: sessionID,
                chunkLength: chunkSize,
                confirmedBytes: confirmedBytes,
                totalBytes: totalBytes
            )
        case .audioResumableProgress(let sessionID, let confirmedBytes, let totalBytes, let nextOffset):
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "resumableChunkCompleted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus,
                ledgerState: job.resumableState?.rawValue,
                jobID: job.id,
                sessionID: sessionID,
                chunkOffset: nextOffset,
                confirmedBytes: confirmedBytes,
                totalBytes: totalBytes
            )
        case .audioResumableFinalizing(let sessionID, let confirmedBytes, let totalBytes):
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "resumableFinalizeStarted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "begin",
                uploadStatus: metadata.uploadStatus,
                ledgerState: job.resumableState?.rawValue,
                jobID: job.id,
                sessionID: sessionID,
                confirmedBytes: confirmedBytes,
                totalBytes: totalBytes
            )
        case .audioSucceeded(let disposition):
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "audioUploadCompleted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                reasonCode: disposition,
                uploadStatus: metadata.uploadStatus,
                ledgerState: job.audioStage.rawValue,
                jobID: job.id,
                confirmedBytes: job.audioConfirmedBytes,
                totalBytes: job.audioTotalBytes
            )
        }
    }

    private static func progressDescription(for job: RecordingUploadJob) -> String? {
        guard let confirmedBytes = job.audioConfirmedBytes,
              let totalBytes = job.audioTotalBytes,
              totalBytes > 0 else {
            return nil
        }

        let percent = Int((Double(confirmedBytes) / Double(totalBytes) * 100).rounded())
        return "上传中 \(min(max(percent, 0), 100))%"
    }
}

nonisolated enum RecordingUploadJobStageState: String, Codable, Equatable {
    case pending
    case inProgress
    case succeeded
    case failed
}

nonisolated enum RecordingUploadJobOverallState: String, Codable, Equatable {
    case pending
    case inProgress
    case succeeded
    case retryableFailed
    case fatalFailed
}

nonisolated enum RecordingUploadJobDisposition: String, Codable, Equatable {
    case none
    case acceptedNew
    case acceptedExisting

    init(serverValue: String?) {
        switch serverValue {
        case "acceptedNew":
            self = .acceptedNew
        case "acceptedExisting":
            self = .acceptedExisting
        default:
            self = .none
        }
    }
}

nonisolated struct RecordingUploadJob: Codable, Equatable, Identifiable {
    var id: String { recordingID }

    let recordingID: String
    var createdAt: Date
    var updatedAt: Date
    var metadataStage: RecordingUploadJobStageState
    var audioStage: RecordingUploadJobStageState
    var overallState: RecordingUploadJobOverallState
    var metadataDisposition: RecordingUploadJobDisposition
    var audioDisposition: RecordingUploadJobDisposition
    var attemptCount: Int
    var lastAttemptAt: Date?
    var nextRetryAfter: Date?
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var isFatal: Bool
    var localMetadataPath: String
    var localAudioPath: String
    var targetDeviceID: String?
    var targetMacName: String?
    var resumableSessionID: String? = nil
    var uploadMode: RecordingUploadMode? = nil
    var audioTotalBytes: Int64? = nil
    var audioConfirmedBytes: Int64? = nil
    var audioChunkSize: Int? = nil
    var audioTotalSHA256: String? = nil
    var audioNextOffset: Int64? = nil
    var audioChunkCount: Int? = nil
    var audioCompletedChunkCount: Int? = nil
    var currentProgressFraction: Double? = nil
    var lastProgressAt: Date? = nil
    var resumableState: RecordingResumableUploadState? = nil
    var lastConfirmedByMacAt: Date? = nil
    var lastSessionStatusError: String? = nil

    var isRetryable: Bool {
        overallState == .retryableFailed && !isFatal
    }

    var resumeContext: RecordingUploadResumeContext {
        RecordingUploadResumeContext(
            metadataStage: metadataStage,
            metadataDisposition: metadataDisposition,
            resumableSessionID: resumableSessionID,
            audioConfirmedBytes: audioConfirmedBytes,
            audioTotalBytes: audioTotalBytes,
            audioChunkSize: audioChunkSize,
            audioTotalSHA256: audioTotalSHA256
        )
    }

    static func make(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        now: Date
    ) -> RecordingUploadJob {
        RecordingUploadJob(
            recordingID: metadata.id,
            createdAt: now,
            updatedAt: now,
            metadataStage: .pending,
            audioStage: .pending,
            overallState: .pending,
            metadataDisposition: .none,
            audioDisposition: .none,
            attemptCount: 0,
            lastAttemptAt: nil,
            nextRetryAfter: nil,
            lastErrorCode: nil,
            lastErrorMessage: nil,
            isFatal: false,
            localMetadataPath: metadata.relativeMetadataPath,
            localAudioPath: metadata.relativeAudioPath,
            targetDeviceID: settings.deviceID,
            targetMacName: settings.macName.isEmpty ? nil : settings.macName
        )
    }
}

nonisolated struct RecordingUploadJobLedger: Codable, Equatable {
    static let currentVersion = 2

    var version: Int
    var jobs: [RecordingUploadJob]

    static var empty: RecordingUploadJobLedger {
        RecordingUploadJobLedger(version: currentVersion, jobs: [])
    }
}

struct RecordingUploadFailureClassification: Equatable {
    let code: String
    let message: String
    let isFatal: Bool

    static func classify(_ error: Error) -> RecordingUploadFailureClassification {
        if let uploadError = error as? RecordingUploadError {
            switch uploadError {
            case .metadataUploadFailed(let reason):
                return RecordingUploadFailureClassification(
                    code: reason.contains("recording_metadata_conflict") ? "recording_metadata_conflict" : "metadata_upload_failed",
                    message: uploadError.localizedDescription,
                    isFatal: reason.contains("recording_metadata_conflict")
                )
            case .audioUploadFailed(let reason):
                return RecordingUploadFailureClassification(
                    code: reason.contains("recording_audio_conflict") ? "recording_audio_conflict" : "audio_upload_failed",
                    message: uploadError.localizedDescription,
                    isFatal: reason.contains("recording_audio_conflict")
                )
            case .notPaired:
                return RecordingUploadFailureClassification(code: "not_paired", message: uploadError.localizedDescription, isFatal: false)
            case .audioFileMissing:
                return RecordingUploadFailureClassification(code: "audio_file_missing", message: uploadError.localizedDescription, isFatal: true)
            case .fileTooLarge:
                return RecordingUploadFailureClassification(code: "file_too_large", message: uploadError.localizedDescription, isFatal: true)
            case .macRejected(let reason):
                let isFatal = reason.contains("conflict")
                return RecordingUploadFailureClassification(code: isFatal ? reason : "mac_rejected", message: uploadError.localizedDescription, isFatal: isFatal)
            case .networkFailed:
                return RecordingUploadFailureClassification(code: "network_failed", message: uploadError.localizedDescription, isFatal: false)
            }
        }

        let message = error.localizedDescription
        let isMetadataConflict = message.contains("recording_metadata_conflict")
        let isAudioConflict = message.contains("recording_audio_conflict")
        if isMetadataConflict || isAudioConflict {
            return RecordingUploadFailureClassification(
                code: isMetadataConflict ? "recording_metadata_conflict" : "recording_audio_conflict",
                message: message,
                isFatal: true
            )
        }

        return RecordingUploadFailureClassification(code: "temporary_upload_failed", message: message, isFatal: false)
    }
}

struct RecordingUploadRetryPolicy: Equatable {
    nonisolated static let standard = RecordingUploadRetryPolicy(
        delays: [5, 30, 120],
        maximumDelay: 600,
        maximumAutomaticAttempts: 8
    )

    let delays: [TimeInterval]
    let maximumDelay: TimeInterval
    var maximumAutomaticAttempts: Int = 8

    func delay(forAttemptCount attemptCount: Int) -> TimeInterval {
        guard attemptCount > 0 else {
            return 0
        }

        if attemptCount <= delays.count {
            return min(delays[attemptCount - 1], maximumDelay)
        }

        let extraAttempts = attemptCount - delays.count
        let baseDelay = delays.last ?? maximumDelay
        let multiplier = pow(2.0, Double(extraAttempts))
        return min(baseDelay * multiplier, maximumDelay)
    }

    func nextRetryAfter(attemptCount: Int, now: Date) -> Date {
        now.addingTimeInterval(delay(forAttemptCount: attemptCount))
    }
}

final class RecordingUploadJobStore {
    private let audioFileStore: AudioFileStore
    private let fileManager: FileManager
    private(set) var lastReadError: String?

    init(audioFileStore: AudioFileStore = AudioFileStore(), fileManager: FileManager = .default) {
        self.audioFileStore = audioFileStore
        self.fileManager = fileManager
    }

    var ledgerFileExists: Bool {
        guard let url = try? ledgerURL() else {
            return false
        }
        return fileManager.fileExists(atPath: url.path)
    }

    func ledgerURL() throws -> URL {
        try ledgerDirectory()
            .appendingPathComponent("upload-ledger")
            .appendingPathExtension("json")
            .standardizedFileURL
    }

    func canonicalChecksumCacheDirectoryURL() throws -> URL {
        try audioFileStore.baseDirectory()
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("CanonicalChecksumCache", isDirectory: true)
            .standardizedFileURL
    }

    func loadJobs() throws -> [RecordingUploadJob] {
        try loadLedger().jobs
    }

    func loadJob(recordingID: String) throws -> RecordingUploadJob? {
        try loadLedger().jobs.first { $0.recordingID == recordingID }
    }

    func audioURL(for metadata: RecordingMetadata) throws -> URL {
        try audioFileStore.audioURL(for: metadata)
    }

    func fileExists(at url: URL) -> Bool {
        audioFileStore.fileExists(at: url)
    }

    func fileSize(at url: URL) throws -> Int64 {
        try audioFileStore.fileSize(at: url)
    }

    @discardableResult
    func ensureJob(
        for metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        now: Date
    ) throws -> RecordingUploadJob {
        if let existing = try loadJob(recordingID: metadata.id) {
            let existingTarget = existing.targetDeviceID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentTarget = settings.deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !currentTarget.isEmpty, existingTarget == currentTarget {
                return existing
            }

            // Upload proof is scoped to one paired receiver. A new or legacy-missing
            // target must restart metadata and audio from a clean job so the new Mac
            // cannot inherit another receiver's successful stages/session IDs.
            let replacement = RecordingUploadJob.make(metadata: metadata, settings: settings, now: now)
            try saveJob(replacement)
            return replacement
        }

        let job = RecordingUploadJob.make(metadata: metadata, settings: settings, now: now)
        try saveJob(job)
        return job
    }

    func saveJob(_ job: RecordingUploadJob) throws {
        var ledger = try loadLedger()
        ledger.jobs.removeAll { $0.recordingID == job.recordingID }
        ledger.jobs.append(job)
        ledger.jobs.sort { $0.createdAt > $1.createdAt }
        try saveLedger(ledger)
    }

    @discardableResult
    func markAttemptStarted(recordingID: String, now: Date) throws -> RecordingUploadJob {
        try updateJob(recordingID: recordingID) { job in
            job.updatedAt = now
            job.lastAttemptAt = now
            job.nextRetryAfter = nil
            job.lastErrorCode = nil
            job.lastErrorMessage = nil
            job.isFatal = false
            job.overallState = .inProgress
            job.attemptCount += 1
            if job.uploadMode == .resumableChunks {
                job.resumableState = job.resumableSessionID == nil ? .starting : .uploading
            }

            if job.metadataStage != .succeeded {
                job.metadataStage = .pending
            }
            if job.audioStage != .succeeded {
                job.audioStage = .pending
            }
        }
    }

    @discardableResult
    func applyProgress(
        recordingID: String,
        event: RecordingUploadProgressEvent,
        now: Date
    ) throws -> RecordingUploadJob {
        try updateJob(recordingID: recordingID) { job in
            job.updatedAt = now
            job.overallState = .inProgress
            job.lastErrorCode = nil
            job.lastErrorMessage = nil
            job.nextRetryAfter = nil

            switch event {
            case .metadataStarted:
                if job.metadataStage != .succeeded {
                    job.metadataStage = .inProgress
                }
            case .metadataSucceeded(let disposition):
                job.metadataStage = .succeeded
                job.metadataDisposition = RecordingUploadJobDisposition(serverValue: disposition)
            case .audioStarted:
                job.audioStage = .inProgress
                if job.uploadMode == .resumableChunks {
                    job.resumableState = .uploading
                }
            case .audioResumableSessionStarted(let sessionID, let totalBytes, let chunkSize, let totalSHA256, let confirmedBytes):
                job.uploadMode = .resumableChunks
                job.audioStage = .inProgress
                job.resumableState = .uploading
                job.resumableSessionID = sessionID
                job.audioTotalBytes = totalBytes
                job.audioConfirmedBytes = confirmedBytes
                job.audioChunkSize = chunkSize
                job.audioTotalSHA256 = totalSHA256
                job.audioNextOffset = confirmedBytes
                job.audioChunkCount = Self.chunkCount(totalBytes: totalBytes, chunkSize: chunkSize)
                job.audioCompletedChunkCount = Self.completedChunkCount(confirmedBytes: confirmedBytes, chunkSize: chunkSize)
                job.currentProgressFraction = Self.progressFraction(confirmedBytes: confirmedBytes, totalBytes: totalBytes)
                job.lastProgressAt = now
                job.lastConfirmedByMacAt = now
                job.lastSessionStatusError = nil
            case .audioResumableProgress(let sessionID, let confirmedBytes, let totalBytes, let nextOffset):
                job.uploadMode = .resumableChunks
                job.audioStage = .inProgress
                job.resumableState = .uploading
                job.resumableSessionID = sessionID
                job.audioTotalBytes = totalBytes
                job.audioConfirmedBytes = confirmedBytes
                job.audioNextOffset = nextOffset
                if let chunkSize = job.audioChunkSize {
                    job.audioChunkCount = Self.chunkCount(totalBytes: totalBytes, chunkSize: chunkSize)
                    job.audioCompletedChunkCount = Self.completedChunkCount(confirmedBytes: confirmedBytes, chunkSize: chunkSize)
                }
                job.currentProgressFraction = Self.progressFraction(confirmedBytes: confirmedBytes, totalBytes: totalBytes)
                job.lastProgressAt = now
                job.lastConfirmedByMacAt = now
                job.lastSessionStatusError = nil
            case .audioResumableFinalizing(let sessionID, let confirmedBytes, let totalBytes):
                job.uploadMode = .resumableChunks
                job.audioStage = .inProgress
                job.resumableState = .finalizing
                job.resumableSessionID = sessionID
                job.audioTotalBytes = totalBytes
                job.audioConfirmedBytes = confirmedBytes
                job.audioNextOffset = confirmedBytes
                job.currentProgressFraction = Self.progressFraction(confirmedBytes: confirmedBytes, totalBytes: totalBytes)
                job.lastProgressAt = now
            case .audioSucceeded(let disposition):
                job.audioStage = .succeeded
                job.audioDisposition = RecordingUploadJobDisposition(serverValue: disposition)
                if job.uploadMode == .resumableChunks {
                    job.resumableState = .completed
                    job.currentProgressFraction = 1
                    job.audioConfirmedBytes = job.audioTotalBytes ?? job.audioConfirmedBytes
                    job.audioNextOffset = job.audioTotalBytes ?? job.audioNextOffset
                    job.lastProgressAt = now
                }
            }
        }
    }

    @discardableResult
    func markSucceeded(
        recordingID: String,
        result: RecordingUploadResult,
        now: Date
    ) throws -> RecordingUploadJob {
        try updateJob(recordingID: recordingID) { job in
            job.updatedAt = now
            job.metadataStage = .succeeded
            job.audioStage = .succeeded
            job.overallState = .succeeded
            job.metadataDisposition = RecordingUploadJobDisposition(serverValue: result.metadataDisposition)
            job.audioDisposition = RecordingUploadJobDisposition(serverValue: result.audioDisposition)
            job.nextRetryAfter = nil
            job.lastErrorCode = nil
            job.lastErrorMessage = nil
            job.isFatal = false
            if job.uploadMode == .resumableChunks {
                job.resumableState = .completed
                job.currentProgressFraction = 1
                job.audioConfirmedBytes = job.audioTotalBytes ?? job.audioConfirmedBytes
                job.audioNextOffset = job.audioTotalBytes ?? job.audioNextOffset
                job.lastProgressAt = now
            }
        }
    }

    @discardableResult
    func recordCompletedAudioProof(
        recordingID: String,
        signature: RecordingAudioSignature,
        now: Date
    ) throws -> RecordingUploadJob {
        try updateJob(recordingID: recordingID) { job in
            job.updatedAt = now
            if let hash = signature.normalizedSHA256 {
                job.audioTotalSHA256 = hash
            }
            if let size = signature.size, size > 0 {
                job.audioTotalBytes = size
                job.audioConfirmedBytes = size
                job.audioNextOffset = size
            }
            job.currentProgressFraction = 1
            job.lastProgressAt = now
            job.lastConfirmedByMacAt = now
        }
    }

    @discardableResult
    func markRetryableFailure(
        recordingID: String,
        classification: RecordingUploadFailureClassification,
        retryPolicy: RecordingUploadRetryPolicy,
        now: Date
    ) throws -> RecordingUploadJob {
        try markFailure(recordingID: recordingID, classification: classification, retryPolicy: retryPolicy, now: now)
    }

    @discardableResult
    func markFailure(
        recordingID: String,
        classification: RecordingUploadFailureClassification,
        retryPolicy: RecordingUploadRetryPolicy,
        now: Date
    ) throws -> RecordingUploadJob {
        try updateJob(recordingID: recordingID) { job in
            let failingStage = Self.failingStage(for: classification, job: job)
            job.updatedAt = now
            job.overallState = classification.isFatal ? .fatalFailed : .retryableFailed
            job.isFatal = classification.isFatal
            job.nextRetryAfter = classification.isFatal ? nil : retryPolicy.nextRetryAfter(attemptCount: job.attemptCount, now: now)
            job.lastErrorCode = classification.code
            job.lastErrorMessage = classification.message
            if job.uploadMode == .resumableChunks {
                job.resumableState = classification.isFatal ? .fatalFailed : .retryableFailed
                job.lastSessionStatusError = classification.message
            }

            switch failingStage {
            case .metadata:
                job.metadataStage = .failed
            case .audio:
                job.audioStage = .failed
            }
        }
    }

    @discardableResult
    func recoverStaleInProgressJobs(now: Date) throws -> [RecordingUploadJob] {
        var ledger = try loadLedger()
        var recovered: [RecordingUploadJob] = []

        for index in ledger.jobs.indices {
            guard ledger.jobs[index].overallState == .inProgress
                    || ledger.jobs[index].metadataStage == .inProgress
                    || ledger.jobs[index].audioStage == .inProgress else {
                continue
            }

            if ledger.jobs[index].metadataStage == .inProgress {
                ledger.jobs[index].metadataStage = .failed
            }
            if ledger.jobs[index].audioStage == .inProgress {
                ledger.jobs[index].audioStage = .failed
            }
            if ledger.jobs[index].uploadMode == .resumableChunks,
               let resumableState = ledger.jobs[index].resumableState,
               [.starting, .uploading, .finalizing].contains(resumableState) {
                ledger.jobs[index].resumableState = .paused
            }

            ledger.jobs[index].overallState = .retryableFailed
            ledger.jobs[index].isFatal = false
            ledger.jobs[index].updatedAt = now
            ledger.jobs[index].nextRetryAfter = now
            ledger.jobs[index].lastErrorCode = "upload_interrupted"
            ledger.jobs[index].lastErrorMessage = "上次上传中断，可重试。"
            recovered.append(ledger.jobs[index])
        }

        if !recovered.isEmpty {
            try saveLedger(ledger)
        }

        return recovered
    }

    private enum UploadStage {
        case metadata
        case audio
    }

    private static func failingStage(
        for classification: RecordingUploadFailureClassification,
        job: RecordingUploadJob
    ) -> UploadStage {
        if classification.code.contains("metadata") {
            return .metadata
        }

        if classification.code.contains("audio") {
            return .audio
        }

        if job.metadataStage == .succeeded {
            return .audio
        }

        return .metadata
    }

    private static func progressFraction(confirmedBytes: Int64, totalBytes: Int64) -> Double? {
        guard totalBytes > 0 else {
            return nil
        }

        return min(max(Double(confirmedBytes) / Double(totalBytes), 0), 1)
    }

    private static func chunkCount(totalBytes: Int64, chunkSize: Int) -> Int? {
        guard chunkSize > 0 else {
            return nil
        }

        return Int((totalBytes + Int64(chunkSize) - 1) / Int64(chunkSize))
    }

    private static func completedChunkCount(confirmedBytes: Int64, chunkSize: Int) -> Int? {
        guard chunkSize > 0 else {
            return nil
        }

        return Int(confirmedBytes / Int64(chunkSize))
    }

    private func updateJob(
        recordingID: String,
        update: (inout RecordingUploadJob) -> Void
    ) throws -> RecordingUploadJob {
        var ledger = try loadLedger()
        guard let index = ledger.jobs.firstIndex(where: { $0.recordingID == recordingID }) else {
            throw RecordingUploadJobStoreError.jobNotFound(recordingID)
        }

        update(&ledger.jobs[index])
        let updatedJob = ledger.jobs[index]
        try saveLedger(ledger)
        return updatedJob
    }

    private func ledgerDirectory() throws -> URL {
        let directoryURL = try audioFileStore.baseDirectory()
            .appendingPathComponent("UploadJobs", isDirectory: true)
            .standardizedFileURL

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw RecordingUploadJobStoreError.directoryCreationFailed(directoryURL, error)
        }

        return directoryURL
    }

    private func loadLedger() throws -> RecordingUploadJobLedger {
        let url = try ledgerURL()
        guard fileManager.fileExists(atPath: url.path) else {
            lastReadError = nil
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            let ledger = try Self.decoder.decode(RecordingUploadJobLedger.self, from: data)
            lastReadError = nil
            return RecordingUploadJobLedger(
                version: ledger.version,
                jobs: deduplicatedJobs(ledger.jobs)
            )
        } catch {
            lastReadError = "upload ledger read failed: \(error.localizedDescription)"
            // A damaged retry ledger is derived state. Treat it as empty so a
            // malformed JSON file cannot block every otherwise-valid upload or
            // endanger recording/audio metadata; retain `lastReadError` for
            // diagnostics and leave the corrupt file untouched until a later
            // successful ledger write replaces it atomically.
            return .empty
        }
    }

    private func saveLedger(_ ledger: RecordingUploadJobLedger) throws {
        let url = try ledgerURL()
        let directoryURL = url.deletingLastPathComponent()
        let temporaryURL = directoryURL
            .appendingPathComponent(".upload-ledger-\(UUID().uuidString)")
            .appendingPathExtension("tmp")

        let normalizedLedger = RecordingUploadJobLedger(
            version: RecordingUploadJobLedger.currentVersion,
            jobs: deduplicatedJobs(ledger.jobs)
        )
        let data = try Self.encoder.encode(normalizedLedger)

        do {
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw RecordingUploadJobStoreError.ledgerWriteFailed(url, error)
        }
        NotificationCenter.default.post(name: .recordingUploadJobLedgerDidChange, object: nil)
    }

    private func deduplicatedJobs(_ jobs: [RecordingUploadJob]) -> [RecordingUploadJob] {
        var latestByRecordingID: [String: RecordingUploadJob] = [:]
        for job in jobs {
            let existing = latestByRecordingID[job.recordingID]
            if existing == nil || job.updatedAt >= existing!.updatedAt {
                latestByRecordingID[job.recordingID] = job
            }
        }

        return latestByRecordingID.values.sorted { $0.createdAt > $1.createdAt }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum RecordingUploadJobStoreError: LocalizedError {
    case directoryCreationFailed(URL, Error)
    case ledgerWriteFailed(URL, Error)
    case jobNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .directoryCreationFailed(url, error):
            return "上传任务目录创建失败：\(url.path) - \(error.localizedDescription)"
        case let .ledgerWriteFailed(url, error):
            return "上传任务账本写入失败：\(url.path) - \(error.localizedDescription)"
        case let .jobNotFound(recordingID):
            return "未找到上传任务：\(recordingID)"
        }
    }
}

struct RecordingUploadQueue {
    let jobStore: RecordingUploadJobStore
    let retryPolicy: RecordingUploadRetryPolicy

    func retryableJobs(now: Date = Date()) throws -> [RecordingUploadJob] {
        try jobStore.loadJobs()
            .filter(\.isRetryable)
            .sorted { ($0.nextRetryAfter ?? .distantPast) < ($1.nextRetryAfter ?? .distantPast) }
    }

    func eligibleRetryableJobs(now: Date = Date()) throws -> [RecordingUploadJob] {
        try retryableJobs(now: now).filter { isEligible($0, now: now) }
    }

    func isEligible(_ job: RecordingUploadJob, now: Date = Date()) -> Bool {
        guard job.isRetryable else {
            return false
        }
        guard job.attemptCount < retryPolicy.maximumAutomaticAttempts else {
            return false
        }

        guard let nextRetryAfter = job.nextRetryAfter else {
            return true
        }

        return now >= nextRetryAfter
    }

    func drainEligibleJobs(
        now: Date = Date(),
        perform: (RecordingUploadJob) async -> Void
    ) async throws -> [RecordingUploadJob] {
        let jobs = try eligibleRetryableJobs(now: now)
        for job in jobs {
            await perform(job)
        }
        return jobs
    }
}
