//
//  IPhoneCanonicalProductionApplyPort.swift
//  Rokurics
//
//  Created by Codex on 2026/6/2.
//

import Foundation

actor IPhoneCanonicalProductionApplyPort: CanonicalProductionApplyPort {
    nonisolated let isDryRunOnly: Bool
    nonisolated let metadataApplySupported = true
    nonisolated let generatedArtifactApplySupported = true
    nonisolated let tombstoneApplySupported = true
    nonisolated let conflictRecordSupported = true
    nonisolated let applyPortMode: CanonicalRecordingMetadataApplyPortMode

    private let mode: Mode
    private nonisolated let failureInjection: CanonicalRecordingMetadataCommitFailureInjection
    private nonisolated let rootBoundCore: CanonicalRootBoundMetadataWriteCore?
    private var results: [String: CanonicalProductionApplyResult] = [:]
    private var actionIDsByCheckpointID: [String: String] = [:]
    private var actionIDsByObjectID: [String: [String]] = [:]
    private var tombstones: Set<String> = []
    private var conflicts: Set<String> = []

    init() {
        self.mode = .disabled
        self.isDryRunOnly = true
        self.failureInjection = .none
        self.applyPortMode = .disabled
        self.rootBoundCore = nil
    }

    init(
        fakeInMemory: Bool,
        failureInjection: CanonicalRecordingMetadataCommitFailureInjection = .none
    ) {
        self.mode = fakeInMemory ? .fakeInMemory : .disabled
        self.isDryRunOnly = !fakeInMemory
        self.failureInjection = failureInjection
        self.applyPortMode = fakeInMemory ? .fakeInMemory : .disabled
        self.rootBoundCore = nil
    }

    init(
        testRootURL: URL,
        rootToken: CanonicalRootToken = CanonicalRootToken("iphone-recording-metadata-test-root"),
        fileManager: FileManager = .default,
        failureInjection: CanonicalRecordingMetadataCommitFailureInjection = .none
    ) throws {
        self.mode = .rootBound
        self.isDryRunOnly = false
        self.failureInjection = failureInjection
        self.applyPortMode = .testRootBound
        self.rootBoundCore = try CanonicalRootBoundMetadataWriteCore(
            rootURL: testRootURL,
            rootToken: rootToken,
            mode: .testRootBound,
            fileManager: fileManager
        )
    }

    init(
        productionRootURL: URL,
        rootToken: CanonicalRootToken = CanonicalRootToken("iphone-recording-metadata-production-root"),
        allowProductionRootWrites: Bool = false,
        fileManager: FileManager = .default,
        failureInjection: CanonicalRecordingMetadataCommitFailureInjection = .none
    ) throws {
        self.mode = .rootBound
        self.isDryRunOnly = !allowProductionRootWrites
        self.failureInjection = failureInjection
        self.applyPortMode = allowProductionRootWrites ? .productionRootBound : .productionRootDisabled
        self.rootBoundCore = try CanonicalRootBoundMetadataWriteCore(
            rootURL: productionRootURL,
            rootToken: rootToken,
            mode: self.applyPortMode,
            fileManager: fileManager
        )
    }

    func applyMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        if rootBoundCore != nil {
            try failBeforeMutationIfNeeded()
            let result = try await recordRootBoundResult(request: request, actionKind: .apply, status: .applied, summary: "iphoneRootBoundMetadataApply")
            try failAfterMutationIfNeeded()
            return result
        }
        try requireFakeInMemory()
        try failBeforeMutationIfNeeded()
        let result = recordResult(request: request, status: .applied, sideEffectKind: .metadataApply, summary: "iphoneFakeMetadataApply")
        try failAfterMutationIfNeeded()
        return result
    }

    func sendMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        if rootBoundCore != nil {
            try failBeforeMutationIfNeeded()
            let result = try await recordRootBoundResult(request: request, actionKind: .send, status: .sent, summary: "iphoneRootBoundMetadataSendNoNetwork")
            try failAfterMutationIfNeeded()
            return result
        }
        try requireFakeInMemory()
        try failBeforeMutationIfNeeded()
        let result = recordResult(request: request, status: .sent, sideEffectKind: .metadataApply, summary: "iphoneFakeMetadataSend")
        try failAfterMutationIfNeeded()
        return result
    }

    func applyGeneratedArtifact(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        try requireFakeInMemory()
        guard request.action.target.artifactID != nil else {
            throw CanonicalProductionPortError.unsupportedObject("iphoneGeneratedArtifactMissingID")
        }
        return recordResult(request: request, status: .applied, sideEffectKind: .generatedArtifactApply, summary: "iphoneFakeGeneratedArtifactApply")
    }

    func requestGeneratedArtifact(_ request: CanonicalProductionArtifactRequest) async throws -> CanonicalProductionApplyResult {
        try requireFakeInMemory()
        let actionID = "iphone-request-generated-artifact-\(request.artifactID)"
        let target = CanonicalApplyTarget(objectID: request.objectID, artifactID: request.artifactID, artifactKind: request.kind)
        let result = CanonicalProductionApplyResult(
            actionID: actionID,
            status: .sent,
            precondition: CanonicalProductionApplyPrecondition(actionID: actionID, target: target, accepted: true),
            postcondition: CanonicalProductionApplyPostcondition(actionID: actionID, target: target, accepted: true),
            sideEffect: CanonicalProductionSideEffect(
                kind: .generatedArtifactApply,
                domain: .generatedArtifacts,
                objectID: request.objectID,
                artifactID: request.artifactID,
                summary: "iphoneFakeGeneratedArtifactRequest"
            ),
            rollbackCheckpointID: nil
        )
        results[actionID] = result
        return result
    }

    func applyObjectTombstone(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        try requireFakeInMemory()
        tombstones.insert(request.action.target.objectID)
        return recordResult(request: request, status: .applied, sideEffectKind: .tombstoneMark, summary: "iphoneFakeObjectTombstone")
    }

    func applyLibraryTombstone(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        try requireFakeInMemory()
        tombstones.insert(request.action.target.objectID)
        return recordResult(request: request, status: .applied, sideEffectKind: .tombstoneMark, summary: "iphoneFakeLibraryTombstone")
    }

    func recordConflict(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        try requireFakeInMemory()
        conflicts.insert(request.action.conflictID ?? request.action.actionID)
        return recordResult(request: request, status: .conflictRecorded, sideEffectKind: .conflictRecord, summary: "iphoneFakeConflictRecord")
    }

    nonisolated func verifyPrecondition(_ precondition: CanonicalProductionApplyPrecondition) async throws -> CanonicalProductionApplyPrecondition {
        if failureInjection == .preconditionMismatch {
            var rejected = precondition
            rejected.accepted = false
            rejected.reason = "iphoneFakePreconditionMismatch"
            rejected.expectedHashPrefix = CanonicalProductionRedaction.hashPrefix(precondition.expectedHashPrefix)
            return rejected
        }
        if precondition.expectedHashPrefix?.count == 64 {
            var redacted = precondition
            redacted.expectedHashPrefix = CanonicalProductionRedaction.hashPrefix(precondition.expectedHashPrefix)
            return redacted
        }
        return precondition
    }

    nonisolated func verifyPostcondition(_ postcondition: CanonicalProductionApplyPostcondition) async throws -> CanonicalProductionApplyPostcondition {
        if let rootBoundCore {
            if failureInjection == .postconditionMismatch {
                var rejected = postcondition
                rejected.accepted = false
                rejected.reason = "iphoneRootBoundPostconditionMismatch"
                rejected.actualHashPrefix = CanonicalProductionRedaction.hashPrefix(postcondition.actualHashPrefix)
                return rejected
            }
            return await rootBoundCore.verifyPostcondition(postcondition)
        }
        if failureInjection == .postconditionMismatch {
            var rejected = postcondition
            rejected.accepted = false
            rejected.reason = "iphoneFakePostconditionMismatch"
            rejected.actualHashPrefix = CanonicalProductionRedaction.hashPrefix(postcondition.actualHashPrefix)
            return rejected
        }
        if postcondition.actualHashPrefix?.count == 64 {
            var redacted = postcondition
            redacted.actualHashPrefix = CanonicalProductionRedaction.hashPrefix(postcondition.actualHashPrefix)
            return redacted
        }
        return postcondition
    }

    func rollbackApply(_ request: CanonicalRollbackAction) async throws -> CanonicalRollbackResult {
        if let rootBoundCore {
            let rollback = await rootBoundCore.rollback(request)
            return CanonicalRollbackResult(
                planID: rollback.checkpointID,
                succeeded: rollback.succeeded,
                completedActionIDs: rollback.succeeded ? [request.actionID] : [],
                failures: rollback.succeeded ? [] : [
                    CanonicalRollbackFailure(actionID: request.actionID, reason: rollback.failure?.rawValue ?? "rootBoundRollbackFailed")
                ]
            )
        }
        try requireFakeInMemory()
        if failureInjection == .rollbackFailure {
            return CanonicalRollbackResult(
                planID: request.checkpointID ?? request.actionID,
                succeeded: false,
                completedActionIDs: []
            )
        }
        guard let checkpointID = request.checkpointID,
              let actionID = actionIDsByCheckpointID[checkpointID] else {
            return CanonicalRollbackResult(
                planID: request.checkpointID ?? request.actionID,
                succeeded: false,
                completedActionIDs: []
            )
        }
        if let objectID = results[actionID]?.sideEffect?.objectID {
            actionIDsByObjectID[objectID]?.removeAll { $0 == actionID }
        }
        results.removeValue(forKey: actionID)
        actionIDsByCheckpointID.removeValue(forKey: checkpointID)
        return CanonicalRollbackResult(
            planID: request.checkpointID ?? request.actionID,
            succeeded: true,
            completedActionIDs: [request.actionID]
        )
    }

    nonisolated func projectApplyDryRun(_ action: CanonicalApplyAction) async throws -> CanonicalProductionApplyTrace {
        CanonicalProductionApplyTrace(
            action: action,
            wouldCallApplySyncManifest: false,
            reason: isDryRunOnly ? "iphoneProductionApplyDisabled" : "iphoneProductionApplyProjected:\(applyPortMode.rawValue)"
        )
    }

    func setRootBoundMetadataPayload(
        objectID: String,
        actionKind: CanonicalRecordingMetadataCutoverActionKind,
        metadataBytes: Data,
        metadataHash: CanonicalHash? = nil,
        tombstone: Bool = false,
        modifiedAt: CanonicalTimestamp? = nil,
        logicalPathToken: String? = nil,
        actionID: String? = nil
    ) async throws {
        guard let rootBoundCore else {
            throw CanonicalRootBoundMetadataWriteFailure.unsupportedStoreAPI
        }
        try await rootBoundCore.setPayload(
            objectID: objectID,
            actionKind: actionKind,
            metadataBytes: metadataBytes,
            metadataHash: metadataHash,
            tombstone: tombstone,
            modifiedAt: modifiedAt,
            logicalPathToken: logicalPathToken,
            actionID: actionID
        )
    }

    func injectRootBoundCheckpointFailure(objectID: String) async {
        await rootBoundCore?.injectCheckpointFailure(for: objectID)
    }

    func injectRootBoundPostconditionFailure(objectID: String) async {
        await rootBoundCore?.injectPostconditionFailure(for: objectID)
    }

    func injectRootBoundRollbackFailure(checkpointID: String) async {
        await rootBoundCore?.injectRollbackFailure(checkpointID: checkpointID)
    }

    func rootBoundWriteResult(for actionID: String) async -> CanonicalRootBoundMetadataWriteResult? {
        await rootBoundCore?.lastWriteResult(actionID: actionID)
    }

    func rootBoundRollbackResult(for checkpointID: String) async -> CanonicalRootBoundMetadataRollbackResult? {
        await rootBoundCore?.lastRollbackResult(checkpointID: checkpointID)
    }

    func rootBoundMetadataBytes(objectID: String, actionKind: CanonicalRecordingMetadataCutoverActionKind = .apply) async throws -> Data? {
        try await rootBoundCore?.readMetadataBytes(objectID: objectID, actionKind: actionKind)
    }

    func fakeCommittedActionIDs(for objectID: String) -> [String] {
        actionIDsByObjectID[objectID] ?? []
    }

    func fakeResult(for actionID: String) -> CanonicalProductionApplyResult? {
        results[actionID]
    }

    func fakeTombstoneCount() -> Int {
        tombstones.count
    }

    func fakeConflictCount() -> Int {
        conflicts.count
    }

    private enum Mode: Sendable {
        case disabled
        case fakeInMemory
        case rootBound
    }

    private func requireFakeInMemory() throws {
        guard mode == .fakeInMemory else {
            throw CanonicalProductionPortError.productionMutationAttempted("iphoneProductionApplyDisabled")
        }
    }

    private func failBeforeMutationIfNeeded() throws {
        if failureInjection == .applyFailureBeforeCommit {
            throw CanonicalProductionPortError.productionMutationAttempted("iphoneFakeApplyFailureBeforeMutation")
        }
    }

    private func failAfterMutationIfNeeded() throws {
        if failureInjection == .applyFailureAfterPartialCommit {
            throw CanonicalProductionPortError.productionMutationAttempted("iphoneFakeApplyFailureAfterPartialMutation")
        }
    }

    private func recordRootBoundResult(
        request: CanonicalProductionApplyExecutionRequest,
        actionKind: CanonicalRecordingMetadataCutoverActionKind,
        status: CanonicalApplyExecutionStatus,
        summary: String
    ) async throws -> CanonicalProductionApplyResult {
        guard let rootBoundCore else {
            throw CanonicalRootBoundMetadataWriteFailure.unsupportedStoreAPI
        }
        guard (actionKind == .apply && request.action.kind == .recordingMetadataApply)
            || (actionKind == .send && request.action.kind == .recordingMetadataSend) else {
            throw CanonicalRootBoundMetadataWriteFailure.unsupportedStoreAPI
        }
        let write = try await rootBoundCore.write(
            action: request.action,
            actionKind: actionKind,
            checkpointID: request.rollbackCheckpointID
        )
        let precondition = CanonicalProductionApplyPrecondition(
            actionID: request.action.actionID,
            target: request.action.target,
            expectedHashPrefix: write.hashPrefixBefore,
            accepted: true,
            reason: "iphoneRootBoundPreconditionAccepted"
        )
        let postcondition = CanonicalProductionApplyPostcondition(
            actionID: request.action.actionID,
            target: request.action.target,
            actualHashPrefix: write.hashPrefixAfter,
            accepted: true,
            reason: "iphoneRootBoundPostconditionAccepted"
        )
        return CanonicalProductionApplyResult(
            actionID: request.action.actionID,
            status: status,
            precondition: precondition,
            postcondition: postcondition,
            sideEffect: CanonicalProductionSideEffect(
                kind: .metadataApply,
                domain: .recordingMetadata,
                objectID: request.action.target.objectID,
                byteSize: write.byteCount,
                hashPrefix: write.hashPrefixAfter,
                summary: "\(summary):atomicReplace=\(write.atomicWriteUsed):rollback=\(write.rollbackAvailable)"
            ),
            rollbackCheckpointID: write.checkpointID
        )
    }

    private func recordResult(
        request: CanonicalProductionApplyExecutionRequest,
        status: CanonicalApplyExecutionStatus,
        sideEffectKind: CanonicalProductionSideEffectKind,
        summary: String
    ) -> CanonicalProductionApplyResult {
        if let existing = results[request.action.actionID] {
            return existing
        }
        let effectiveSideEffectKind: CanonicalProductionSideEffectKind
        let effectiveDomain: CanonicalProductionDomain
        switch failureInjection {
        case .unsupportedSideEffect:
            effectiveSideEffectKind = .generatedArtifactApply
            effectiveDomain = .generatedArtifacts
        case .unexpectedSideEffect:
            effectiveSideEffectKind = .uploadSessionStart
            effectiveDomain = .uploadRuntime
        default:
            effectiveSideEffectKind = sideEffectKind
            effectiveDomain = .apply
        }
        let result = CanonicalProductionApplyResult(
            actionID: request.action.actionID,
            status: status,
            precondition: CanonicalProductionApplyPrecondition(
                actionID: request.action.actionID,
                target: request.action.target,
                accepted: true
            ),
            postcondition: CanonicalProductionApplyPostcondition(
                actionID: request.action.actionID,
                target: request.action.target,
                accepted: true
            ),
            sideEffect: CanonicalProductionSideEffect(
                kind: effectiveSideEffectKind,
                domain: effectiveDomain,
                objectID: request.action.target.objectID,
                artifactID: request.action.target.artifactID,
                summary: summary
            ),
            rollbackCheckpointID: request.rollbackCheckpointID
        )
        results[request.action.actionID] = result
        if let checkpointID = request.rollbackCheckpointID {
            actionIDsByCheckpointID[checkpointID] = request.action.actionID
        }
        actionIDsByObjectID[request.action.target.objectID, default: []].append(request.action.actionID)
        return result
    }
}
