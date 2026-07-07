//
//  CanonicalKernelFacade.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalKernelExecutionMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case dryRun
    case offlineRuntime
    case productionShadow
    case executionShadowDryRun
    case executionShadowWithShadowFileStore
    case executionShadowWithReadOnlyTransportProbe
    case productionExecute

    nonisolated var allowsDryRunPlanning: Bool {
        switch self {
        case .dryRun, .productionShadow, .executionShadowDryRun, .executionShadowWithShadowFileStore,
             .executionShadowWithReadOnlyTransportProbe, .productionExecute:
            return true
        case .disabled, .offlineRuntime:
            return false
        }
    }

    nonisolated var isShadowPreparationMode: Bool {
        switch self {
        case .productionShadow, .executionShadowDryRun, .executionShadowWithShadowFileStore,
             .executionShadowWithReadOnlyTransportProbe:
            return true
        case .disabled, .dryRun, .offlineRuntime, .productionExecute:
            return false
        }
    }
}

nonisolated struct CanonicalKernelConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalKernelExecutionMode
    var productionPolicy: CanonicalProductionExecutionPolicy

    nonisolated init(
        mode: CanonicalKernelExecutionMode = .disabled,
        productionPolicy: CanonicalProductionExecutionPolicy = CanonicalProductionExecutionPolicy()
    ) {
        self.mode = mode
        self.productionPolicy = productionPolicy
    }
}

nonisolated struct CanonicalKernelEnvironment: Sendable {
    var ports: CanonicalProductionPortSet

    nonisolated init(
        ports: CanonicalProductionPortSet = CanonicalProductionPortSet()
    ) {
        self.ports = ports
    }
}

nonisolated enum CanonicalKernelOperation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case buildSnapshot
    case buildManifest
    case planSync
    case buildApplyPlan
    case buildLibraryPlan
    case buildTransferProjection
    case buildObjectProjection
    case buildRuntimeReadiness
    case buildProductionReadiness
    case dryRunMigration
    case compareLegacy
    case executeOffline
    case executeProduction
    case rollbackPreview
}

nonisolated enum CanonicalKernelError: Error, Equatable, Codable, Sendable {
    case disabled(String)
    case modeNotAllowed(String)
    case productionExecutionRejected([CanonicalProductionExecutionRejectionReason])
    case missingInput(String)
    case portMissing(CanonicalProductionPortKind)
    case operationFailed(String)
}

nonisolated struct CanonicalKernelAuditReport: Codable, Equatable, Sendable {
    var operation: CanonicalKernelOperation
    var mode: CanonicalKernelExecutionMode
    var generatedAt: CanonicalTimestamp
    var productionAudit: CanonicalProductionExecutionAudit?
    var sideEffects: [CanonicalProductionSideEffect]
    var diagnostics: [CanonicalProductionDiagnosticsEvent]

    nonisolated init(
        operation: CanonicalKernelOperation,
        mode: CanonicalKernelExecutionMode,
        productionAudit: CanonicalProductionExecutionAudit? = nil,
        sideEffects: [CanonicalProductionSideEffect] = [],
        diagnostics: [CanonicalProductionDiagnosticsEvent] = [],
        generatedAt: Date = Date()
    ) {
        self.operation = operation
        self.mode = mode
        self.generatedAt = CanonicalTimestamp(generatedAt)
        self.productionAudit = productionAudit
        self.sideEffects = sideEffects
        self.diagnostics = diagnostics
    }
}

nonisolated struct CanonicalKernelOperationResult<Payload: Sendable>: Sendable {
    var operation: CanonicalKernelOperation
    var mode: CanonicalKernelExecutionMode
    var payload: Payload?
    var errors: [CanonicalKernelError]
    var audit: CanonicalKernelAuditReport

    nonisolated var succeeded: Bool {
        errors.isEmpty && payload != nil
    }

    nonisolated static func success(
        operation: CanonicalKernelOperation,
        mode: CanonicalKernelExecutionMode,
        payload: Payload,
        audit: CanonicalKernelAuditReport
    ) -> CanonicalKernelOperationResult<Payload> {
        CanonicalKernelOperationResult(operation: operation, mode: mode, payload: payload, errors: [], audit: audit)
    }

    nonisolated static func failure(
        operation: CanonicalKernelOperation,
        mode: CanonicalKernelExecutionMode,
        errors: [CanonicalKernelError],
        audit: CanonicalKernelAuditReport
    ) -> CanonicalKernelOperationResult<Payload> {
        CanonicalKernelOperationResult(operation: operation, mode: mode, payload: nil, errors: errors, audit: audit)
    }
}

nonisolated struct CanonicalKernelInput: Sendable {
    var localSnapshot: CanonicalProductionSnapshot?
    var peerSnapshot: CanonicalProductionSnapshot?
    var trigger: CanonicalSyncPlanTrigger

    nonisolated init(
        localSnapshot: CanonicalProductionSnapshot? = nil,
        peerSnapshot: CanonicalProductionSnapshot? = nil,
        trigger: CanonicalSyncPlanTrigger = .periodic
    ) {
        self.localSnapshot = localSnapshot
        self.peerSnapshot = peerSnapshot
        self.trigger = trigger
    }
}

nonisolated struct CanonicalKernelOutput: Sendable {
    var manifest: CanonicalManifest?
    var syncPlan: CanonicalSyncPlan?
    var applyPlan: CanonicalApplyPlan?
    var libraryPlan: CanonicalLibrarySyncPlan?
    var dryRunPlan: CanonicalDryRunMigrationPlan?
    var productionResult: CanonicalProductionExecutionResult?
}

nonisolated struct CanonicalProductionExecutionStep: Codable, Equatable, Identifiable, Sendable {
    var id: String { stepID }

    var stepID: String
    var kind: CanonicalProductionSideEffectKind
    var domain: CanonicalProductionDomain
    var fileIntent: CanonicalFileWriteIntent?
    var transportRequest: CanonicalProductionTransportBuildRequest?
    var uploadStartRequest: CanonicalUploadStartRequest?
    var uploadChunk: CanonicalUploadChunk?
    var uploadFinalizeRequest: CanonicalUploadFinalizeRequest?
    var applyAction: CanonicalApplyAction?
    var tombstoneRequest: CanonicalProductionTombstoneRequest?

    nonisolated init(
        stepID: String,
        kind: CanonicalProductionSideEffectKind,
        domain: CanonicalProductionDomain,
        fileIntent: CanonicalFileWriteIntent? = nil,
        transportRequest: CanonicalProductionTransportBuildRequest? = nil,
        uploadStartRequest: CanonicalUploadStartRequest? = nil,
        uploadChunk: CanonicalUploadChunk? = nil,
        uploadFinalizeRequest: CanonicalUploadFinalizeRequest? = nil,
        applyAction: CanonicalApplyAction? = nil,
        tombstoneRequest: CanonicalProductionTombstoneRequest? = nil
    ) {
        self.stepID = CanonicalProductionRedaction.safeIdentifier(stepID, fallback: kind.rawValue)
        self.kind = kind
        self.domain = domain
        self.fileIntent = fileIntent
        self.transportRequest = transportRequest
        self.uploadStartRequest = uploadStartRequest
        self.uploadChunk = uploadChunk
        self.uploadFinalizeRequest = uploadFinalizeRequest
        self.applyAction = applyAction
        self.tombstoneRequest = tombstoneRequest
    }
}

nonisolated struct CanonicalProductionExecutionInput: Sendable {
    var operationID: String
    var domains: [CanonicalProductionDomain]
    var steps: [CanonicalProductionExecutionStep]
    var rollbackPlan: CanonicalRollbackPlan?
    var dryRunReportID: String?
    var dryRunEquivalence: CanonicalDryRunEquivalenceReport?
    var readinessReport: CanonicalDryRunReadinessReport?
    var unresolvedConflictCount: Int

    nonisolated init(
        operationID: String,
        domains: [CanonicalProductionDomain],
        steps: [CanonicalProductionExecutionStep],
        rollbackPlan: CanonicalRollbackPlan? = nil,
        dryRunReportID: String? = nil,
        dryRunEquivalence: CanonicalDryRunEquivalenceReport? = nil,
        readinessReport: CanonicalDryRunReadinessReport? = nil,
        unresolvedConflictCount: Int = 0
    ) {
        self.operationID = CanonicalProductionRedaction.safeIdentifier(operationID, fallback: "production-operation")
        self.domains = Array(Set(domains)).sorted { $0.rawValue < $1.rawValue }
        self.steps = steps
        self.rollbackPlan = rollbackPlan
        self.dryRunReportID = dryRunReportID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "dry-run-report") }
        self.dryRunEquivalence = dryRunEquivalence
        self.readinessReport = readinessReport
        self.unresolvedConflictCount = unresolvedConflictCount
    }
}

nonisolated struct CanonicalKernelFacade: Sendable {
    var configuration: CanonicalKernelConfiguration
    var environment: CanonicalKernelEnvironment

    nonisolated init(
        configuration: CanonicalKernelConfiguration = CanonicalKernelConfiguration(),
        environment: CanonicalKernelEnvironment = CanonicalKernelEnvironment()
    ) {
        self.configuration = configuration
        self.environment = environment
    }

    nonisolated func buildSnapshot(_ snapshot: CanonicalProductionSnapshot) -> CanonicalKernelOperationResult<CanonicalProductionSnapshot> {
        success(.buildSnapshot, payload: snapshot)
    }

    nonisolated func buildManifest(from snapshot: CanonicalProductionSnapshot) -> CanonicalKernelOperationResult<CanonicalManifest> {
        success(.buildManifest, payload: snapshot.manifest)
    }

    nonisolated func planSync(
        local: CanonicalManifest,
        peer: CanonicalManifest,
        trigger: CanonicalSyncPlanTrigger
    ) -> CanonicalKernelOperationResult<CanonicalSyncPlan> {
        do {
            return success(.planSync, payload: try CanonicalSyncPlanner().plan(local: local, peer: peer, trigger: trigger))
        } catch {
            return failure(.planSync, error: .operationFailed(String(describing: error)))
        }
    }

    nonisolated func buildApplyPlan(
        local: CanonicalManifest,
        peer: CanonicalManifest,
        syncPlan: CanonicalSyncPlan,
        trigger: CanonicalSyncPlanTrigger
    ) -> CanonicalKernelOperationResult<CanonicalApplyPlan> {
        success(
            .buildApplyPlan,
            payload: CanonicalApplyPlanner().plan(local: local, peer: peer, syncPlan: syncPlan, trigger: trigger)
        )
    }

    nonisolated func buildLibraryPlan(
        local: CanonicalManifest,
        peer: CanonicalManifest,
        trigger: CanonicalSyncPlanTrigger
    ) -> CanonicalKernelOperationResult<CanonicalLibrarySyncPlan> {
        success(.buildLibraryPlan, payload: CanonicalLibrarySyncPlanner().plan(local: local, peer: peer, trigger: trigger))
    }

    nonisolated func buildTransferProjection(
        jobs: [CanonicalTransferJob]
    ) -> CanonicalKernelOperationResult<CanonicalTransferProjection> {
        success(.buildTransferProjection, payload: CanonicalTransferStateMachine.projection(from: jobs))
    }

    nonisolated func buildObjectProjection(
        manifest: CanonicalManifest,
        applyPlan: CanonicalApplyPlan? = nil,
        libraryPlan: CanonicalLibrarySyncPlan? = nil,
        transferProjection: CanonicalTransferProjection? = nil
    ) -> CanonicalKernelOperationResult<CanonicalLibraryProjection> {
        success(
            .buildObjectProjection,
            payload: CanonicalObjectProjectionBuilder.build(
                manifest: manifest,
                applyPlan: applyPlan,
                libraryPlan: libraryPlan,
                transferProjection: transferProjection
            )
        )
    }

    nonisolated func buildRuntimeReadiness(
        evidence: CanonicalRuntimeReadinessEvidence
    ) -> CanonicalKernelOperationResult<CanonicalRuntimeReadinessReport> {
        success(.buildRuntimeReadiness, payload: CanonicalRuntimeReadinessEvaluator().evaluate(evidence: evidence))
    }

    nonisolated func buildProductionReadiness(
        ports: CanonicalProductionPortSet? = nil
    ) -> CanonicalKernelOperationResult<CanonicalProductionPortReadiness> {
        success(.buildProductionReadiness, payload: (ports ?? environment.ports).readiness())
    }

    nonisolated func dryRunMigration(
        local: CanonicalProductionSnapshot,
        peer: CanonicalProductionSnapshot,
        currentRuntimeReadiness: CanonicalRuntimeReadinessReport,
        trigger: CanonicalSyncPlanTrigger,
        context: CanonicalDryRunMigrationContext = CanonicalDryRunMigrationContext()
    ) -> CanonicalKernelOperationResult<CanonicalDryRunMigrationPlan> {
        guard configuration.mode.allowsDryRunPlanning else {
            return failure(.dryRunMigration, error: .modeNotAllowed(configuration.mode.rawValue))
        }
        do {
            let plan = try CanonicalDryRunMigrationPlanner().plan(
                local: local,
                peer: peer,
                ports: environment.ports,
                currentRuntimeReadiness: currentRuntimeReadiness,
                trigger: trigger,
                context: context
            )
            return success(.dryRunMigration, payload: plan)
        } catch {
            return failure(.dryRunMigration, error: .operationFailed(String(describing: error)))
        }
    }

    nonisolated func compareLegacy(
        syncPlan: CanonicalSyncPlan,
        applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan,
        localLegacyActions: CanonicalLegacyActionSnapshot,
        portReadiness: CanonicalProductionPortReadiness
    ) -> CanonicalKernelOperationResult<CanonicalLegacyEquivalenceReport> {
        success(
            .compareLegacy,
            payload: CanonicalDryRunMigrationPlanner.equivalenceReport(
                syncPlan: syncPlan,
                applyPlan: applyPlan,
                libraryPlan: libraryPlan,
                localLegacyActions: localLegacyActions,
                portReadiness: portReadiness
            )
        )
    }

    func executeProduction(
        _ input: CanonicalProductionExecutionInput,
        token: CanonicalProductionExecutionToken?
    ) async -> CanonicalKernelOperationResult<CanonicalProductionExecutionResult> {
        let guardAudit = CanonicalProductionExecutionGuard.evaluate(
            mode: configuration.mode,
            token: token,
            policy: configuration.productionPolicy,
            domains: input.domains,
            ports: environment.ports,
            rollbackPlan: input.rollbackPlan,
            dryRunReportID: input.dryRunReportID,
            dryRunEquivalence: input.dryRunEquivalence,
            readinessReport: input.readinessReport,
            unresolvedConflictCount: input.unresolvedConflictCount
        )
        guard guardAudit.allowed else {
            let result = CanonicalProductionExecutionResult(
                operationID: input.operationID,
                mode: configuration.mode,
                succeeded: false,
                failures: [
                    CanonicalProductionExecutionFailure(
                        operationID: input.operationID,
                        reason: guardAudit.rejectionReasons.map(\.rawValue).joined(separator: ",")
                    )
                ],
                guardAudit: guardAudit
            )
            return CanonicalKernelOperationResult.failure(
                operation: .executeProduction,
                mode: configuration.mode,
                errors: [.productionExecutionRejected(guardAudit.rejectionReasons)],
                audit: CanonicalKernelAuditReport(
                    operation: .executeProduction,
                    mode: configuration.mode,
                    productionAudit: guardAudit
                )
            ).replacingPayload(result)
        }

        var sideEffects: [CanonicalProductionSideEffect] = []
        var failures: [CanonicalProductionExecutionFailure] = []
        for step in input.steps {
            do {
                if let sideEffect = try await execute(step) {
                    sideEffects.append(sideEffect)
                }
            } catch {
                failures.append(CanonicalProductionExecutionFailure(operationID: step.stepID, domain: step.domain, reason: String(describing: error)))
            }
        }

        let result = CanonicalProductionExecutionResult(
            operationID: input.operationID,
            mode: configuration.mode,
            succeeded: failures.isEmpty,
            sideEffects: sideEffects,
            failures: failures,
            guardAudit: guardAudit
        )
        let audit = CanonicalKernelAuditReport(
            operation: .executeProduction,
            mode: configuration.mode,
            productionAudit: guardAudit,
            sideEffects: sideEffects
        )
        return failures.isEmpty
            ? .success(operation: .executeProduction, mode: configuration.mode, payload: result, audit: audit)
            : .failure(operation: .executeProduction, mode: configuration.mode, errors: failures.map { .operationFailed($0.reason) }, audit: audit)
                .replacingPayload(result)
    }

    nonisolated func rollbackPreview(_ plan: CanonicalRollbackPlan?, requiredDomains: [CanonicalProductionDomain]) -> CanonicalKernelOperationResult<CanonicalRollbackAudit> {
        success(.rollbackPreview, payload: CanonicalRollbackAudit(plan: plan, requiredDomains: requiredDomains))
    }

    private func execute(_ step: CanonicalProductionExecutionStep) async throws -> CanonicalProductionSideEffect? {
        switch step.kind {
        case .fileRead:
            guard let intent = step.fileIntent else { throw CanonicalKernelError.missingInput(step.stepID) }
            _ = try await requiredFilePort().readMetadata(CanonicalProductionMetadataReadRequest(objectID: step.stepID, reference: intent.reference))
            return CanonicalProductionSideEffect(kind: .fileRead, domain: step.domain, objectID: step.stepID, summary: "fileRead")
        case .fileWrite:
            guard let intent = step.fileIntent else { throw CanonicalKernelError.missingInput(step.stepID) }
            let result = try await requiredFilePort().writeMetadata(intent, rollbackCheckpoint: nil)
            return CanonicalProductionSideEffect(
                kind: .fileWrite,
                domain: step.domain,
                objectID: step.stepID,
                byteSize: result.evidence.actualByteSize,
                hashPrefix: result.evidence.actualHashPrefix,
                summary: "fileWrite:\(result.disposition.rawValue)"
            )
        case .networkRequest:
            guard let request = step.transportRequest else { throw CanonicalKernelError.missingInput(step.stepID) }
            let exchange = try await requiredTransportPort().sendRequest(try await requiredTransportPort().buildSignedRequest(request))
            return exchange.sideEffect ?? CanonicalProductionSideEffect(kind: .networkRequest, domain: step.domain, route: request.route, summary: "networkRequest")
        case .uploadSessionStart:
            guard let request = step.uploadStartRequest else { throw CanonicalKernelError.missingInput(step.stepID) }
            let status = try await requiredUploadPort().startResumableUpload(request, now: Date())
            return CanonicalProductionSideEffect(kind: .uploadSessionStart, domain: step.domain, objectID: request.objectID, byteSize: status.fileSize, hashPrefix: status.checksum?.value, summary: "uploadSessionStart")
        case .uploadChunkSend:
            guard let chunk = step.uploadChunk else { throw CanonicalKernelError.missingInput(step.stepID) }
            let status = try await requiredUploadPort().uploadChunk(chunk, now: Date())
            return CanonicalProductionSideEffect(kind: .uploadChunkSend, domain: step.domain, objectID: chunk.objectID, byteSize: status.confirmedBytes, hash: chunk.chunkHash, summary: "uploadChunkSend")
        case .uploadFinalize:
            guard let request = step.uploadFinalizeRequest else { throw CanonicalKernelError.missingInput(step.stepID) }
            let status = try await requiredUploadPort().finalizeUpload(request, now: Date())
            return CanonicalProductionSideEffect(kind: .uploadFinalize, domain: step.domain, objectID: request.objectID, byteSize: status.fileSize, hashPrefix: status.checksum?.value, summary: "uploadFinalize")
        case .metadataApply:
            guard let action = step.applyAction else { throw CanonicalKernelError.missingInput(step.stepID) }
            let request = CanonicalProductionApplyExecutionRequest(action: action, rollbackCheckpointID: nil)
            let result: CanonicalProductionApplyResult
            switch action.kind {
            case .recordingMetadataSend, .folderMetadataSend, .studyItemMetadataSend, .libraryTombstoneSend, .objectTombstoneSend:
                result = try await requiredApplyPort().sendMetadata(request)
            default:
                result = try await requiredApplyPort().applyMetadata(request)
            }
            return result.sideEffect ?? CanonicalProductionSideEffect(kind: .metadataApply, domain: step.domain, objectID: action.target.objectID, summary: "metadataApply")
        case .generatedArtifactApply:
            guard let action = step.applyAction else { throw CanonicalKernelError.missingInput(step.stepID) }
            let result = try await requiredApplyPort().applyGeneratedArtifact(CanonicalProductionApplyExecutionRequest(action: action, rollbackCheckpointID: nil))
            return result.sideEffect ?? CanonicalProductionSideEffect(kind: .generatedArtifactApply, domain: step.domain, objectID: action.target.objectID, artifactID: action.target.artifactID, summary: "generatedArtifactApply")
        case .tombstoneMark:
            guard let request = step.tombstoneRequest else { throw CanonicalKernelError.missingInput(step.stepID) }
            let result = try await requiredFilePort().markTombstone(request)
            return CanonicalProductionSideEffect(kind: .tombstoneMark, domain: step.domain, byteSize: result.evidence.actualByteSize, hashPrefix: result.evidence.actualHashPrefix, summary: "tombstoneMark")
        case .conflictRecord:
            guard let action = step.applyAction else { throw CanonicalKernelError.missingInput(step.stepID) }
            let result = try await requiredApplyPort().recordConflict(CanonicalProductionApplyExecutionRequest(action: action, rollbackCheckpointID: nil))
            return result.sideEffect ?? CanonicalProductionSideEffect(kind: .conflictRecord, domain: step.domain, objectID: action.target.objectID, summary: "conflictRecord")
        case .diagnosticsWrite:
            return CanonicalProductionSideEffect(kind: .diagnosticsWrite, domain: step.domain, summary: "diagnosticsWrite")
        }
    }

    private func requiredFilePort() throws -> any CanonicalProductionFilePort {
        guard let file = environment.ports.file else { throw CanonicalKernelError.portMissing(.file) }
        return file
    }

    private func requiredTransportPort() throws -> any CanonicalProductionTransportPort {
        guard let transport = environment.ports.transport else { throw CanonicalKernelError.portMissing(.transport) }
        return transport
    }

    private func requiredUploadPort() throws -> any CanonicalProductionUploadPort {
        guard let upload = environment.ports.upload else { throw CanonicalKernelError.portMissing(.upload) }
        return upload
    }

    private func requiredApplyPort() throws -> any CanonicalProductionApplyPort {
        guard let apply = environment.ports.apply else { throw CanonicalKernelError.portMissing(.apply) }
        return apply
    }

    private nonisolated func success<Payload: Sendable>(
        _ operation: CanonicalKernelOperation,
        payload: Payload
    ) -> CanonicalKernelOperationResult<Payload> {
        .success(
            operation: operation,
            mode: configuration.mode,
            payload: payload,
            audit: CanonicalKernelAuditReport(operation: operation, mode: configuration.mode)
        )
    }

    private nonisolated func failure<Payload: Sendable>(
        _ operation: CanonicalKernelOperation,
        error: CanonicalKernelError
    ) -> CanonicalKernelOperationResult<Payload> {
        .failure(
            operation: operation,
            mode: configuration.mode,
            errors: [error],
            audit: CanonicalKernelAuditReport(operation: operation, mode: configuration.mode)
        )
    }
}

private extension CanonicalKernelOperationResult {
    nonisolated func replacingPayload(_ payload: Payload) -> CanonicalKernelOperationResult<Payload> {
        CanonicalKernelOperationResult(
            operation: operation,
            mode: mode,
            payload: payload,
            errors: errors,
            audit: audit
        )
    }
}
