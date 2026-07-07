//
//  CanonicalExecutionShadow.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalShadowRootKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case temporary
    case shadowCopy
    case productionRootRejected
}

nonisolated struct CanonicalShadowRootBinding: Codable, Equatable, Sendable {
    var rootToken: CanonicalRootToken
    var rootKind: CanonicalShadowRootKind
    var rootURL: URL?
    var prohibitedProductionRootURL: URL?

    nonisolated init(
        rootToken: CanonicalRootToken,
        rootKind: CanonicalShadowRootKind,
        rootURL: URL? = nil,
        prohibitedProductionRootURL: URL? = nil
    ) {
        self.rootToken = rootToken
        self.rootKind = rootKind
        self.rootURL = rootURL?.standardizedFileURL
        self.prohibitedProductionRootURL = prohibitedProductionRootURL?.standardizedFileURL
    }

    nonisolated func validatedShadowRootURL() throws -> URL {
        guard rootKind != .productionRootRejected else {
            throw CanonicalProductionPortError.productionMutationAttempted("shadowProductionRootRejected")
        }
        guard let rootURL else {
            throw CanonicalFileRuntimeError.rootNotBound(rootToken.rawValue)
        }
        let standardized = rootURL.standardizedFileURL
        guard standardized.isFileURL else {
            throw CanonicalProductionPortError.pathEscapeRisk("shadowRootMustBeFileURL")
        }
        guard let prohibitedProductionRootURL else {
            return standardized
        }
        let production = prohibitedProductionRootURL.standardizedFileURL
        let shadowPath = standardized.path
        let productionPath = production.path
        guard shadowPath != productionPath,
              !shadowPath.hasPrefix(productionPath + "/") else {
            throw CanonicalProductionPortError.productionMutationAttempted("shadowRootInsideProductionRootRejected")
        }
        return standardized
    }
}

nonisolated struct CanonicalShadowCopyPolicy: Codable, Equatable, Sendable {
    var maxBytes: Int64
    var allowMetadataBytes: Bool
    var allowArtifactBytes: Bool
    var allowTombstoneMarkers: Bool
    var noPhysicalDelete: Bool

    nonisolated init(
        maxBytes: Int64 = 8 * 1024 * 1024,
        allowMetadataBytes: Bool = true,
        allowArtifactBytes: Bool = true,
        allowTombstoneMarkers: Bool = true,
        noPhysicalDelete: Bool = true
    ) {
        self.maxBytes = max(0, maxBytes)
        self.allowMetadataBytes = allowMetadataBytes
        self.allowArtifactBytes = allowArtifactBytes
        self.allowTombstoneMarkers = allowTombstoneMarkers
        self.noPhysicalDelete = noPhysicalDelete
    }
}

nonisolated struct CanonicalShadowCopyEntry: Codable, Equatable, Identifiable, Sendable {
    var id: String { [reference.rootToken.rawValue, reference.logicalPathToken, purpose.rawValue].joined(separator: "|") }

    var reference: CanonicalFileReference
    var purpose: CanonicalFilePurpose
    var byteSize: Int64
    var contentHashPrefix: String?
    var copiedToShadowRoot: Bool
    var reason: String?

    nonisolated init(
        reference: CanonicalFileReference,
        purpose: CanonicalFilePurpose,
        byteSize: Int64,
        contentHash: CanonicalHash? = nil,
        copiedToShadowRoot: Bool,
        reason: String? = nil
    ) {
        self.reference = reference
        self.purpose = purpose
        self.byteSize = max(0, byteSize)
        self.contentHashPrefix = contentHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.copiedToShadowRoot = copiedToShadowRoot
        self.reason = CanonicalShadowMigrationRedaction.safeText(reason)
    }
}

nonisolated struct CanonicalShadowCopyManifest: Codable, Equatable, Sendable {
    var rootKind: CanonicalShadowRootKind
    var rootToken: CanonicalRootToken
    var entries: [CanonicalShadowCopyEntry]
    var totalBytes: Int64
    var missingSourceBytesCount: Int

    nonisolated init(
        rootKind: CanonicalShadowRootKind,
        rootToken: CanonicalRootToken,
        entries: [CanonicalShadowCopyEntry] = [],
        missingSourceBytesCount: Int = 0
    ) {
        self.rootKind = rootKind
        self.rootToken = rootToken
        self.entries = entries.sorted { $0.id < $1.id }
        self.totalBytes = entries.reduce(0) { $0 + $1.byteSize }
        self.missingSourceBytesCount = max(0, missingSourceBytesCount)
    }
}

nonisolated struct CanonicalShadowFileExecutionReport: Codable, Equatable, Sendable {
    var rootKind: CanonicalShadowRootKind
    var entryCount: Int
    var bytesCopied: Int64
    var wroteToShadowRoot: Bool
    var wroteProductionRoot: Bool
    var physicalDeletePerformed: Bool
    var rollbackAvailable: Bool
    var missingSourceBytesCount: Int
    var rejectedReason: String?

    nonisolated init(
        rootKind: CanonicalShadowRootKind,
        manifest: CanonicalShadowCopyManifest? = nil,
        wroteToShadowRoot: Bool = false,
        wroteProductionRoot: Bool = false,
        physicalDeletePerformed: Bool = false,
        rollbackAvailable: Bool = false,
        missingSourceBytesCount: Int = 0,
        rejectedReason: String? = nil
    ) {
        self.rootKind = rootKind
        self.entryCount = manifest?.entries.count ?? 0
        self.bytesCopied = manifest?.totalBytes ?? 0
        self.wroteToShadowRoot = wroteToShadowRoot
        self.wroteProductionRoot = wroteProductionRoot
        self.physicalDeletePerformed = physicalDeletePerformed
        self.rollbackAvailable = rollbackAvailable
        self.missingSourceBytesCount = max(0, missingSourceBytesCount + (manifest?.missingSourceBytesCount ?? 0))
        self.rejectedReason = CanonicalShadowMigrationRedaction.safeText(rejectedReason)
    }
}

actor CanonicalShadowFileStore: CanonicalFileStorePort {
    nonisolated let rootToken: CanonicalRootToken
    nonisolated let rootKind: CanonicalShadowRootKind
    nonisolated let policy: CanonicalShadowCopyPolicy

    private let store: InMemoryCanonicalFileStore
    private var entries: [CanonicalShadowCopyEntry] = []
    private var missingSourceBytesCount = 0

    init(
        rootToken: CanonicalRootToken = CanonicalRootToken("canonical-shadow-root"),
        rootKind: CanonicalShadowRootKind = .temporary,
        policy: CanonicalShadowCopyPolicy = CanonicalShadowCopyPolicy()
    ) {
        self.rootToken = rootToken
        self.rootKind = rootKind
        self.policy = policy
        self.store = InMemoryCanonicalFileStore(rootBindings: [rootToken: "canonical-shadow-root"])
    }

    func resolve(_ reference: CanonicalFileReference) async throws -> CanonicalPathResolutionResult {
        try await store.resolve(reference)
    }

    func read(_ request: CanonicalFileReadRequest) async throws -> CanonicalFileReadResult {
        try await store.read(request)
    }

    @discardableResult
    func write(_ intent: CanonicalFileWriteIntent) async throws -> CanonicalFileWriteResult {
        try validate(intent)
        let result = try await store.write(intent)
        entries.append(
            CanonicalShadowCopyEntry(
                reference: intent.reference,
                purpose: intent.purpose,
                byteSize: result.byteSize,
                contentHash: result.contentHash,
                copiedToShadowRoot: true,
                reason: result.disposition.rawValue
            )
        )
        return result
    }

    @discardableResult
    func markTombstone(_ reference: CanonicalFileReference, reason: String?) async throws -> CanonicalFileWriteResult {
        guard policy.allowTombstoneMarkers else {
            throw CanonicalProductionPortError.productionMutationAttempted("shadowTombstoneMarkerDisabled")
        }
        let result = try await store.markTombstone(reference, reason: reason)
        entries.append(
            CanonicalShadowCopyEntry(
                reference: reference,
                purpose: .tombstoneMarker,
                byteSize: result.byteSize,
                contentHash: result.contentHash,
                copiedToShadowRoot: true,
                reason: "noPhysicalDelete"
            )
        )
        return result
    }

    func contains(_ reference: CanonicalFileReference) async throws -> Bool {
        try await store.contains(reference)
    }

    func report() -> CanonicalShadowFileExecutionReport {
        CanonicalShadowFileExecutionReport(
            rootKind: rootKind,
            manifest: CanonicalShadowCopyManifest(
                rootKind: rootKind,
                rootToken: rootToken,
                entries: entries,
                missingSourceBytesCount: missingSourceBytesCount
            ),
            wroteToShadowRoot: !entries.isEmpty,
            wroteProductionRoot: false,
            physicalDeletePerformed: false,
            rollbackAvailable: !entries.isEmpty,
            missingSourceBytesCount: missingSourceBytesCount
        )
    }

    func recordMissingSourceBytes() {
        missingSourceBytesCount += 1
    }

    private func validate(_ intent: CanonicalFileWriteIntent) throws {
        guard intent.reference.rootToken == rootToken else {
            throw CanonicalFileRuntimeError.rootNotBound(intent.reference.rootToken.rawValue)
        }
        guard policy.maxBytes == 0 || Int64(intent.bytes.count) <= policy.maxBytes else {
            throw CanonicalFileRuntimeError.preWriteSizeMismatch(expected: policy.maxBytes, actual: Int64(intent.bytes.count))
        }
        switch intent.purpose {
        case .metadataBlob:
            guard policy.allowMetadataBytes else {
                throw CanonicalProductionPortError.fullContentRejected("shadowMetadataBytesDisabled")
            }
        case .artifactBytes, .generatedArtifact:
            guard policy.allowArtifactBytes else {
                throw CanonicalProductionPortError.fullContentRejected("shadowArtifactBytesDisabled")
            }
        case .tombstoneMarker:
            guard policy.allowTombstoneMarkers else {
                throw CanonicalProductionPortError.productionMutationAttempted("shadowTombstoneMarkerDisabled")
            }
        }
    }
}

nonisolated enum CanonicalShadowRouteClassification: String, Codable, Equatable, Hashable, Sendable {
    case readOnly
    case mutating
    case unknown
}

nonisolated struct CanonicalShadowRoutePolicy: Codable, Equatable, Sendable {
    var artifactRequestMaxBytes: Int

    nonisolated init(artifactRequestMaxBytes: Int = 256 * 1024) {
        self.artifactRequestMaxBytes = max(0, artifactRequestMaxBytes)
    }

    nonisolated func classification(for route: CanonicalTransportRoute, bodyByteCount: Int = 0) -> CanonicalShadowRouteClassification {
        switch route {
        case .manifestExchange:
            return .readOnly
        case .fileRead:
            return bodyByteCount <= artifactRequestMaxBytes ? .readOnly : .mutating
        case .applyPlan, .applyMetadata, .uploadStart, .uploadStatus, .uploadChunk, .uploadFinalize:
            return .mutating
        }
    }

    nonisolated func probeKind(for route: CanonicalTransportRoute) -> CanonicalShadowNetworkProbeKind {
        switch route {
        case .manifestExchange:
            return .syncInventoryReadOnly
        case .fileRead:
            return .artifactRequestReadOnly
        case .applyPlan, .applyMetadata:
            return .applyManifest
        case .uploadStart:
            return .uploadSessionStart
        case .uploadStatus:
            return .uploadSessionStart
        case .uploadChunk:
            return .uploadSessionChunk
        case .uploadFinalize:
            return .uploadSessionFinalize
        }
    }
}

nonisolated struct CanonicalShadowTransportEnvelopeReport: Codable, Equatable, Sendable {
    var route: CanonicalTransportRoute
    var routePath: String
    var classification: CanonicalShadowRouteClassification
    var bodyHashPrefix: String?
    var timestampPresent: Bool
    var noncePresent: Bool
    var signatureProjectionPresent: Bool
    var wouldSendNetwork: Bool
    var sentNetwork: Bool
    var reason: String

    nonisolated init(
        signedRequest: CanonicalProductionSignedRequest,
        classification: CanonicalShadowRouteClassification,
        wouldSendNetwork: Bool,
        sentNetwork: Bool,
        reason: String
    ) {
        self.route = signedRequest.buildRequest.route
        self.routePath = CanonicalShadowMigrationRedaction.safeText(signedRequest.buildRequest.existingRoutePath) ?? signedRequest.buildRequest.route.rawValue
        self.classification = classification
        self.bodyHashPrefix = CanonicalProductionRedaction.hashPrefix(signedRequest.bodyHash.value)
        self.timestampPresent = true
        self.noncePresent = !signedRequest.buildRequest.nonce.isEmpty
        self.signatureProjectionPresent = signedRequest.signaturePrefix != nil || signedRequest.signerDescription != nil
        self.wouldSendNetwork = wouldSendNetwork
        self.sentNetwork = sentNetwork
        self.reason = CanonicalShadowMigrationRedaction.safeText(reason) ?? "shadowTransportProjection"
    }
}

nonisolated struct CanonicalShadowTransportProbeResult: Codable, Equatable, Sendable {
    var policyDecision: CanonicalShadowNetworkProbeDecision
    var envelopeReport: CanonicalShadowTransportEnvelopeReport
    var accepted: Bool
    var sentNetwork: Bool
    var failureReason: String?

    nonisolated init(
        policyDecision: CanonicalShadowNetworkProbeDecision,
        envelopeReport: CanonicalShadowTransportEnvelopeReport,
        accepted: Bool,
        sentNetwork: Bool,
        failureReason: String? = nil
    ) {
        self.policyDecision = policyDecision
        self.envelopeReport = envelopeReport
        self.accepted = accepted
        self.sentNetwork = sentNetwork
        self.failureReason = CanonicalShadowMigrationRedaction.safeText(failureReason)
    }
}

nonisolated struct CanonicalShadowTransportProbe: Sendable {
    var routePolicy: CanonicalShadowRoutePolicy

    nonisolated init(routePolicy: CanonicalShadowRoutePolicy = CanonicalShadowRoutePolicy()) {
        self.routePolicy = routePolicy
    }

    func project(
        request: CanonicalProductionTransportBuildRequest,
        transport: any CanonicalProductionTransportPort,
        networkPolicy: CanonicalShadowNetworkProbePolicy,
        allowNetworkSend: Bool = false
    ) async throws -> CanonicalShadowTransportProbeResult {
        let classification = routePolicy.classification(for: request.route, bodyByteCount: request.body.count)
        let probeRequest = CanonicalShadowNetworkProbeRequest(
            kind: routePolicy.probeKind(for: request.route),
            routePath: request.existingRoutePath,
            bodyByteCount: request.body.count,
            artifactByteLimit: routePolicy.artifactRequestMaxBytes
        )
        let decision = networkPolicy.decision(for: probeRequest)
        let signed = try await transport.buildSignedRequest(request)
        let maySend = allowNetworkSend && decision.accepted && classification == .readOnly && transport.realNetworkExecutionEnabled
        var sent = false
        var failureReason: String?
        if maySend {
            _ = try await transport.sendRequest(signed)
            sent = true
        } else if decision.accepted {
            failureReason = "networkSendSuppressedShadow"
        } else {
            failureReason = decision.reason
        }
        let envelope = CanonicalShadowTransportEnvelopeReport(
            signedRequest: signed,
            classification: classification,
            wouldSendNetwork: decision.accepted,
            sentNetwork: sent,
            reason: failureReason ?? decision.reason
        )
        return CanonicalShadowTransportProbeResult(
            policyDecision: decision,
            envelopeReport: envelope,
            accepted: decision.accepted,
            sentNetwork: sent,
            failureReason: failureReason
        )
    }
}

nonisolated struct CanonicalShadowUploadSession: Codable, Equatable, Sendable {
    var sessionID: CanonicalUploadSessionID?
    var confirmedBytes: Int64
    var phase: CanonicalUploadSessionPhase
}

nonisolated final class CanonicalShadowUploadReceiver: @unchecked Sendable {
    let store: InMemoryCanonicalFileStore
    let rootToken: CanonicalRootToken

    nonisolated init(rootToken: CanonicalRootToken = CanonicalRootToken("canonical-shadow-upload-root")) {
        self.rootToken = rootToken
        self.store = InMemoryCanonicalFileStore(rootBindings: [rootToken: "canonical-shadow-upload-root"])
    }

    func seed(reference: CanonicalFileReference, bytes: Data) async throws {
        let hash = InMemoryCanonicalFileStore.hash(bytes, policy: .sha256)
        _ = try await store.write(
            CanonicalFileWriteIntent(
                reference: reference,
                bytes: bytes,
                purpose: .artifactBytes,
                expectedContentHash: hash,
                expectedByteSize: Int64(bytes.count),
                conflictPolicy: .replace
            )
        )
    }

    func read(reference: CanonicalFileReference) async throws -> CanonicalFileReadResult {
        try await store.read(CanonicalFileReadRequest(reference: reference))
    }
}

nonisolated enum CanonicalShadowUploadDivergence: String, Codable, Equatable, Sendable {
    case none
    case sameHashNoOp
    case differentHashConflict
    case finalizeHashMismatch
    case interruptedAndResumed
    case unexpectedFailure
}

nonisolated struct CanonicalShadowUploadRehearsalInput: Sendable {
    var objectID: String
    var targetReference: CanonicalFileReference
    var bytes: Data
    var chunkSize: Int
    var declaredTotalHash: CanonicalHash?
    var existingReceiverBytes: Data?
    var simulateInterruptionAfterFirstChunk: Bool

    nonisolated init(
        objectID: String,
        targetReference: CanonicalFileReference,
        bytes: Data,
        chunkSize: Int = 4 * 1024 * 1024,
        declaredTotalHash: CanonicalHash? = nil,
        existingReceiverBytes: Data? = nil,
        simulateInterruptionAfterFirstChunk: Bool = false
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.targetReference = targetReference
        self.bytes = bytes
        self.chunkSize = max(1, chunkSize)
        self.declaredTotalHash = declaredTotalHash
        self.existingReceiverBytes = existingReceiverBytes
        self.simulateInterruptionAfterFirstChunk = simulateInterruptionAfterFirstChunk
    }
}

nonisolated struct CanonicalShadowUploadResult: Codable, Equatable, Sendable {
    var session: CanonicalShadowUploadSession?
    var calledProductionUploadCoordinator: Bool
    var calledRecordingUploadClient: Bool
    var calledSecureMacUploadClient: Bool
    var wroteProductionInbox: Bool
    var wroteReceiveJSON: Bool
    var wroteShadowReceiver: Bool
    var completed: Bool
    var confirmedBytes: Int64
    var phase: CanonicalUploadSessionPhase
    var divergence: CanonicalShadowUploadDivergence
    var failureReason: String?
}

nonisolated struct CanonicalShadowUploadRehearsal: Sendable {
    nonisolated init() {}

    func run(
        input: CanonicalShadowUploadRehearsalInput,
        receiver: CanonicalShadowUploadReceiver = CanonicalShadowUploadReceiver(),
        now: Date = Date()
    ) async -> CanonicalShadowUploadResult {
        do {
            if let existingReceiverBytes = input.existingReceiverBytes {
                try await receiver.seed(reference: input.targetReference, bytes: existingReceiverBytes)
            }
            let runtime = CanonicalResumableUploadRuntime(fileStore: receiver.store)
            let actualHash = InMemoryCanonicalFileStore.hash(input.bytes, policy: .sha256) ?? CanonicalHash.sha256String("")
            let totalHash = input.declaredTotalHash ?? actualHash
            let start = try await runtime.start(
                CanonicalUploadStartRequest(
                    objectID: input.objectID,
                    targetReference: input.targetReference,
                    totalBytes: Int64(input.bytes.count),
                    totalHash: totalHash,
                    chunkSize: input.chunkSize
                ),
                now: now
            )
            if start.completed {
                return result(
                    status: start,
                    wroteShadowReceiver: false,
                    divergence: .sameHashNoOp
                )
            }
            let sessionID = try requiredSessionID(start)
            var offset = 0
            var interrupted = false
            while offset < input.bytes.count {
                let upper = min(offset + input.chunkSize, input.bytes.count)
                let chunkBytes = input.bytes.subdata(in: offset..<upper)
                let chunkHash = InMemoryCanonicalFileStore.hash(chunkBytes, policy: .sha256) ?? CanonicalHash.sha256String("")
                _ = try await runtime.append(
                    CanonicalUploadChunk(
                        objectID: input.objectID,
                        sessionID: sessionID,
                        offset: Int64(offset),
                        bytes: chunkBytes,
                        chunkHash: chunkHash,
                        totalHash: totalHash,
                        idempotencyKey: "shadow-\(offset)"
                    ),
                    now: now
                )
                offset = upper
                if input.simulateInterruptionAfterFirstChunk, !interrupted {
                    interrupted = true
                    _ = try await runtime.status(
                        CanonicalUploadStatusRequest(objectID: input.objectID, sessionID: sessionID, totalHash: totalHash),
                        now: now
                    )
                }
            }
            let finalized = try await runtime.finalize(
                CanonicalUploadFinalizeRequest(
                    objectID: input.objectID,
                    sessionID: sessionID,
                    totalBytes: Int64(input.bytes.count),
                    totalHash: totalHash
                ),
                now: now
            )
            return result(
                status: finalized,
                wroteShadowReceiver: true,
                divergence: interrupted ? .interruptedAndResumed : .none
            )
        } catch let error as CanonicalUploadRuntimeError {
            switch error {
            case .finalHashMismatch:
                return failedResult(phase: .conflict, divergence: .finalizeHashMismatch, reason: "finalHashMismatch")
            case .targetConflict:
                return failedResult(phase: .conflict, divergence: .differentHashConflict, reason: "targetConflict")
            default:
                return failedResult(phase: .failed, divergence: .unexpectedFailure, reason: String(describing: error))
            }
        } catch {
            return failedResult(phase: .failed, divergence: .unexpectedFailure, reason: String(describing: error))
        }
    }

    private nonisolated func requiredSessionID(_ status: CanonicalUploadSessionStatus) throws -> CanonicalUploadSessionID {
        guard let sessionID = status.sessionID else {
            throw CanonicalUploadRuntimeError.invalidSession("shadowSessionMissing")
        }
        return sessionID
    }

    private nonisolated func result(
        status: CanonicalUploadSessionStatus,
        wroteShadowReceiver: Bool,
        divergence: CanonicalShadowUploadDivergence
    ) -> CanonicalShadowUploadResult {
        CanonicalShadowUploadResult(
            session: CanonicalShadowUploadSession(
                sessionID: status.sessionID,
                confirmedBytes: status.confirmedBytes,
                phase: status.phase
            ),
            calledProductionUploadCoordinator: false,
            calledRecordingUploadClient: false,
            calledSecureMacUploadClient: false,
            wroteProductionInbox: false,
            wroteReceiveJSON: false,
            wroteShadowReceiver: wroteShadowReceiver,
            completed: status.completed,
            confirmedBytes: status.confirmedBytes,
            phase: status.phase,
            divergence: divergence,
            failureReason: nil
        )
    }

    private nonisolated func failedResult(
        phase: CanonicalUploadSessionPhase,
        divergence: CanonicalShadowUploadDivergence,
        reason: String
    ) -> CanonicalShadowUploadResult {
        CanonicalShadowUploadResult(
            session: nil,
            calledProductionUploadCoordinator: false,
            calledRecordingUploadClient: false,
            calledSecureMacUploadClient: false,
            wroteProductionInbox: false,
            wroteReceiveJSON: false,
            wroteShadowReceiver: false,
            completed: false,
            confirmedBytes: 0,
            phase: phase,
            divergence: divergence,
            failureReason: CanonicalShadowMigrationRedaction.safeText(reason)
        )
    }
}

actor CanonicalShadowUploadPort: CanonicalProductionUploadPort {
    nonisolated let isDryRunOnly = false
    nonisolated let resumableSessionSupported = true
    nonisolated let chunkSizePolicy: Int

    private let runtime: CanonicalResumableUploadRuntime
    private var ledgers: [String: CanonicalProductionUploadLedgerSnapshot] = [:]

    init(
        receiver: CanonicalShadowUploadReceiver = CanonicalShadowUploadReceiver(),
        chunkSizePolicy: Int = 4 * 1024 * 1024
    ) {
        self.chunkSizePolicy = max(1, chunkSizePolicy)
        self.runtime = CanonicalResumableUploadRuntime(fileStore: receiver.store)
    }

    func startResumableUpload(_ request: CanonicalUploadStartRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        guard request.chunkSize <= chunkSizePolicy else {
            throw CanonicalUploadRuntimeError.invalidRequest("shadowChunkSizeExceedsPolicy")
        }
        let status = try await runtime.start(request, now: now)
        ledgers[request.objectID] = ledger(objectID: request.objectID, status: status, totalBytes: request.totalBytes, totalHash: request.totalHash)
        return status
    }

    func resumeUpload(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        let status = try await runtime.status(request, now: now)
        ledgers[request.objectID] = ledger(objectID: request.objectID, status: status, totalBytes: status.fileSize, totalHash: status.checksum ?? request.totalHash)
        return status
    }

    func uploadChunk(_ chunk: CanonicalUploadChunk, now: Date) async throws -> CanonicalUploadSessionStatus {
        let status = try await runtime.append(chunk, now: now)
        ledgers[chunk.objectID] = ledger(objectID: chunk.objectID, status: status, totalBytes: nil, totalHash: chunk.totalHash)
        return status
    }

    func queryConfirmedBytes(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> Int64 {
        try await resumeUpload(request, now: now).confirmedBytes
    }

    func finalizeUpload(_ request: CanonicalUploadFinalizeRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        let status = try await runtime.finalize(request, now: now)
        ledgers[request.objectID] = ledger(objectID: request.objectID, status: status, totalBytes: request.totalBytes, totalHash: request.totalHash)
        return status
    }

    func cancelUpload(_ request: CanonicalProductionUploadCancelRequest, now: Date) async throws -> CanonicalRollbackResult {
        ledgers[request.objectID] = CanonicalProductionUploadLedgerSnapshot(
            objectID: request.objectID,
            sessionID: request.sessionID,
            confirmedBytes: 0,
            phase: .failed
        )
        return CanonicalRollbackResult(planID: request.sessionID.rawValue, succeeded: true, completedActionIDs: [request.sessionID.rawValue])
    }

    nonisolated func classifyUploadFailure(_ failure: CanonicalProductionUploadFailure) -> CanonicalProductionUploadFailureClassification {
        let code = failure.code.lowercased()
        if code.contains("conflict") || code == "409" {
            return CanonicalProductionUploadFailureClassification(kind: .conflict, retry: nil, reason: "shadowUploadConflict")
        }
        if code.contains("timeout") || code.contains("network") || code.contains("retry") {
            return CanonicalProductionUploadFailureClassification(
                kind: .retryable,
                retry: CanonicalRetryPolicySnapshot(retryCount: 1, nextRetryAt: nil, maxAttempts: 3),
                reason: "shadowUploadRetryable"
            )
        }
        return CanonicalProductionUploadFailureClassification(kind: .fatal, retry: nil, reason: failure.code)
    }

    func readUploadLedger(objectID: String) async throws -> CanonicalProductionUploadLedgerSnapshot {
        ledgers[CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")]
            ?? CanonicalProductionUploadLedgerSnapshot(objectID: objectID)
    }

    func writeUploadLedger(_ snapshot: CanonicalProductionUploadLedgerSnapshot) async throws -> CanonicalProductionUploadLedgerSnapshot {
        ledgers[snapshot.objectID] = snapshot
        return snapshot
    }

    nonisolated func projectRetry(_ snapshot: CanonicalProductionUploadLedgerSnapshot, now: Date) -> CanonicalRetryPolicySnapshot? {
        snapshot.retry
    }

    func rollbackUploadState(_ request: CanonicalProductionUploadRollbackRequest) async throws -> CanonicalRollbackResult {
        ledgers[request.objectID] = CanonicalProductionUploadLedgerSnapshot(objectID: request.objectID)
        return CanonicalRollbackResult(planID: request.checkpointID, succeeded: true, completedActionIDs: [request.objectID])
    }

    nonisolated func projectUploadDryRun(
        object: CanonicalRecordingObject,
        artifact: CanonicalArtifact
    ) async throws -> CanonicalProductionUploadTrace {
        guard artifact.kind == .audio else {
            throw CanonicalProductionPortError.unsupportedObject("shadowUploadOnlySupportsAudio")
        }
        return CanonicalProductionUploadTrace(
            objectID: object.objectID,
            artifactID: artifact.artifactID,
            totalBytes: artifact.byteSize,
            totalHash: artifact.contentHash,
            chunkSize: chunkSizePolicy,
            resumable: true,
            route: .uploadStart,
            reason: "shadowReceiverOnly"
        )
    }

    private nonisolated func ledger(
        objectID: String,
        status: CanonicalUploadSessionStatus,
        totalBytes: Int64?,
        totalHash: CanonicalHash?
    ) -> CanonicalProductionUploadLedgerSnapshot {
        CanonicalProductionUploadLedgerSnapshot(
            objectID: objectID,
            sessionID: status.sessionID,
            confirmedBytes: status.confirmedBytes,
            totalBytes: totalBytes,
            contentHash: totalHash,
            phase: status.phase,
            retry: status.retry
        )
    }
}

nonisolated final class CanonicalShadowApplyStore: @unchecked Sendable {
    let localFileStore: InMemoryCanonicalFileStore
    let peerFileStore: InMemoryCanonicalFileStore
    let localMetadataRoot: CanonicalRootToken
    let peerMetadataRoot: CanonicalRootToken
    let localGeneratedRoot: CanonicalRootToken
    let peerGeneratedRoot: CanonicalRootToken

    nonisolated init(
        localMetadataRoot: CanonicalRootToken = CanonicalRootToken("shadow-local-metadata"),
        peerMetadataRoot: CanonicalRootToken = CanonicalRootToken("shadow-peer-metadata"),
        localGeneratedRoot: CanonicalRootToken = CanonicalRootToken("shadow-local-generated"),
        peerGeneratedRoot: CanonicalRootToken = CanonicalRootToken("shadow-peer-generated")
    ) {
        self.localMetadataRoot = localMetadataRoot
        self.peerMetadataRoot = peerMetadataRoot
        self.localGeneratedRoot = localGeneratedRoot
        self.peerGeneratedRoot = peerGeneratedRoot
        self.localFileStore = InMemoryCanonicalFileStore(rootBindings: [
            localMetadataRoot: "shadow/local/metadata",
            localGeneratedRoot: "shadow/local/generated"
        ])
        self.peerFileStore = InMemoryCanonicalFileStore(rootBindings: [
            peerMetadataRoot: "shadow/peer/metadata",
            peerGeneratedRoot: "shadow/peer/generated"
        ])
    }

    nonisolated func makeContext(localManifest: CanonicalManifest, peerManifest: CanonicalManifest) -> CanonicalApplyRuntimeContext {
        CanonicalApplyRuntimeContext(
            localManifest: localManifest,
            peerManifest: peerManifest,
            localFileStore: localFileStore,
            peerFileStore: peerFileStore,
            localMetadataRoot: localMetadataRoot,
            peerMetadataRoot: peerMetadataRoot,
            localGeneratedRoot: localGeneratedRoot,
            peerGeneratedRoot: peerGeneratedRoot
        )
    }
}

nonisolated enum CanonicalShadowApplyDivergence: String, Codable, Equatable, Sendable {
    case none
    case failedAction
    case rollbackFailed
    case conflictRecorded
}

nonisolated struct CanonicalShadowApplyResult: Codable, Equatable, Sendable {
    var executionReport: CanonicalApplyExecutionReport
    var calledApplySyncManifest: Bool
    var calledArtifactApply: Bool
    var wroteProductionStore: Bool
    var wroteShadowStore: Bool
    var tombstonePhysicalDelete: Bool
    var postconditionVerified: Bool
    var rollbackResult: CanonicalRollbackResult?
    var divergence: CanonicalShadowApplyDivergence
}

nonisolated struct CanonicalShadowApplyRehearsal: Sendable {
    nonisolated init() {}

    func run(
        applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan? = nil,
        localManifest: CanonicalManifest,
        peerManifest: CanonicalManifest,
        store: CanonicalShadowApplyStore = CanonicalShadowApplyStore()
    ) async -> CanonicalShadowApplyResult {
        let report = await CanonicalApplyExecutor().execute(
            applyPlan: applyPlan,
            libraryPlan: libraryPlan,
            context: store.makeContext(localManifest: localManifest, peerManifest: peerManifest)
        )
        let rollback = CanonicalRollbackResult(
            planID: "shadow-apply-rollback",
            succeeded: true,
            completedActionIDs: report.records.map(\.actionID)
        )
        let divergence: CanonicalShadowApplyDivergence
        if report.failedCount > 0 {
            divergence = .failedAction
        } else if report.conflictReport.unresolvedCount > 0 {
            divergence = .conflictRecorded
        } else {
            divergence = .none
        }
        return CanonicalShadowApplyResult(
            executionReport: report,
            calledApplySyncManifest: false,
            calledArtifactApply: false,
            wroteProductionStore: false,
            wroteShadowStore: !report.records.isEmpty,
            tombstonePhysicalDelete: false,
            postconditionVerified: report.failedCount == 0,
            rollbackResult: rollback,
            divergence: divergence
        )
    }
}

actor CanonicalShadowApplyPort: CanonicalProductionApplyPort {
    nonisolated let isDryRunOnly = false
    nonisolated let metadataApplySupported = true
    nonisolated let generatedArtifactApplySupported = true
    nonisolated let tombstoneApplySupported = true
    nonisolated let conflictRecordSupported = true

    private var results: [String: CanonicalProductionApplyResult] = [:]
    private var tombstones: Set<String> = []
    private var conflicts: Set<String> = []

    init() {}

    func applyMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        recordResult(request: request, status: .applied, sideEffectKind: .metadataApply, summary: "shadowMetadataApply")
    }

    func sendMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        recordResult(request: request, status: .sent, sideEffectKind: .metadataApply, summary: "shadowMetadataSend")
    }

    func applyGeneratedArtifact(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        guard request.action.target.artifactID != nil else {
            throw CanonicalProductionPortError.unsupportedObject("shadowGeneratedArtifactMissingID")
        }
        return recordResult(request: request, status: .applied, sideEffectKind: .generatedArtifactApply, summary: "shadowGeneratedArtifactApply")
    }

    func requestGeneratedArtifact(_ request: CanonicalProductionArtifactRequest) async throws -> CanonicalProductionApplyResult {
        let action = CanonicalApplyAction(
            kind: .generatedArtifactDownloadApply,
            source: .peer,
            target: CanonicalApplyTarget(objectID: request.objectID, artifactID: request.artifactID, artifactKind: request.kind),
            reason: "shadowGeneratedArtifactRequest"
        )
        return recordResult(
            request: CanonicalProductionApplyExecutionRequest(action: action, rollbackCheckpointID: nil),
            status: .sent,
            sideEffectKind: .generatedArtifactApply,
            summary: "shadowGeneratedArtifactRequest"
        )
    }

    func applyObjectTombstone(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        tombstones.insert(request.action.target.objectID)
        return recordResult(request: request, status: .applied, sideEffectKind: .tombstoneMark, summary: "shadowObjectTombstone")
    }

    func applyLibraryTombstone(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        tombstones.insert(request.action.target.objectID)
        return recordResult(request: request, status: .applied, sideEffectKind: .tombstoneMark, summary: "shadowLibraryTombstone")
    }

    func recordConflict(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        conflicts.insert(request.action.conflictID ?? request.action.actionID)
        return recordResult(request: request, status: .conflictRecorded, sideEffectKind: .conflictRecord, summary: "shadowConflictRecord")
    }

    nonisolated func verifyPrecondition(_ precondition: CanonicalProductionApplyPrecondition) async throws -> CanonicalProductionApplyPrecondition {
        precondition
    }

    nonisolated func verifyPostcondition(_ postcondition: CanonicalProductionApplyPostcondition) async throws -> CanonicalProductionApplyPostcondition {
        postcondition
    }

    func rollbackApply(_ request: CanonicalRollbackAction) async throws -> CanonicalRollbackResult {
        if let checkpointID = request.checkpointID {
            results.removeValue(forKey: checkpointID)
        }
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
            reason: "shadowStoreOnly"
        )
    }

    private func recordResult(
        request: CanonicalProductionApplyExecutionRequest,
        status: CanonicalApplyExecutionStatus,
        sideEffectKind: CanonicalProductionSideEffectKind,
        summary: String
    ) -> CanonicalProductionApplyResult {
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
                kind: sideEffectKind,
                domain: .apply,
                objectID: request.action.target.objectID,
                artifactID: request.action.target.artifactID,
                summary: summary
            ),
            rollbackCheckpointID: request.rollbackCheckpointID
        )
        results[request.action.actionID] = result
        return result
    }
}

nonisolated enum CanonicalExecutionShadowEventKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalExecutionShadowStarted
    case canonicalExecutionShadowCompleted
    case canonicalExecutionShadowBlocked
    case canonicalExecutionShadowFileWriteSuppressed
    case canonicalExecutionShadowFileWriteToShadowRoot
    case canonicalExecutionShadowTransportProbeSuppressed
    case canonicalExecutionShadowTransportProbeCompleted
    case canonicalExecutionShadowUploadRehearsed
    case canonicalExecutionShadowApplyRehearsed
    case canonicalExecutionShadowRollbackRehearsed
    case canonicalExecutionShadowDivergenceDetected
    case canonicalExecutionShadowEquivalent
    case canonicalExecutionShadowProductionExecuteBlocked
    case canonicalRealDataShadowCopyStarted
    case canonicalRealDataShadowCopyCompleted
    case canonicalRealDataShadowCopyFailed
    case canonicalRealDataShadowCopyVerified
    case canonicalRealDataShadowCopyCleanupStarted
    case canonicalRealDataShadowCopyCleanupCompleted
    case canonicalRealDataShadowCopyCleanupFailed
    case canonicalRealDataShadowCopyRetainedForDiagnostics
    case canonicalRealDataShadowCopyUnavailable
    case canonicalReadOnlyTransportProbeStarted
    case canonicalReadOnlyTransportProbeCompleted
    case canonicalReadOnlyTransportProbeBlocked
    case canonicalReadOnlyTransportProbeSuppressed
    case canonicalReadOnlyTransportProbeRouteRejected
    case canonicalReadOnlyTransportProbeAuthBoundaryPreserved
}

nonisolated struct CanonicalExecutionShadowEvent: Codable, Equatable, Identifiable, Sendable {
    var id: String {
        [
            kind.rawValue,
            syncRunID ?? "",
            trigger.rawValue,
            nodeRole.rawValue,
            mode.rawValue,
            domain.rawValue,
            sideEffectClass ?? "",
            reason ?? ""
        ].joined(separator: "|")
    }

    var kind: CanonicalExecutionShadowEventKind
    var syncRunID: String?
    var trigger: CanonicalShadowMigrationTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var mode: CanonicalShadowMigrationMode
    var domain: CanonicalProductionDomain
    var shadowRootKind: CanonicalShadowRootKind?
    var sideEffectClass: String?
    var suppressionStatus: String?
    var reason: String?
    var plannedFileWriteCount: Int
    var plannedUploadCount: Int
    var plannedApplyCount: Int
    var divergenceCount: Int
    var generatedAt: CanonicalTimestamp

    nonisolated init(
        kind: CanonicalExecutionShadowEventKind,
        syncRunID: String?,
        trigger: CanonicalShadowMigrationTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        mode: CanonicalShadowMigrationMode,
        domain: CanonicalProductionDomain,
        shadowRootKind: CanonicalShadowRootKind? = nil,
        sideEffectClass: String? = nil,
        suppressionStatus: String? = nil,
        reason: String? = nil,
        plannedFileWriteCount: Int = 0,
        plannedUploadCount: Int = 0,
        plannedApplyCount: Int = 0,
        divergenceCount: Int = 0,
        generatedAt: Date = Date()
    ) {
        self.kind = kind
        self.syncRunID = CanonicalShadowMigrationRedaction.safeIdentifier(syncRunID)
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.mode = mode
        self.domain = domain
        self.shadowRootKind = shadowRootKind
        self.sideEffectClass = CanonicalShadowMigrationRedaction.safeText(sideEffectClass)
        self.suppressionStatus = CanonicalShadowMigrationRedaction.safeText(suppressionStatus)
        self.reason = CanonicalShadowMigrationRedaction.safeText(reason)
        self.plannedFileWriteCount = max(0, plannedFileWriteCount)
        self.plannedUploadCount = max(0, plannedUploadCount)
        self.plannedApplyCount = max(0, plannedApplyCount)
        self.divergenceCount = max(0, divergenceCount)
        self.generatedAt = CanonicalTimestamp(generatedAt)
    }

    nonisolated var diagnosticsSummary: String {
        [
            "trigger=\(trigger.rawValue)",
            "nodeRole=\(nodeRole.rawValue)",
            "mode=\(mode.rawValue)",
            "domain=\(domain.rawValue)",
            "shadowRootKind=\(shadowRootKind?.rawValue ?? "none")",
            "sideEffect=\(sideEffectClass ?? "none")",
            "suppression=\(suppressionStatus ?? "none")",
            "fileWrites=\(plannedFileWriteCount)",
            "uploads=\(plannedUploadCount)",
            "applies=\(plannedApplyCount)",
            "divergences=\(divergenceCount)",
            "reason=\(reason ?? "none")"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalExecutionShadowReport: Codable, Equatable, Identifiable, Sendable {
    var id: String { runID }

    var runID: String
    var syncRunID: String?
    var trigger: CanonicalShadowMigrationTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var mode: CanonicalShadowMigrationMode
    var generatedAt: CanonicalTimestamp
    var dryRunEquivalent: Bool
    var blocked: Bool
    var shadowRootKind: CanonicalShadowRootKind?
    var fileReport: CanonicalShadowFileExecutionReport?
    var uploadResult: CanonicalShadowUploadResult?
    var applyResult: CanonicalShadowApplyResult?
    var transportProbeResult: CanonicalShadowTransportProbeResult?
    var realDataShadowCopyResult: CanonicalRealDataShadowCopyResult?
    var shadowRootCleanupResult: CanonicalShadowRootCleanupResult?
    var readOnlyTransportProbeResult: CanonicalReadOnlyTransportProbeResult?
    var productionAudit: CanonicalProductionExecutionAudit?
    var events: [CanonicalExecutionShadowEvent]
    var failure: CanonicalShadowMigrationFailure?
    var failureReason: String?

    nonisolated init(
        runID: String,
        syncRunID: String?,
        trigger: CanonicalShadowMigrationTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        mode: CanonicalShadowMigrationMode,
        dryRunEquivalent: Bool,
        blocked: Bool,
        shadowRootKind: CanonicalShadowRootKind? = nil,
        fileReport: CanonicalShadowFileExecutionReport? = nil,
        uploadResult: CanonicalShadowUploadResult? = nil,
        applyResult: CanonicalShadowApplyResult? = nil,
        transportProbeResult: CanonicalShadowTransportProbeResult? = nil,
        realDataShadowCopyResult: CanonicalRealDataShadowCopyResult? = nil,
        shadowRootCleanupResult: CanonicalShadowRootCleanupResult? = nil,
        readOnlyTransportProbeResult: CanonicalReadOnlyTransportProbeResult? = nil,
        productionAudit: CanonicalProductionExecutionAudit? = nil,
        events: [CanonicalExecutionShadowEvent],
        failure: CanonicalShadowMigrationFailure? = nil,
        failureReason: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.runID = CanonicalShadowMigrationRedaction.safeIdentifier(runID) ?? "execution-shadow-run"
        self.syncRunID = CanonicalShadowMigrationRedaction.safeIdentifier(syncRunID)
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.mode = mode
        self.generatedAt = CanonicalTimestamp(generatedAt)
        self.dryRunEquivalent = dryRunEquivalent
        self.blocked = blocked
        self.shadowRootKind = shadowRootKind
        self.fileReport = fileReport
        self.uploadResult = uploadResult
        self.applyResult = applyResult
        self.transportProbeResult = transportProbeResult
        self.realDataShadowCopyResult = realDataShadowCopyResult
        self.shadowRootCleanupResult = shadowRootCleanupResult
        self.readOnlyTransportProbeResult = readOnlyTransportProbeResult
        self.productionAudit = productionAudit
        self.events = events
        self.failure = failure
        self.failureReason = CanonicalShadowMigrationRedaction.safeText(failureReason)
    }
}

nonisolated struct CanonicalExecutionShadowResult: Sendable {
    var configuration: CanonicalShadowMigrationConfiguration
    var gate: CanonicalShadowMigrationGate
    var dryRunPlan: CanonicalDryRunMigrationPlan?
    var report: CanonicalExecutionShadowReport
    var failure: CanonicalShadowMigrationFailure?
    var isFatal: Bool

    nonisolated var succeeded: Bool {
        failure == nil
    }
}

nonisolated struct CanonicalExecutionShadowPreparationRunner {
    nonisolated init() {}

    nonisolated func run(
        configuration: CanonicalShadowMigrationConfiguration,
        trigger: CanonicalShadowMigrationTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        domain: CanonicalProductionDomain,
        localSnapshot: CanonicalProductionSnapshot?,
        peerSnapshot: CanonicalProductionSnapshot?,
        ports: CanonicalProductionPortSet,
        currentRuntimeReadiness: CanonicalRuntimeReadinessReport = CanonicalShadowMigrationRunner.defaultRuntimeReadiness(),
        context: CanonicalDryRunMigrationContext = CanonicalDryRunMigrationContext(),
        syncRunID: String? = nil,
        shadowRootKind: CanonicalShadowRootKind? = nil,
        shadowFileReport: CanonicalShadowFileExecutionReport? = nil,
        realDataShadowCopyResult: CanonicalRealDataShadowCopyResult? = nil,
        shadowRootCleanupResult: CanonicalShadowRootCleanupResult? = nil,
        readOnlyTransportProbeResult: CanonicalReadOnlyTransportProbeResult? = nil,
        generatedAt: Date = Date()
    ) -> CanonicalExecutionShadowResult {
        let gate = CanonicalShadowMigrationGate.evaluate(
            configuration: configuration,
            trigger: trigger,
            nodeRole: nodeRole
        )
        var events: [CanonicalExecutionShadowEvent] = [
            event(
                .canonicalExecutionShadowStarted,
                gate: gate,
                configuration: configuration,
                domain: domain,
                syncRunID: syncRunID,
                shadowRootKind: shadowRootKind,
                sideEffectClass: "executionShadow",
                suppressionStatus: "started",
                reason: gate.reason,
                generatedAt: generatedAt
            )
        ]
        events.append(contentsOf: realDataCopyEvents(
            result: realDataShadowCopyResult,
            gate: gate,
            configuration: configuration,
            domain: domain,
            syncRunID: syncRunID,
            shadowRootKind: shadowRootKind,
            generatedAt: generatedAt
        ))
        events.append(contentsOf: readOnlyProbeEvents(
            result: readOnlyTransportProbeResult,
            gate: gate,
            configuration: configuration,
            domain: .transportRuntime,
            syncRunID: syncRunID,
            shadowRootKind: shadowRootKind,
            generatedAt: generatedAt
        ))

        guard gate.allowed, configuration.effectiveMode.runsExecutionShadowPreparation else {
            let kind: CanonicalExecutionShadowEventKind = gate.failure == .blockedProductionExecute
                ? .canonicalExecutionShadowProductionExecuteBlocked
                : .canonicalExecutionShadowBlocked
            events.append(
                event(
                    kind,
                    gate: gate,
                    configuration: configuration,
                    domain: domain,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "productionExecute",
                    suppressionStatus: "blocked",
                    reason: gate.reason,
                    generatedAt: generatedAt
                )
            )
            return makeResult(
                configuration: configuration,
                gate: gate,
                plan: nil,
                dryRunEquivalent: false,
                blocked: true,
                events: events,
                failure: gate.failure,
                failureReason: gate.reason,
                shadowRootKind: shadowRootKind,
                shadowFileReport: shadowFileReport,
                realDataShadowCopyResult: realDataShadowCopyResult,
                shadowRootCleanupResult: shadowRootCleanupResult,
                readOnlyTransportProbeResult: readOnlyTransportProbeResult,
                productionAudit: nil,
                generatedAt: generatedAt
            )
        }

        guard let localSnapshot else {
            events.append(blockedEvent(gate: gate, configuration: configuration, domain: domain, syncRunID: syncRunID, shadowRootKind: shadowRootKind, reason: "insufficientLocalSnapshot", generatedAt: generatedAt))
            events.append(contentsOf: cleanupEvents(result: shadowRootCleanupResult, gate: gate, configuration: configuration, domain: domain, syncRunID: syncRunID, shadowRootKind: shadowRootKind, generatedAt: generatedAt))
            return makeResult(configuration: configuration, gate: gate, plan: nil, dryRunEquivalent: false, blocked: true, events: events, failure: .insufficientLocalSnapshot, failureReason: "insufficientLocalSnapshot", shadowRootKind: shadowRootKind, shadowFileReport: shadowFileReport, realDataShadowCopyResult: realDataShadowCopyResult, shadowRootCleanupResult: shadowRootCleanupResult, readOnlyTransportProbeResult: readOnlyTransportProbeResult, productionAudit: nil, generatedAt: generatedAt)
        }
        guard let peerSnapshot else {
            events.append(blockedEvent(gate: gate, configuration: configuration, domain: domain, syncRunID: syncRunID, shadowRootKind: shadowRootKind, reason: "insufficientPeerSnapshot", generatedAt: generatedAt))
            events.append(contentsOf: cleanupEvents(result: shadowRootCleanupResult, gate: gate, configuration: configuration, domain: domain, syncRunID: syncRunID, shadowRootKind: shadowRootKind, generatedAt: generatedAt))
            return makeResult(configuration: configuration, gate: gate, plan: nil, dryRunEquivalent: false, blocked: true, events: events, failure: .insufficientPeerSnapshot, failureReason: "insufficientPeerSnapshot", shadowRootKind: shadowRootKind, shadowFileReport: shadowFileReport, realDataShadowCopyResult: realDataShadowCopyResult, shadowRootCleanupResult: shadowRootCleanupResult, readOnlyTransportProbeResult: readOnlyTransportProbeResult, productionAudit: nil, generatedAt: generatedAt)
        }

        do {
            let plan = try CanonicalDryRunMigrationPlanner().plan(
                local: localSnapshot,
                peer: peerSnapshot,
                ports: ports,
                currentRuntimeReadiness: currentRuntimeReadiness,
                trigger: .periodic,
                context: context,
                generatedAt: generatedAt
            )
            let dryRunEquivalent = plan.equivalenceReport.legacyEquivalence.hasBlockingDivergence == false
            let counts = plannedCounts(plan)
            events.append(fileEvent(for: configuration.effectiveMode, gate: gate, domain: domain, syncRunID: syncRunID, shadowRootKind: shadowRootKind, shadowFileReport: shadowFileReport, plannedCount: counts.fileWrites, generatedAt: generatedAt))
            events.append(transportEvent(for: configuration, gate: gate, domain: domain, syncRunID: syncRunID, shadowRootKind: shadowRootKind, generatedAt: generatedAt))
            events.append(
                event(
                    .canonicalExecutionShadowUploadRehearsed,
                    gate: gate,
                    configuration: configuration,
                    domain: .uploadRuntime,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "upload",
                    suppressionStatus: "shadowReceiverOnly",
                    reason: "productionUploadSuppressed",
                    plannedUploadCount: counts.uploads,
                    generatedAt: generatedAt
                )
            )
            events.append(
                event(
                    .canonicalExecutionShadowApplyRehearsed,
                    gate: gate,
                    configuration: configuration,
                    domain: .apply,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "apply",
                    suppressionStatus: "shadowStoreOnly",
                    reason: "applySyncManifestSuppressed",
                    plannedApplyCount: counts.applies,
                    generatedAt: generatedAt
                )
            )
            events.append(
                event(
                    .canonicalExecutionShadowRollbackRehearsed,
                    gate: gate,
                    configuration: configuration,
                    domain: .fileRuntime,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "rollback",
                    suppressionStatus: "shadowOnly",
                    reason: "rollbackAvailable",
                    plannedFileWriteCount: counts.fileWrites,
                    generatedAt: generatedAt
                )
            )
            events.append(
                event(
                    dryRunEquivalent ? .canonicalExecutionShadowEquivalent : .canonicalExecutionShadowDivergenceDetected,
                    gate: gate,
                    configuration: configuration,
                    domain: domain,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "dryRunEquivalence",
                    suppressionStatus: dryRunEquivalent ? "equivalent" : "divergent",
                    reason: dryRunEquivalent ? "equivalent" : "blockingDivergence",
                    divergenceCount: plan.equivalenceReport.legacyEquivalence.divergences.count,
                    generatedAt: generatedAt
                )
            )
            events.append(
                event(
                    .canonicalExecutionShadowCompleted,
                    gate: gate,
                    configuration: configuration,
                    domain: domain,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "executionShadow",
                    suppressionStatus: "completed",
                    reason: configuration.effectiveMode.noSideEffectReason,
                    plannedFileWriteCount: counts.fileWrites,
                    plannedUploadCount: counts.uploads,
                    plannedApplyCount: counts.applies,
                    divergenceCount: plan.equivalenceReport.legacyEquivalence.divergences.count,
                    generatedAt: generatedAt
                )
            )
            events.append(contentsOf: cleanupEvents(result: shadowRootCleanupResult, gate: gate, configuration: configuration, domain: domain, syncRunID: syncRunID, shadowRootKind: shadowRootKind, generatedAt: generatedAt))
            let audit = CanonicalProductionExecutionGuard.evaluateShadow(
                mode: configuration.effectiveMode.kernelShadowMode,
                token: CanonicalProductionExecutionToken(
                    mode: configuration.effectiveMode.kernelShadowMode,
                    domainAllowlist: CanonicalProductionDomain.allCases,
                    nodeRole: nodeRole,
                    syncRunID: syncRunID ?? context.dryRunID
                ),
                domains: [.fileRuntime, .transportRuntime, .uploadRuntime, .apply],
                rollbackPlan: CanonicalRollbackPlan(planID: "execution-shadow-rollback", checkpoints: [], actions: []),
                dryRunEquivalence: plan.equivalenceReport,
                unresolvedConflictCount: plan.blockers.filter { $0.kind == .unresolvedConflict }.count,
                generatedAt: generatedAt
            )
            return makeResult(
                configuration: configuration,
                gate: gate,
                plan: plan,
                dryRunEquivalent: dryRunEquivalent,
                blocked: false,
                events: events,
                failure: nil,
                failureReason: nil,
                shadowRootKind: shadowRootKind,
                shadowFileReport: shadowFileReport,
                realDataShadowCopyResult: realDataShadowCopyResult,
                shadowRootCleanupResult: shadowRootCleanupResult,
                readOnlyTransportProbeResult: readOnlyTransportProbeResult,
                productionAudit: audit,
                generatedAt: generatedAt
            )
        } catch {
            events.append(blockedEvent(gate: gate, configuration: configuration, domain: domain, syncRunID: syncRunID, shadowRootKind: shadowRootKind, reason: "dryRunFailed", generatedAt: generatedAt))
            events.append(contentsOf: cleanupEvents(result: shadowRootCleanupResult, gate: gate, configuration: configuration, domain: domain, syncRunID: syncRunID, shadowRootKind: shadowRootKind, generatedAt: generatedAt))
            return makeResult(configuration: configuration, gate: gate, plan: nil, dryRunEquivalent: false, blocked: true, events: events, failure: .dryRunFailed, failureReason: String(describing: error), shadowRootKind: shadowRootKind, shadowFileReport: shadowFileReport, realDataShadowCopyResult: realDataShadowCopyResult, shadowRootCleanupResult: shadowRootCleanupResult, readOnlyTransportProbeResult: readOnlyTransportProbeResult, productionAudit: nil, generatedAt: generatedAt)
        }
    }

    private nonisolated func makeResult(
        configuration: CanonicalShadowMigrationConfiguration,
        gate: CanonicalShadowMigrationGate,
        plan: CanonicalDryRunMigrationPlan?,
        dryRunEquivalent: Bool,
        blocked: Bool,
        events: [CanonicalExecutionShadowEvent],
        failure: CanonicalShadowMigrationFailure?,
        failureReason: String?,
        shadowRootKind: CanonicalShadowRootKind?,
        shadowFileReport: CanonicalShadowFileExecutionReport?,
        realDataShadowCopyResult: CanonicalRealDataShadowCopyResult?,
        shadowRootCleanupResult: CanonicalShadowRootCleanupResult?,
        readOnlyTransportProbeResult: CanonicalReadOnlyTransportProbeResult?,
        productionAudit: CanonicalProductionExecutionAudit?,
        generatedAt: Date
    ) -> CanonicalExecutionShadowResult {
        let boundedEvents = Array(events.prefix(configuration.policy.maxDiagnosticsEvents))
        let report = CanonicalExecutionShadowReport(
            runID: plan?.dryRunID ?? gate.reason,
            syncRunID: boundedEvents.first?.syncRunID,
            trigger: gate.trigger,
            nodeRole: gate.nodeRole,
            mode: gate.mode,
            dryRunEquivalent: dryRunEquivalent,
            blocked: blocked,
            shadowRootKind: shadowRootKind,
            fileReport: shadowFileReport,
            realDataShadowCopyResult: realDataShadowCopyResult,
            shadowRootCleanupResult: shadowRootCleanupResult,
            readOnlyTransportProbeResult: readOnlyTransportProbeResult,
            productionAudit: productionAudit,
            events: boundedEvents,
            failure: failure,
            failureReason: failureReason,
            generatedAt: generatedAt
        )
        return CanonicalExecutionShadowResult(
            configuration: configuration,
            gate: gate,
            dryRunPlan: plan,
            report: report,
            failure: failure,
            isFatal: failure != nil && configuration.policy.failureIsFatal
        )
    }

    private nonisolated func plannedCounts(_ plan: CanonicalDryRunMigrationPlan) -> (fileWrites: Int, uploads: Int, applies: Int) {
        let uploads = plan.syncPlan.uploadAudioArtifact.count
        let applies = plan.applyPlan.actions.count + plan.libraryPlan.applyActions.count
        let fileWrites = plan.applyPlan.actions.filter {
            switch $0.kind {
            case .recordingMetadataApply, .folderMetadataApply, .studyItemMetadataApply, .generatedArtifactDownloadApply,
                 .objectTombstoneApply, .libraryTombstoneApply, .artifactTombstoneApply:
                return true
            case .recordingMetadataSend, .folderMetadataSend, .studyItemMetadataSend, .libraryTombstoneSend,
                 .objectTombstoneSend, .generatedArtifactNoOp, .conflictRecord, .deferredUnsupported:
                return false
            }
        }.count + plan.libraryPlan.applyActions.count
        return (fileWrites, uploads, applies)
    }

    private nonisolated func fileEvent(
        for mode: CanonicalShadowMigrationMode,
        gate: CanonicalShadowMigrationGate,
        domain: CanonicalProductionDomain,
        syncRunID: String?,
        shadowRootKind: CanonicalShadowRootKind?,
        shadowFileReport: CanonicalShadowFileExecutionReport?,
        plannedCount: Int,
        generatedAt: Date
    ) -> CanonicalExecutionShadowEvent {
        if mode == .executionShadowWithShadowFileStore, shadowFileReport?.wroteToShadowRoot == true {
            return event(
                .canonicalExecutionShadowFileWriteToShadowRoot,
                gate: gate,
                configuration: .enabled(mode: mode),
                domain: .fileRuntime,
                syncRunID: syncRunID,
                shadowRootKind: shadowRootKind,
                sideEffectClass: "fileWrite",
                suppressionStatus: "shadowRootOnly",
                reason: "wroteToShadowRoot",
                plannedFileWriteCount: plannedCount,
                generatedAt: generatedAt
            )
        }
        return event(
            .canonicalExecutionShadowFileWriteSuppressed,
            gate: gate,
            configuration: .enabled(mode: mode),
            domain: domain,
            syncRunID: syncRunID,
            shadowRootKind: shadowRootKind,
            sideEffectClass: "fileWrite",
            suppressionStatus: "suppressed",
            reason: mode == .executionShadowWithShadowFileStore ? "missingShadowSourceBytes" : "fileWriteSuppressed",
            plannedFileWriteCount: plannedCount,
            generatedAt: generatedAt
        )
    }

    private nonisolated func transportEvent(
        for configuration: CanonicalShadowMigrationConfiguration,
        gate: CanonicalShadowMigrationGate,
        domain: CanonicalProductionDomain,
        syncRunID: String?,
        shadowRootKind: CanonicalShadowRootKind?,
        generatedAt: Date
    ) -> CanonicalExecutionShadowEvent {
        guard configuration.effectiveMode == .executionShadowWithReadOnlyTransportProbe else {
            return event(
                .canonicalExecutionShadowTransportProbeSuppressed,
                gate: gate,
                configuration: configuration,
                domain: .transportRuntime,
                syncRunID: syncRunID,
                shadowRootKind: shadowRootKind,
                sideEffectClass: "transport",
                suppressionStatus: "suppressed",
                reason: "transportProbeNotRequested",
                generatedAt: generatedAt
            )
        }
        let decision = configuration.policy.networkProbePolicy.decision(
            for: CanonicalShadowNetworkProbeRequest(kind: .syncInventoryReadOnly, routePath: "/sync/inventory")
        )
        return event(
            decision.accepted ? .canonicalExecutionShadowTransportProbeCompleted : .canonicalExecutionShadowTransportProbeSuppressed,
            gate: gate,
            configuration: configuration,
            domain: .transportRuntime,
            syncRunID: syncRunID,
            shadowRootKind: shadowRootKind,
            sideEffectClass: "transport",
            suppressionStatus: decision.accepted ? "readOnlyProbeAccepted" : "suppressed",
            reason: decision.accepted ? "readOnlyEnvelopeOnly" : decision.reason,
            generatedAt: generatedAt
        )
    }

    private nonisolated func realDataCopyEvents(
        result: CanonicalRealDataShadowCopyResult?,
        gate: CanonicalShadowMigrationGate,
        configuration: CanonicalShadowMigrationConfiguration,
        domain: CanonicalProductionDomain,
        syncRunID: String?,
        shadowRootKind: CanonicalShadowRootKind?,
        generatedAt: Date
    ) -> [CanonicalExecutionShadowEvent] {
        guard let result else {
            guard configuration.policy.realDataShadowCopyPolicy.isEnabled,
                  configuration.effectiveMode == .executionShadowWithShadowFileStore else {
                return []
            }
            return [
                event(
                    .canonicalRealDataShadowCopyUnavailable,
                    gate: gate,
                    configuration: configuration,
                    domain: .fileRuntime,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "realDataShadowCopy",
                    suppressionStatus: "unavailable",
                    reason: "realDataShadowCopyUnavailable",
                    generatedAt: generatedAt
                )
            ]
        }
        var events: [CanonicalExecutionShadowEvent] = [
            event(
                .canonicalRealDataShadowCopyStarted,
                gate: gate,
                configuration: configuration,
                domain: .fileRuntime,
                syncRunID: syncRunID,
                shadowRootKind: shadowRootKind,
                sideEffectClass: "realDataShadowCopy",
                suppressionStatus: "started",
                reason: result.diagnosticsSummary,
                plannedFileWriteCount: result.copiedEntryCount,
                generatedAt: generatedAt
            )
        ]
        if result.completed {
            events.append(
                event(
                    .canonicalRealDataShadowCopyCompleted,
                    gate: gate,
                    configuration: configuration,
                    domain: .fileRuntime,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "realDataShadowCopy",
                    suppressionStatus: "shadowRootOnly",
                    reason: result.diagnosticsSummary,
                    plannedFileWriteCount: result.copiedEntryCount,
                    generatedAt: generatedAt
                )
            )
            events.append(
                event(
                    .canonicalRealDataShadowCopyVerified,
                    gate: gate,
                    configuration: configuration,
                    domain: .fileRuntime,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "copyVerification",
                    suppressionStatus: result.verificationStatus,
                    reason: result.diagnosticsSummary,
                    plannedFileWriteCount: result.copiedEntryCount,
                    generatedAt: generatedAt
                )
            )
        } else if result.unavailable {
            events.append(
                event(
                    .canonicalRealDataShadowCopyUnavailable,
                    gate: gate,
                    configuration: configuration,
                    domain: .fileRuntime,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "realDataShadowCopy",
                    suppressionStatus: "unavailable",
                    reason: result.failureReason ?? result.failure?.rawValue,
                    generatedAt: generatedAt
                )
            )
        } else {
            events.append(
                event(
                    .canonicalRealDataShadowCopyFailed,
                    gate: gate,
                    configuration: configuration,
                    domain: .fileRuntime,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "realDataShadowCopy",
                    suppressionStatus: "failed",
                    reason: result.failureReason ?? result.failure?.rawValue,
                    plannedFileWriteCount: result.copiedEntryCount,
                    generatedAt: generatedAt
                )
            )
        }
        return events
    }

    private nonisolated func cleanupEvents(
        result: CanonicalShadowRootCleanupResult?,
        gate: CanonicalShadowMigrationGate,
        configuration: CanonicalShadowMigrationConfiguration,
        domain: CanonicalProductionDomain,
        syncRunID: String?,
        shadowRootKind: CanonicalShadowRootKind?,
        generatedAt: Date
    ) -> [CanonicalExecutionShadowEvent] {
        guard let result else {
            return []
        }
        let completedKind: CanonicalExecutionShadowEventKind
        switch result.status {
        case .removed:
            completedKind = .canonicalRealDataShadowCopyCleanupCompleted
        case .retainedForDiagnostics, .retainedForNextLaunch:
            completedKind = .canonicalRealDataShadowCopyRetainedForDiagnostics
        case .refusedProductionRoot, .failed:
            completedKind = .canonicalRealDataShadowCopyCleanupFailed
        }
        return [
            event(
                .canonicalRealDataShadowCopyCleanupStarted,
                gate: gate,
                configuration: configuration,
                domain: .fileRuntime,
                syncRunID: syncRunID,
                shadowRootKind: shadowRootKind,
                sideEffectClass: "shadowRootCleanup",
                suppressionStatus: "started",
                reason: result.rootID,
                generatedAt: generatedAt
            ),
            event(
                completedKind,
                gate: gate,
                configuration: configuration,
                domain: .fileRuntime,
                syncRunID: syncRunID,
                shadowRootKind: shadowRootKind,
                sideEffectClass: "shadowRootCleanup",
                suppressionStatus: result.status.rawValue,
                reason: result.diagnosticsSummary,
                generatedAt: generatedAt
            )
        ]
    }

    private nonisolated func readOnlyProbeEvents(
        result: CanonicalReadOnlyTransportProbeResult?,
        gate: CanonicalShadowMigrationGate,
        configuration: CanonicalShadowMigrationConfiguration,
        domain: CanonicalProductionDomain,
        syncRunID: String?,
        shadowRootKind: CanonicalShadowRootKind?,
        generatedAt: Date
    ) -> [CanonicalExecutionShadowEvent] {
        guard let result else {
            guard configuration.policy.readOnlyTransportProbePolicy.isEnabled,
                  configuration.effectiveMode == .executionShadowWithReadOnlyTransportProbe else {
                return []
            }
            return [
                event(
                    .canonicalReadOnlyTransportProbeSuppressed,
                    gate: gate,
                    configuration: configuration,
                    domain: domain,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "readOnlyTransportProbe",
                    suppressionStatus: "suppressed",
                    reason: "readOnlyProbeUnavailable",
                    generatedAt: generatedAt
                )
            ]
        }
        var events: [CanonicalExecutionShadowEvent] = [
            event(
                .canonicalReadOnlyTransportProbeStarted,
                gate: gate,
                configuration: configuration,
                domain: domain,
                syncRunID: syncRunID,
                shadowRootKind: shadowRootKind,
                sideEffectClass: "readOnlyTransportProbe",
                suppressionStatus: "started",
                reason: result.diagnosticsSummary,
                generatedAt: generatedAt
            )
        ]
        let mainKind: CanonicalExecutionShadowEventKind
        if result.blocked {
            mainKind = result.routeStatus == .rejectedMutating || result.routeStatus == .rejectedUnknown
                ? .canonicalReadOnlyTransportProbeRouteRejected
                : .canonicalReadOnlyTransportProbeBlocked
        } else if result.suppressed {
            mainKind = .canonicalReadOnlyTransportProbeSuppressed
        } else {
            mainKind = .canonicalReadOnlyTransportProbeCompleted
        }
        events.append(
            event(
                mainKind,
                gate: gate,
                configuration: configuration,
                domain: domain,
                syncRunID: syncRunID,
                shadowRootKind: shadowRootKind,
                sideEffectClass: "readOnlyTransportProbe",
                suppressionStatus: result.routeStatus.rawValue,
                reason: result.diagnosticsSummary,
                generatedAt: generatedAt
            )
        )
        if result.authBoundaryPreserved {
            events.append(
                event(
                    .canonicalReadOnlyTransportProbeAuthBoundaryPreserved,
                    gate: gate,
                    configuration: configuration,
                    domain: domain,
                    syncRunID: syncRunID,
                    shadowRootKind: shadowRootKind,
                    sideEffectClass: "transportAuth",
                    suppressionStatus: "preserved",
                    reason: "tlsHmacNonceTimestampBodyHashPreserved",
                    generatedAt: generatedAt
                )
            )
        }
        return events
    }

    private nonisolated func blockedEvent(
        gate: CanonicalShadowMigrationGate,
        configuration: CanonicalShadowMigrationConfiguration,
        domain: CanonicalProductionDomain,
        syncRunID: String?,
        shadowRootKind: CanonicalShadowRootKind?,
        reason: String,
        generatedAt: Date
    ) -> CanonicalExecutionShadowEvent {
        event(
            .canonicalExecutionShadowBlocked,
            gate: gate,
            configuration: configuration,
            domain: domain,
            syncRunID: syncRunID,
            shadowRootKind: shadowRootKind,
            sideEffectClass: "executionShadow",
            suppressionStatus: "blocked",
            reason: reason,
            generatedAt: generatedAt
        )
    }

    private nonisolated func event(
        _ kind: CanonicalExecutionShadowEventKind,
        gate: CanonicalShadowMigrationGate,
        configuration: CanonicalShadowMigrationConfiguration,
        domain: CanonicalProductionDomain,
        syncRunID: String?,
        shadowRootKind: CanonicalShadowRootKind?,
        sideEffectClass: String?,
        suppressionStatus: String?,
        reason: String?,
        plannedFileWriteCount: Int = 0,
        plannedUploadCount: Int = 0,
        plannedApplyCount: Int = 0,
        divergenceCount: Int = 0,
        generatedAt: Date
    ) -> CanonicalExecutionShadowEvent {
        CanonicalExecutionShadowEvent(
            kind: kind,
            syncRunID: syncRunID,
            trigger: gate.trigger,
            nodeRole: gate.nodeRole,
            mode: configuration.effectiveMode,
            domain: domain,
            shadowRootKind: shadowRootKind,
            sideEffectClass: sideEffectClass,
            suppressionStatus: suppressionStatus,
            reason: reason,
            plannedFileWriteCount: plannedFileWriteCount,
            plannedUploadCount: plannedUploadCount,
            plannedApplyCount: plannedApplyCount,
            divergenceCount: divergenceCount,
            generatedAt: generatedAt
        )
    }
}

extension CanonicalShadowMigrationMode {
    nonisolated var kernelShadowMode: CanonicalKernelExecutionMode {
        switch self {
        case .executionShadowDryRun:
            return .executionShadowDryRun
        case .executionShadowWithShadowFileStore:
            return .executionShadowWithShadowFileStore
        case .executionShadowWithReadOnlyTransportProbe:
            return .executionShadowWithReadOnlyTransportProbe
        case .shadowReadOnly, .shadowReadOnlyWithNetworkProbe:
            return .productionShadow
        case .disabled, .diagnosticsOnly, .dryRunCompare, .blockedProductionExecute,
             .blockedExecutionShadowWrite, .blockedExecutionShadowUpload, .blockedExecutionShadowApply:
            return .dryRun
        }
    }
}
