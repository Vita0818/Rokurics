//
//  MacRecordingMetadataRealApplyPort.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/12.
//

import Foundation

actor MacRecordingMetadataRealApplyPort: CanonicalProductionApplyPort {
    nonisolated let isDryRunOnly: Bool
    nonisolated let metadataApplySupported = true
    nonisolated let generatedArtifactApplySupported = false
    nonisolated let tombstoneApplySupported = false
    nonisolated let conflictRecordSupported = false
    nonisolated let applyPortMode: CanonicalRecordingMetadataApplyPortMode

    private nonisolated let failureInjection: CanonicalRecordingMetadataCommitFailureInjection
    private nonisolated let rootBoundCore: CanonicalRootBoundMetadataWriteCore?

    init() {
        self.isDryRunOnly = true
        self.failureInjection = .none
        self.applyPortMode = .disabled
        self.rootBoundCore = nil
    }

    init(
        testRootURL: URL,
        rootToken: CanonicalRootToken = CanonicalRootToken("mac-recording-metadata-test-root"),
        fileManager: FileManager = .default,
        failureInjection: CanonicalRecordingMetadataCommitFailureInjection = .none
    ) throws {
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
        rootToken: CanonicalRootToken = CanonicalRootToken("mac-recording-metadata-production-root"),
        allowProductionRootWrites: Bool = false,
        fileManager: FileManager = .default,
        failureInjection: CanonicalRecordingMetadataCommitFailureInjection = .none
    ) throws {
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

    func prepare(candidate: CanonicalRecordingMetadataCutoverCandidate) async throws {
        guard let actionKind = candidate.cutoverActionKind,
              let expectedObject = candidate.expectedObject else {
            throw CanonicalRootBoundMetadataWriteFailure.schemaMismatch
        }
        try await setRootBoundMetadataPayload(
            objectID: candidate.objectID,
            actionKind: actionKind,
            metadataBytes: try Self.payloadBytes(for: expectedObject),
            metadataHash: candidate.stableMetadataHash,
            tombstone: expectedObject.metadata.isDeleted,
            modifiedAt: expectedObject.metadata.modifiedAt,
            actionID: candidate.action.actionID
        )
    }

    func applyMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        try failBeforeMutationIfNeeded()
        let result = try await writeMetadata(
            request: request,
            actionKind: .apply,
            status: .applied,
            summary: "macRecordingMetadataRootBoundApply"
        )
        try failAfterMutationIfNeeded()
        return result
    }

    func sendMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        try failBeforeMutationIfNeeded()
        let result = try await writeMetadata(
            request: request,
            actionKind: .send,
            status: .sent,
            summary: "macRecordingMetadataRootBoundSendNoNetwork"
        )
        try failAfterMutationIfNeeded()
        return result
    }

    nonisolated func verifyPrecondition(_ precondition: CanonicalProductionApplyPrecondition) async throws -> CanonicalProductionApplyPrecondition {
        if failureInjection == .preconditionMismatch {
            var rejected = precondition
            rejected.accepted = false
            rejected.reason = "macRecordingMetadataPreconditionMismatch"
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
        guard let rootBoundCore else {
            var rejected = postcondition
            rejected.accepted = false
            rejected.reason = "macRecordingMetadataRootBoundPortDisabled"
            return rejected
        }
        if failureInjection == .postconditionMismatch {
            var rejected = postcondition
            rejected.accepted = false
            rejected.reason = "macRecordingMetadataPostconditionMismatch"
            rejected.actualHashPrefix = CanonicalProductionRedaction.hashPrefix(postcondition.actualHashPrefix)
            return rejected
        }
        return await rootBoundCore.verifyPostcondition(postcondition)
    }

    func rollbackApply(_ request: CanonicalRollbackAction) async throws -> CanonicalRollbackResult {
        guard let rootBoundCore else {
            return CanonicalRollbackResult(
                planID: request.checkpointID ?? request.actionID,
                succeeded: false,
                failures: [CanonicalRollbackFailure(actionID: request.actionID, reason: "macRecordingMetadataRootBoundPortDisabled")]
            )
        }
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

    nonisolated func projectApplyDryRun(_ action: CanonicalApplyAction) async throws -> CanonicalProductionApplyTrace {
        CanonicalProductionApplyTrace(
            action: action,
            wouldCallApplySyncManifest: false,
            reason: isDryRunOnly
                ? "macRecordingMetadataRealApplyPortDisabled"
                : "macRecordingMetadataRealApplyPortProjected:\(applyPortMode.rawValue)"
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

    private func failBeforeMutationIfNeeded() throws {
        if failureInjection == .applyFailureBeforeCommit {
            throw CanonicalProductionPortError.productionMutationAttempted("macRecordingMetadataApplyFailureBeforeMutation")
        }
    }

    private func failAfterMutationIfNeeded() throws {
        if failureInjection == .applyFailureAfterPartialCommit {
            throw CanonicalProductionPortError.productionMutationAttempted("macRecordingMetadataApplyFailureAfterPartialMutation")
        }
    }

    private func writeMetadata(
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
            reason: "macRecordingMetadataPreconditionAccepted"
        )
        let postcondition = CanonicalProductionApplyPostcondition(
            actionID: request.action.actionID,
            target: request.action.target,
            actualHashPrefix: write.hashPrefixAfter,
            accepted: true,
            reason: "macRecordingMetadataPostconditionAccepted"
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
                summary: "\(summary):atomicReplace=\(write.atomicWriteUsed):rollback=\(write.rollbackAvailable):receiveJSONTouched=false:audioInboxTouched=false:generationTriggered=false"
            ),
            rollbackCheckpointID: write.checkpointID
        )
    }

    private nonisolated static func payloadBytes(for object: CanonicalRecordingObject) throws -> Data {
        let metadata = object.metadata
        let payload = RecordingMetadataRootPayload(
            schemaVersion: CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
            objectID: metadata.objectID,
            title: metadata.title,
            name: metadata.title,
            createdAtEpochSeconds: metadata.createdAt.date.timeIntervalSince1970,
            modifiedAtEpochSeconds: metadata.modifiedAt.date.timeIntervalSince1970,
            duration: metadata.duration,
            filingType: metadata.filing?.type,
            filingSubject: metadata.filing?.subject,
            filingChapter: metadata.filing?.chapter,
            filingTopic: metadata.filing?.topic,
            tags: metadata.tags,
            isDeleted: metadata.isDeleted,
            deletedAtEpochSeconds: metadata.deletedAt?.date.timeIntervalSince1970,
            metadataHash: metadata.metadataHash.value,
            legacyCompatibility: RecordingMetadataRootPayload.LegacyCompatibility(
                title: metadata.title,
                updatedAtEpochSeconds: metadata.modifiedAt.date.timeIntervalSince1970,
                deleted: metadata.isDeleted
            ),
            canonicalCompatibility: RecordingMetadataRootPayload.CanonicalCompatibility(
                businessModifiedAtEpochSeconds: metadata.modifiedAt.date.timeIntervalSince1970,
                metadataHash: metadata.metadataHash.value
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }
}

private nonisolated struct RecordingMetadataRootPayload: Codable, Sendable {
    nonisolated struct LegacyCompatibility: Codable, Sendable {
        var title: String
        var updatedAtEpochSeconds: TimeInterval
        var deleted: Bool
    }

    nonisolated struct CanonicalCompatibility: Codable, Sendable {
        var businessModifiedAtEpochSeconds: TimeInterval
        var metadataHash: String
    }

    var kind: String = "recordingMetadata"
    var schemaVersion: String
    var objectID: String
    var title: String
    var name: String
    var createdAtEpochSeconds: TimeInterval
    var modifiedAtEpochSeconds: TimeInterval
    var duration: TimeInterval?
    var filingType: String?
    var filingSubject: String?
    var filingChapter: String?
    var filingTopic: String?
    var tags: [String]
    var isDeleted: Bool
    var deletedAtEpochSeconds: TimeInterval?
    var metadataHash: String
    var legacyCompatibility: LegacyCompatibility
    var canonicalCompatibility: CanonicalCompatibility
}
