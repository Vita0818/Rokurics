//
//  IPhoneGeneratedArtifactRealApplyPort.swift
//  Rokurics
//
//  Created by Codex on 2026/6/4.
//

import Foundation

actor IPhoneGeneratedArtifactRealApplyPort: CanonicalProductionApplyPort {
    nonisolated let isDryRunOnly: Bool
    nonisolated let metadataApplySupported = false
    nonisolated let generatedArtifactApplySupported = true
    nonisolated let tombstoneApplySupported = false
    nonisolated let conflictRecordSupported = false
    nonisolated let applyPortMode: CanonicalGeneratedArtifactApplyPortMode

    private let mode: Mode
    private nonisolated let failureInjection: CanonicalGeneratedArtifactCommitFailureInjection
    private nonisolated let rootBoundCore: CanonicalRootBoundGeneratedArtifactWriteCore?
    private var fakeResults: [String: CanonicalProductionApplyResult] = [:]

    init() {
        self.mode = .disabled
        self.isDryRunOnly = true
        self.failureInjection = .none
        self.applyPortMode = .disabled
        self.rootBoundCore = nil
    }

    init(
        testRootURL: URL,
        rootToken: CanonicalRootToken = CanonicalRootToken("iphone-generated-artifact-test-root"),
        fileManager: FileManager = .default,
        failureInjection: CanonicalGeneratedArtifactCommitFailureInjection = .none
    ) throws {
        self.mode = .rootBound
        self.isDryRunOnly = false
        self.failureInjection = failureInjection
        self.applyPortMode = .testRootBound
        self.rootBoundCore = try CanonicalRootBoundGeneratedArtifactWriteCore(
            rootURL: testRootURL,
            rootToken: rootToken,
            mode: .testRootBound,
            fileManager: fileManager
        )
    }

    init(
        productionRootURL: URL,
        rootToken: CanonicalRootToken = CanonicalRootToken("iphone-generated-artifact-production-root"),
        allowProductionRootWrites: Bool = false,
        fileManager: FileManager = .default,
        failureInjection: CanonicalGeneratedArtifactCommitFailureInjection = .none
    ) throws {
        self.mode = .rootBound
        self.isDryRunOnly = !allowProductionRootWrites
        self.failureInjection = failureInjection
        self.applyPortMode = allowProductionRootWrites ? .productionRootBound : .productionRootDisabled
        self.rootBoundCore = try CanonicalRootBoundGeneratedArtifactWriteCore(
            rootURL: productionRootURL,
            rootToken: rootToken,
            mode: self.applyPortMode,
            fileManager: fileManager
        )
    }

    func applyGeneratedArtifact(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        guard let rootBoundCore else {
            throw CanonicalProductionPortError.productionMutationAttempted("iphoneGeneratedArtifactApplyDisabled")
        }
        try failBeforeMutationIfNeeded()
        let write = try await rootBoundCore.write(action: request.action, checkpointID: request.rollbackCheckpointID)
        try failAfterMutationIfNeeded()
        return CanonicalProductionApplyResult(
            actionID: request.action.actionID,
            status: .applied,
            precondition: CanonicalProductionApplyPrecondition(
                actionID: request.action.actionID,
                target: request.action.target,
                expectedHashPrefix: write.hashPrefixBefore,
                accepted: true,
                reason: "iphoneGeneratedArtifactPreconditionAccepted"
            ),
            postcondition: CanonicalProductionApplyPostcondition(
                actionID: request.action.actionID,
                target: request.action.target,
                actualHashPrefix: write.hashPrefixAfter,
                accepted: failureInjection != .postconditionMismatch,
                reason: failureInjection == .postconditionMismatch ? "iphoneGeneratedArtifactPostconditionMismatch" : "iphoneGeneratedArtifactPostconditionAccepted"
            ),
            sideEffect: CanonicalProductionSideEffect(
                kind: .generatedArtifactApply,
                domain: .generatedArtifacts,
                objectID: request.action.target.objectID,
                artifactID: request.action.target.artifactID,
                byteSize: write.byteCount,
                hashPrefix: write.hashPrefixAfter,
                summary: "iphoneRootBoundGeneratedArtifactApply:atomicReplace=\(write.atomicWriteUsed):rollback=\(write.rollbackAvailable)"
            ),
            rollbackCheckpointID: write.checkpointID
        )
    }

    func requestGeneratedArtifact(_ request: CanonicalProductionArtifactRequest) async throws -> CanonicalProductionApplyResult {
        guard !isDryRunOnly else {
            throw CanonicalProductionPortError.networkExecutionSuppressed("iphoneGeneratedArtifactRequestSuppressed")
        }
        let actionID = "iphone-generated-artifact-request-\(request.artifactID)"
        let target = CanonicalApplyTarget(objectID: request.objectID, artifactID: request.artifactID, artifactKind: request.kind)
        let result = CanonicalProductionApplyResult(
            actionID: actionID,
            status: .sent,
            precondition: CanonicalProductionApplyPrecondition(actionID: actionID, target: target, accepted: true),
            postcondition: CanonicalProductionApplyPostcondition(actionID: actionID, target: target, accepted: true),
            sideEffect: CanonicalProductionSideEffect(
                kind: .diagnosticsWrite,
                domain: .generatedArtifacts,
                objectID: request.objectID,
                artifactID: request.artifactID,
                summary: "iphoneGeneratedArtifactRequestProjection:/sync/artifact-request"
            ),
            rollbackCheckpointID: nil
        )
        fakeResults[actionID] = result
        return result
    }

    nonisolated func verifyPrecondition(_ precondition: CanonicalProductionApplyPrecondition) async throws -> CanonicalProductionApplyPrecondition {
        if failureInjection == .hashMismatchBeforeApply {
            var rejected = precondition
            rejected.accepted = false
            rejected.reason = "iphoneGeneratedArtifactHashMismatchBeforeApply"
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
            rejected.reason = "iphoneGeneratedArtifactPostconditionMismatch"
            rejected.actualHashPrefix = CanonicalProductionRedaction.hashPrefix(postcondition.actualHashPrefix)
            return rejected
        }
        var redacted = postcondition
        redacted.actualHashPrefix = CanonicalProductionRedaction.hashPrefix(postcondition.actualHashPrefix)
        return redacted
    }

    func rollbackApply(_ request: CanonicalRollbackAction) async throws -> CanonicalRollbackResult {
        guard let rootBoundCore else {
            return CanonicalRollbackResult(
                planID: request.checkpointID ?? request.actionID,
                succeeded: false,
                failures: [CanonicalRollbackFailure(actionID: request.actionID, reason: "iphoneGeneratedArtifactRollbackDisabled")]
            )
        }
        let rollback = await rootBoundCore.rollback(request)
        return CanonicalRollbackResult(
            planID: rollback.checkpointID,
            succeeded: rollback.succeeded,
            completedActionIDs: rollback.succeeded ? [request.actionID] : [],
            failures: rollback.succeeded ? [] : [
                CanonicalRollbackFailure(actionID: request.actionID, reason: rollback.failure?.rawValue ?? "generatedArtifactRollbackFailed")
            ]
        )
    }

    nonisolated func projectApplyDryRun(_ action: CanonicalApplyAction) async throws -> CanonicalProductionApplyTrace {
        CanonicalProductionApplyTrace(
            action: action,
            wouldCallApplySyncManifest: false,
            reason: isDryRunOnly ? "iphoneGeneratedArtifactApplyDisabled" : "iphoneGeneratedArtifactApplyProjected:\(applyPortMode.rawValue)"
        )
    }

    func setRootBoundGeneratedArtifactPayload(
        objectID: String,
        artifactID: String,
        kind: CanonicalArtifact.Kind,
        artifactBytes: Data,
        expectedContentHash: CanonicalHash,
        expectedByteSize: Int64,
        logicalPathToken: String? = nil,
        actionID: String? = nil
    ) async throws {
        guard let rootBoundCore else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.unsupportedStoreAPI
        }
        try await rootBoundCore.setPayload(
            objectID: objectID,
            artifactID: artifactID,
            kind: kind,
            artifactBytes: artifactBytes,
            expectedContentHash: expectedContentHash,
            expectedByteSize: expectedByteSize,
            logicalPathToken: logicalPathToken,
            actionID: actionID
        )
    }

    func injectRootBoundCheckpointFailure(artifactID: String) async {
        await rootBoundCore?.injectCheckpointFailure(artifactID: artifactID)
    }

    func injectRootBoundPostconditionFailure(artifactID: String) async {
        await rootBoundCore?.injectPostconditionFailure(artifactID: artifactID)
    }

    func injectRootBoundRollbackFailure(checkpointID: String) async {
        await rootBoundCore?.injectRollbackFailure(checkpointID: checkpointID)
    }

    func rootBoundWriteResult(for actionID: String) async -> CanonicalRootBoundGeneratedArtifactWriteResult? {
        await rootBoundCore?.lastWriteResult(actionID: actionID)
    }

    func rootBoundRollbackResult(for checkpointID: String) async -> CanonicalRootBoundGeneratedArtifactRollbackResult? {
        await rootBoundCore?.lastRollbackResult(checkpointID: checkpointID)
    }

    func rootBoundArtifactBytes(objectID: String, artifactID: String, kind: CanonicalArtifact.Kind) async throws -> Data? {
        try await rootBoundCore?.readArtifactBytes(objectID: objectID, artifactID: artifactID, kind: kind)
    }

    private enum Mode: Sendable {
        case disabled
        case rootBound
    }

    private func failBeforeMutationIfNeeded() throws {
        if failureInjection == .applyFailureBeforeCommit {
            throw CanonicalProductionPortError.productionMutationAttempted("iphoneGeneratedArtifactApplyFailureBeforeMutation")
        }
    }

    private func failAfterMutationIfNeeded() throws {
        if failureInjection == .applyFailureAfterPartialCommit {
            throw CanonicalProductionPortError.productionMutationAttempted("iphoneGeneratedArtifactApplyFailureAfterPartialMutation")
        }
    }
}
