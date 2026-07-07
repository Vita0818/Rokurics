//
//  MacTombstoneConflictRealApplyPort.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/4.
//

import Foundation

actor MacTombstoneConflictRealApplyPort: CanonicalProductionApplyPort {
    nonisolated let isDryRunOnly: Bool
    nonisolated let metadataApplySupported = false
    nonisolated let generatedArtifactApplySupported = false
    nonisolated let tombstoneApplySupported = true
    nonisolated let conflictRecordSupported = true
    nonisolated let applyPortMode: CanonicalTombstoneConflictApplyPortMode

    private nonisolated let failureInjection: CanonicalTombstoneConflictCommitFailureInjection
    private nonisolated let rootBoundCore: CanonicalRootBoundTombstoneConflictWriteCore?

    init() {
        self.isDryRunOnly = true
        self.failureInjection = .none
        self.applyPortMode = .disabled
        self.rootBoundCore = nil
    }

    init(
        testRootURL: URL,
        rootToken: CanonicalRootToken = CanonicalRootToken("mac-tombstone-conflict-test-root"),
        fileManager: FileManager = .default,
        failureInjection: CanonicalTombstoneConflictCommitFailureInjection = .none
    ) throws {
        self.isDryRunOnly = false
        self.failureInjection = failureInjection
        self.applyPortMode = .testRootBound
        self.rootBoundCore = try CanonicalRootBoundTombstoneConflictWriteCore(
            rootURL: testRootURL,
            rootToken: rootToken,
            mode: .testRootBound,
            fileManager: fileManager
        )
    }

    init(
        productionRootURL: URL,
        rootToken: CanonicalRootToken = CanonicalRootToken("mac-tombstone-conflict-production-root"),
        allowProductionRootWrites: Bool = false,
        fileManager: FileManager = .default,
        failureInjection: CanonicalTombstoneConflictCommitFailureInjection = .none
    ) throws {
        self.isDryRunOnly = !allowProductionRootWrites
        self.failureInjection = failureInjection
        self.applyPortMode = allowProductionRootWrites ? .productionRootBound : .productionRootDisabled
        self.rootBoundCore = try CanonicalRootBoundTombstoneConflictWriteCore(
            rootURL: productionRootURL,
            rootToken: rootToken,
            mode: self.applyPortMode,
            fileManager: fileManager
        )
    }

    func applyObjectTombstone(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        try await writeTombstoneConflict(
            request,
            status: request.action.kind == .objectTombstoneSend ? .sent : .applied,
            sideEffectKind: .tombstoneMark,
            summary: "macRootBoundObjectTombstoneMarker"
        )
    }

    func applyLibraryTombstone(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        try await writeTombstoneConflict(
            request,
            status: request.action.kind == .libraryTombstoneSend ? .sent : .applied,
            sideEffectKind: .tombstoneMark,
            summary: "macRootBoundLibraryTombstoneMarker"
        )
    }

    func recordConflict(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        try await writeTombstoneConflict(
            request,
            status: .conflictRecorded,
            sideEffectKind: .conflictRecord,
            summary: "macRootBoundConflictLedgerRecord"
        )
    }

    nonisolated func verifyPrecondition(_ precondition: CanonicalProductionApplyPrecondition) async throws -> CanonicalProductionApplyPrecondition {
        if failureInjection == .preconditionMismatch {
            var rejected = precondition
            rejected.accepted = false
            rejected.reason = "macTombstoneConflictPreconditionMismatch"
            rejected.expectedHashPrefix = CanonicalProductionRedaction.hashPrefix(precondition.expectedHashPrefix)
            return rejected
        }
        var redacted = precondition
        redacted.expectedHashPrefix = CanonicalProductionRedaction.hashPrefix(precondition.expectedHashPrefix)
        return redacted
    }

    nonisolated func verifyPostcondition(_ postcondition: CanonicalProductionApplyPostcondition) async throws -> CanonicalProductionApplyPostcondition {
        if failureInjection == .postconditionMismatch {
            var rejected = postcondition
            rejected.accepted = false
            rejected.reason = "macTombstoneConflictPostconditionMismatch"
            rejected.actualHashPrefix = CanonicalProductionRedaction.hashPrefix(postcondition.actualHashPrefix)
            return rejected
        }
        guard let rootBoundCore else {
            return postcondition
        }
        return await rootBoundCore.verifyPostcondition(postcondition)
    }

    func rollbackApply(_ request: CanonicalRollbackAction) async throws -> CanonicalRollbackResult {
        guard let rootBoundCore else {
            return CanonicalRollbackResult(
                planID: request.checkpointID ?? request.actionID,
                succeeded: false,
                failures: [CanonicalRollbackFailure(actionID: request.actionID, reason: "macTombstoneConflictRollbackDisabled")]
            )
        }
        let rollback = await rootBoundCore.rollback(request)
        return CanonicalRollbackResult(
            planID: rollback.checkpointID,
            succeeded: rollback.succeeded,
            completedActionIDs: rollback.succeeded ? [request.actionID] : [],
            failures: rollback.succeeded ? [] : [
                CanonicalRollbackFailure(actionID: request.actionID, reason: rollback.failure?.rawValue ?? "tombstoneConflictRollbackFailed")
            ]
        )
    }

    nonisolated func projectApplyDryRun(_ action: CanonicalApplyAction) async throws -> CanonicalProductionApplyTrace {
        CanonicalProductionApplyTrace(
            action: action,
            wouldCallApplySyncManifest: false,
            reason: isDryRunOnly ? "macTombstoneConflictApplyDisabled" : "macTombstoneConflictApplyProjected:\(applyPortMode.rawValue)"
        )
    }

    func setRootBoundTombstoneConflictPayload(
        candidate: CanonicalTombstoneConflictCandidate,
        bytes: Data? = nil,
        logicalPathToken: String? = nil
    ) async throws {
        guard let rootBoundCore else {
            throw CanonicalTombstoneConflictFailure.rootBoundWriteUnavailable
        }
        try await rootBoundCore.setPayload(
            candidate: candidate,
            bytes: bytes,
            logicalPathToken: logicalPathToken
        )
    }

    func injectRootBoundCheckpointFailure(objectID: String) async {
        await rootBoundCore?.injectCheckpointFailure(objectID: objectID)
    }

    func injectRootBoundPostconditionFailure(objectID: String) async {
        await rootBoundCore?.injectPostconditionFailure(objectID: objectID)
    }

    func injectRootBoundRollbackFailure(checkpointID: String) async {
        await rootBoundCore?.injectRollbackFailure(checkpointID: checkpointID)
    }

    func rootBoundWriteResult(for actionID: String) async -> CanonicalRootBoundTombstoneConflictWriteResult? {
        await rootBoundCore?.lastWriteResult(actionID: actionID)
    }

    func rootBoundRollbackResult(for checkpointID: String) async -> CanonicalRootBoundTombstoneConflictRollbackResult? {
        await rootBoundCore?.lastRollbackResult(checkpointID: checkpointID)
    }

    func rootBoundTombstoneConflictBytes(for actionID: String) async throws -> Data? {
        try await rootBoundCore?.readBytes(actionID: actionID)
    }

    private func writeTombstoneConflict(
        _ request: CanonicalProductionApplyExecutionRequest,
        status: CanonicalApplyExecutionStatus,
        sideEffectKind: CanonicalProductionSideEffectKind,
        summary: String
    ) async throws -> CanonicalProductionApplyResult {
        guard let rootBoundCore else {
            throw CanonicalProductionPortError.productionMutationAttempted("macTombstoneConflictApplyDisabled")
        }
        guard !isDryRunOnly else {
            throw CanonicalProductionPortError.productionMutationAttempted("macTombstoneConflictProductionRootDisabled")
        }
        try failBeforeMutationIfNeeded()
        let write = try await rootBoundCore.write(
            action: request.action,
            checkpointID: request.rollbackCheckpointID
        )
        try failAfterMutationIfNeeded()
        return CanonicalProductionApplyResult(
            actionID: request.action.actionID,
            status: status,
            precondition: CanonicalProductionApplyPrecondition(
                actionID: request.action.actionID,
                target: request.action.target,
                expectedHashPrefix: write.hashPrefixBefore,
                accepted: true,
                reason: "macTombstoneConflictPreconditionAccepted"
            ),
            postcondition: CanonicalProductionApplyPostcondition(
                actionID: request.action.actionID,
                target: request.action.target,
                actualHashPrefix: write.hashPrefixAfter,
                accepted: failureInjection != .postconditionMismatch,
                reason: failureInjection == .postconditionMismatch ? "macTombstoneConflictPostconditionMismatch" : "macTombstoneConflictPostconditionAccepted"
            ),
            sideEffect: CanonicalProductionSideEffect(
                kind: sideEffectKind,
                domain: write.domain.productionDomain,
                objectID: request.action.target.objectID,
                artifactID: request.action.target.artifactID,
                byteSize: Int64(write.byteCount),
                hashPrefix: write.hashPrefixAfter,
                summary: "\(summary):atomicReplace=\(write.atomicWriteUsed):rollback=\(write.rollbackAvailable):physicalDelete=false:permanentDelete=false:tombstoneGC=false"
            ),
            rollbackCheckpointID: write.checkpointID
        )
    }

    private func failBeforeMutationIfNeeded() throws {
        switch failureInjection {
        case .applyFailureBeforeCommit, .resurrectionRiskDetected, .physicalDeleteAttempted,
             .permanentDeleteAttempted, .tombstoneGCAttempted, .unsupportedRestore, .conflictPolicyAmbiguous:
            throw CanonicalProductionPortError.productionMutationAttempted("macTombstoneConflictFailureBeforeMutation")
        case .none, .preconditionMismatch, .postconditionMismatch, .applyFailureAfterPartialCommit, .rollbackFailure:
            break
        }
    }

    private func failAfterMutationIfNeeded() throws {
        if failureInjection == .applyFailureAfterPartialCommit {
            throw CanonicalProductionPortError.productionMutationAttempted("macTombstoneConflictFailureAfterPartialMutation")
        }
    }
}
