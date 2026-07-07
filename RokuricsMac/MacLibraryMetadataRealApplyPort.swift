//
//  MacLibraryMetadataRealApplyPort.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/4.
//

import Foundation

actor MacLibraryMetadataRealApplyPort: CanonicalProductionApplyPort {
    nonisolated let isDryRunOnly: Bool
    nonisolated let metadataApplySupported = true
    nonisolated let generatedArtifactApplySupported = false
    nonisolated let tombstoneApplySupported = false
    nonisolated let conflictRecordSupported = false
    nonisolated let applyPortMode: CanonicalLibraryMetadataApplyPortMode

    private nonisolated let failureInjection: CanonicalLibraryMetadataCommitFailureInjection
    private nonisolated let rootBoundCore: CanonicalRootBoundLibraryMetadataWriteCore?

    init() {
        self.isDryRunOnly = true
        self.failureInjection = .none
        self.applyPortMode = .disabled
        self.rootBoundCore = nil
    }

    init(
        testRootURL: URL,
        rootToken: CanonicalRootToken = CanonicalRootToken("mac-library-metadata-test-root"),
        fileManager: FileManager = .default,
        failureInjection: CanonicalLibraryMetadataCommitFailureInjection = .none
    ) throws {
        self.isDryRunOnly = false
        self.failureInjection = failureInjection
        self.applyPortMode = .testRootBound
        self.rootBoundCore = try CanonicalRootBoundLibraryMetadataWriteCore(
            rootURL: testRootURL,
            rootToken: rootToken,
            mode: .testRootBound,
            fileManager: fileManager
        )
    }

    init(
        productionRootURL: URL,
        rootToken: CanonicalRootToken = CanonicalRootToken("mac-library-metadata-production-root"),
        allowProductionRootWrites: Bool = false,
        fileManager: FileManager = .default,
        failureInjection: CanonicalLibraryMetadataCommitFailureInjection = .none
    ) throws {
        self.isDryRunOnly = !allowProductionRootWrites
        self.failureInjection = failureInjection
        self.applyPortMode = allowProductionRootWrites ? .productionRootBound : .productionRootDisabled
        self.rootBoundCore = try CanonicalRootBoundLibraryMetadataWriteCore(
            rootURL: productionRootURL,
            rootToken: rootToken,
            mode: self.applyPortMode,
            fileManager: fileManager
        )
    }

    func applyMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        try await writeMetadata(request, status: .applied, summary: "macRootBoundLibraryMetadataApply")
    }

    func sendMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        try await writeMetadata(request, status: .sent, summary: "macRootBoundLibraryMetadataSendNoNetwork")
    }

    nonisolated func verifyPrecondition(_ precondition: CanonicalProductionApplyPrecondition) async throws -> CanonicalProductionApplyPrecondition {
        if failureInjection == .preconditionMismatch {
            var rejected = precondition
            rejected.accepted = false
            rejected.reason = "macLibraryMetadataPreconditionMismatch"
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
            rejected.reason = "macLibraryMetadataPostconditionMismatch"
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
                failures: [CanonicalRollbackFailure(actionID: request.actionID, reason: "macLibraryMetadataRollbackDisabled")]
            )
        }
        let rollback = await rootBoundCore.rollback(request)
        return CanonicalRollbackResult(
            planID: rollback.checkpointID,
            succeeded: rollback.succeeded,
            completedActionIDs: rollback.succeeded ? [request.actionID] : [],
            failures: rollback.succeeded ? [] : [
                CanonicalRollbackFailure(actionID: request.actionID, reason: rollback.failure?.rawValue ?? "libraryMetadataRollbackFailed")
            ]
        )
    }

    nonisolated func projectApplyDryRun(_ action: CanonicalApplyAction) async throws -> CanonicalProductionApplyTrace {
        CanonicalProductionApplyTrace(
            action: action,
            wouldCallApplySyncManifest: false,
            reason: isDryRunOnly ? "macLibraryMetadataApplyDisabled" : "macLibraryMetadataApplyProjected:\(applyPortMode.rawValue)"
        )
    }

    func setRootBoundLibraryMetadataPayload(
        candidate: CanonicalLibraryMetadataCutoverCandidate,
        metadataBytes: Data? = nil,
        logicalPathToken: String? = nil
    ) async throws {
        guard let rootBoundCore else {
            throw CanonicalLibraryMetadataCutoverFailure.rootBoundWriteUnavailable
        }
        let bytes = metadataBytes ?? Self.metadataBytes(for: candidate)
        try await rootBoundCore.setPayload(
            objectID: candidate.objectID,
            objectKind: candidate.objectKind,
            domain: candidate.domain,
            metadataBytes: bytes,
            metadataHash: CanonicalTransportEnvelope.hash(bytes),
            businessModifiedAt: candidate.expectedBusinessModifiedAt,
            logicalPathToken: logicalPathToken,
            actionID: candidate.action.actionID
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

    func rootBoundWriteResult(for actionID: String) async -> CanonicalRootBoundLibraryMetadataWriteResult? {
        await rootBoundCore?.lastWriteResult(actionID: actionID)
    }

    func rootBoundRollbackResult(for checkpointID: String) async -> CanonicalRootBoundLibraryMetadataRollbackResult? {
        await rootBoundCore?.lastRollbackResult(checkpointID: checkpointID)
    }

    func rootBoundLibraryMetadataBytes(
        objectID: String,
        objectKind: CanonicalObjectKind,
        domain: CanonicalLibraryMetadataCutoverDomain
    ) async throws -> Data? {
        try await rootBoundCore?.readMetadataBytes(objectID: objectID, objectKind: objectKind, domain: domain)
    }

    private func writeMetadata(
        _ request: CanonicalProductionApplyExecutionRequest,
        status: CanonicalApplyExecutionStatus,
        summary: String
    ) async throws -> CanonicalProductionApplyResult {
        guard let rootBoundCore else {
            throw CanonicalProductionPortError.productionMutationAttempted("macLibraryMetadataApplyDisabled")
        }
        guard !isDryRunOnly else {
            throw CanonicalProductionPortError.productionMutationAttempted("macLibraryMetadataProductionRootDisabled")
        }
        try failBeforeMutationIfNeeded()
        let inferred = Self.inferKindAndDomain(from: request.action)
        let write = try await rootBoundCore.write(
            action: request.action,
            objectKind: inferred.objectKind,
            domain: inferred.domain,
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
                reason: "macLibraryMetadataPreconditionAccepted"
            ),
            postcondition: CanonicalProductionApplyPostcondition(
                actionID: request.action.actionID,
                target: request.action.target,
                actualHashPrefix: write.hashPrefixAfter,
                accepted: failureInjection != .postconditionMismatch,
                reason: failureInjection == .postconditionMismatch ? "macLibraryMetadataPostconditionMismatch" : "macLibraryMetadataPostconditionAccepted"
            ),
            sideEffect: CanonicalProductionSideEffect(
                kind: .metadataApply,
                domain: write.domain.productionDomain,
                objectID: request.action.target.objectID,
                byteSize: Int64(write.byteCount),
                hashPrefix: write.hashPrefixAfter,
                summary: "\(summary):atomicReplace=\(write.atomicWriteUsed):rollback=\(write.rollbackAvailable):resourceMove=false"
            ),
            rollbackCheckpointID: write.checkpointID
        )
    }

    private func failBeforeMutationIfNeeded() throws {
        switch failureInjection {
        case .applyFailureBeforeCommit, .parentMissing, .cycleDetected, .resourceMoveAttempted, .unsupportedObjectKind, .conflictDetected:
            throw CanonicalProductionPortError.productionMutationAttempted("macLibraryMetadataFailureBeforeMutation")
        case .none, .preconditionMismatch, .postconditionMismatch, .applyFailureAfterPartialCommit, .rollbackFailure:
            break
        }
    }

    private func failAfterMutationIfNeeded() throws {
        if failureInjection == .applyFailureAfterPartialCommit {
            throw CanonicalProductionPortError.productionMutationAttempted("macLibraryMetadataFailureAfterPartialMutation")
        }
    }

    private nonisolated static func inferKindAndDomain(
        from action: CanonicalApplyAction
    ) -> (objectKind: CanonicalObjectKind, domain: CanonicalLibraryMetadataCutoverDomain) {
        switch action.kind {
        case .folderMetadataApply, .folderMetadataSend:
            return (.folder, .folderMetadata)
        case .studyItemMetadataApply, .studyItemMetadataSend:
            return (.standaloneStudyItem, .studyItemMetadata)
        default:
            return (.unknownUnsupported, .studyItemMetadata)
        }
    }

    private nonisolated static func metadataBytes(for candidate: CanonicalLibraryMetadataCutoverCandidate) -> Data {
        let payload: [String: String]
        if let folder = candidate.expectedObject?.folder?.metadata {
            payload = CanonicalProjectionContract.metadataHashPayload(for: folder)
        } else if let item = candidate.expectedObject?.studyItem?.metadata {
            payload = CanonicalProjectionContract.metadataHashPayload(for: item)
        } else {
            payload = [
                "schema": "canonical-library-metadata-v8-10-empty",
                "objectID": candidate.objectID,
                "objectKind": candidate.objectKind.rawValue
            ]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(payload)) ?? Data()
    }
}
