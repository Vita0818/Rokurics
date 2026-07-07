//
//  CanonicalProductionPorts.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalProductionDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingMetadata
    case recordingAudio
    case generatedArtifacts
    case folders
    case studyItems
    case standaloneNotes
    case tombstones
    case conflicts
    case apply
    case fileRuntime
    case transportRuntime
    case uploadRuntime
    case objectProjection
    case inventory
    case uiIntegration
}

nonisolated enum CanonicalProductionPortKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case file
    case transport
    case upload
    case apply
    case syncClock
    case diagnostics
    case capability
}

nonisolated enum CanonicalProductionOperation: String, Codable, Equatable, Hashable, Sendable {
    case metadataSnapshotRead
    case metadataRead
    case metadataWrite
    case artifactDescriptorRead
    case artifactRead
    case artifactWriteAtomic
    case artifactVerify
    case artifactBytesReadDryRun
    case logicalTokenResolve
    case containmentVerify
    case atomicWriteProject
    case atomicWriteExecute
    case artifactList
    case objectList
    case hashCompute
    case rollbackWrite
    case tombstoneApplyProject
    case tombstoneMark
    case physicalDeleteSuppressed
    case routeEnvelopeBuild
    case signedRequestBuild
    case requestSend
    case responseReceive
    case responseVerify
    case manifestExchange
    case artifactRequest
    case applyMetadataSend
    case uploadSessionStart
    case uploadSessionQuery
    case uploadChunkSend
    case uploadSessionFinalize
    case uploadSessionCancel
    case routeResponseDecode
    case uploadStartProject
    case resumableUploadStart
    case resumableUploadResume
    case uploadChunkProject
    case resumableUploadChunk
    case uploadFinalizeProject
    case resumableUploadFinalize
    case resumableUploadCancel
    case uploadLedgerRead
    case uploadLedgerWrite
    case retryProject
    case uploadStateRollback
    case applyMetadataProject
    case metadataApply
    case metadataSend
    case applyGeneratedArtifactProject
    case generatedArtifactApply
    case generatedArtifactRequest
    case objectTombstoneApply
    case libraryTombstoneApply
    case recordConflictProject
    case conflictRecord
    case preconditionVerify
    case postconditionVerify
    case applyRollback
    case diagnosticsRecord
}

nonisolated enum CanonicalProductionCapability: String, Codable, Equatable, Hashable, Sendable {
    case dryRunOnly
    case rootBoundFileAccess
    case rootBoundRead
    case rootBoundWrite
    case logicalTokenValidation
    case containmentVerification
    case atomicWriteProjection
    case atomicWriteExecution
    case hashSizeVerification
    case streamingHash
    case rollbackCheckpoint
    case noPhysicalDelete
    case routeSigning
    case routeVerification
    case externalSignerRequired
    case signedRequestExecution
    case responseVerification
    case resumableUploadProjection
    case resumableUploadExecution
    case chunkResumeProjection
    case confirmedBytesQuery
    case finalizationProjection
    case finalizationExecution
    case retryProjection
    case uploadLedgerMutation
    case metadataApplyProjection
    case metadataApplyExecution
    case generatedArtifactApplyProjection
    case generatedArtifactApplyExecution
    case tombstoneApplyProjection
    case tombstoneApplyExecution
    case conflictRecordProjection
    case conflictRecordExecution
    case preconditionVerification
    case postconditionVerification
    case inMemoryDiagnostics
    case productionDiagnostics
}

nonisolated enum CanonicalProductionPortError: Error, Equatable, Codable, Sendable {
    case missingPort(CanonicalProductionPortKind)
    case capabilityMissing(domain: CanonicalProductionDomain, capability: CanonicalProductionCapability)
    case unsafeLogicalToken(String)
    case productionMutationAttempted(String)
    case networkExecutionSuppressed(String)
    case unsupportedObject(String)
    case fullContentRejected(String)
    case routeBypassRisk(String)
    case pathEscapeRisk(String)
}

nonisolated enum CanonicalProductionFilePortRootMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case testRoot
    case productionRootExplicit
}

nonisolated enum CanonicalProductionFilePortGateBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case nonDebugBuild
    case releaseDefaultBuild
    case missingExplicitDebugInternalConfiguration
    case missingOwnerApproval
    case missingManualConfirmation
    case productionRootWritesDisabled
    case missingTestHarnessConfirmation
    case productionRootSafetyRejected
}

nonisolated struct CanonicalProductionFilePortGateResult: Codable, Equatable, Sendable {
    var rootMode: CanonicalProductionFilePortRootMode
    var allowed: Bool
    var dryRunOnly: Bool
    var rootSafety: CanonicalSwitchBackRootSafetyResult?
    var blockers: [CanonicalProductionFilePortGateBlocker]
    var diagnosticsSummary: String

    nonisolated init(
        rootMode: CanonicalProductionFilePortRootMode,
        allowed: Bool,
        rootSafety: CanonicalSwitchBackRootSafetyResult? = nil,
        blockers: [CanonicalProductionFilePortGateBlocker] = []
    ) {
        self.rootMode = rootMode
        self.allowed = allowed
        self.dryRunOnly = !allowed
        self.rootSafety = rootSafety
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.diagnosticsSummary = [
            "canonicalProductionFilePortGate=v8.61",
            "rootMode=\(rootMode.rawValue)",
            "allowed=\(allowed)",
            "dryRunOnly=\(!allowed)",
            rootSafety.map { "rootToken=\($0.redactedRootToken)" },
            rootSafety.map { "testClonedRoot=\($0.testClonedRoot)" },
            "blockers=\(self.blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].compactMap { $0 }.joined(separator: ",")
    }
}

nonisolated struct CanonicalProductionFilePortWritePolicy: Codable, Equatable, Sendable {
    var rootMode: CanonicalProductionFilePortRootMode
    var explicitDebugInternalConfiguration: Bool
    var ownerApproved: Bool
    var manualConfirmation: Bool
    var allowProductionRootWrites: Bool
    var releaseDefaultBuild: Bool
    var testHarnessConfirmed: Bool

    nonisolated init(
        rootMode: CanonicalProductionFilePortRootMode = .disabled,
        explicitDebugInternalConfiguration: Bool = false,
        ownerApproved: Bool = false,
        manualConfirmation: Bool = false,
        allowProductionRootWrites: Bool = false,
        releaseDefaultBuild: Bool = true,
        testHarnessConfirmed: Bool = false
    ) {
        self.rootMode = rootMode
        self.explicitDebugInternalConfiguration = explicitDebugInternalConfiguration
        self.ownerApproved = ownerApproved
        self.manualConfirmation = manualConfirmation
        self.allowProductionRootWrites = allowProductionRootWrites
        self.releaseDefaultBuild = releaseDefaultBuild
        self.testHarnessConfirmed = testHarnessConfirmed
    }

    nonisolated static let disabled = CanonicalProductionFilePortWritePolicy()

    nonisolated static func explicitTestRoot() -> CanonicalProductionFilePortWritePolicy {
        CanonicalProductionFilePortWritePolicy(
            rootMode: .testRoot,
            explicitDebugInternalConfiguration: true,
            ownerApproved: true,
            manualConfirmation: true,
            releaseDefaultBuild: false,
            testHarnessConfirmed: true
        )
    }

    nonisolated static func explicitProductionRoot(
        explicitDebugInternalConfiguration: Bool,
        ownerApproved: Bool,
        manualConfirmation: Bool,
        allowProductionRootWrites: Bool,
        releaseDefaultBuild: Bool = false,
        testHarnessConfirmed: Bool
    ) -> CanonicalProductionFilePortWritePolicy {
        CanonicalProductionFilePortWritePolicy(
            rootMode: .productionRootExplicit,
            explicitDebugInternalConfiguration: explicitDebugInternalConfiguration,
            ownerApproved: ownerApproved,
            manualConfirmation: manualConfirmation,
            allowProductionRootWrites: allowProductionRootWrites,
            releaseDefaultBuild: releaseDefaultBuild,
            testHarnessConfirmed: testHarnessConfirmed
        )
    }

    nonisolated func evaluate(rootURL: URL, fileManager: FileManager = .default) -> CanonicalProductionFilePortGateResult {
        guard rootMode != .disabled else {
            return CanonicalProductionFilePortGateResult(
                rootMode: rootMode,
                allowed: false,
                blockers: [.productionRootWritesDisabled]
            )
        }

        var blockers: [CanonicalProductionFilePortGateBlocker] = []
        #if !DEBUG
        blockers.append(.nonDebugBuild)
        #endif

        if rootMode == .productionRootExplicit {
            if releaseDefaultBuild {
                blockers.append(.releaseDefaultBuild)
            }
            if !explicitDebugInternalConfiguration {
                blockers.append(.missingExplicitDebugInternalConfiguration)
            }
            if !ownerApproved {
                blockers.append(.missingOwnerApproval)
            }
            if !manualConfirmation {
                blockers.append(.missingManualConfirmation)
            }
            if !allowProductionRootWrites {
                blockers.append(.productionRootWritesDisabled)
            }
            if !testHarnessConfirmed {
                blockers.append(.missingTestHarnessConfirmation)
            }
        }

        let rootSafety = CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: rootURL, fileManager: fileManager)
        if !rootSafety.accepted {
            blockers.append(.productionRootSafetyRejected)
        }

        return CanonicalProductionFilePortGateResult(
            rootMode: rootMode,
            allowed: blockers.isEmpty,
            rootSafety: rootSafety,
            blockers: blockers
        )
    }
}

nonisolated enum CanonicalProductionDiagnosticEventKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalProductionPortsDeclared
    case canonicalProductionSnapshotBuilt
    case canonicalDryRunStarted
    case canonicalDryRunCompleted
    case canonicalDryRunBlocked
    case canonicalDryRunDivergenceDetected
    case canonicalLegacyEquivalent
    case canonicalLegacyDivergent
    case canonicalProductionMigrationBlocked
    case canonicalEligibleForManualMigrationDesign
    case canonicalPortMissing
    case canonicalPortCapabilityMissing
    case canonicalDryRunWouldWriteButSuppressed
    case canonicalDryRunWouldUploadButSuppressed
    case canonicalDryRunWouldSendNetworkButSuppressed
}

nonisolated struct CanonicalProductionDiagnosticsEvent: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, domain?.rawValue ?? "", action ?? "", blocker ?? "", reason ?? ""].joined(separator: "|") }

    var kind: CanonicalProductionDiagnosticEventKind
    var domain: CanonicalProductionDomain?
    var action: String?
    var blocker: String?
    var reason: String?
    var hashPrefix: String?
    var dryRun: Bool
    var generatedAt: CanonicalTimestamp

    nonisolated init(
        kind: CanonicalProductionDiagnosticEventKind,
        domain: CanonicalProductionDomain? = nil,
        action: String? = nil,
        blocker: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil,
        hashPrefix: String? = nil,
        dryRun: Bool = true,
        generatedAt: Date = Date()
    ) {
        self.kind = kind
        self.domain = domain
        self.action = CanonicalProductionRedaction.safeDiagnosticText(action)
        self.blocker = CanonicalProductionRedaction.safeDiagnosticText(blocker)
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason)
        self.hashPrefix = hash.map { CanonicalProductionRedaction.hashPrefix($0.value) }
            ?? CanonicalProductionRedaction.hashPrefix(hashPrefix)
        self.dryRun = dryRun
        self.generatedAt = CanonicalTimestamp(generatedAt)
    }
}

nonisolated enum CanonicalProductionArtifactAvailability: String, Codable, Equatable, Sendable {
    case available
    case missing
    case unknown
    case unsupported
}

nonisolated struct CanonicalProductionArtifactDescriptor: Codable, Equatable, Identifiable, Sendable {
    var id: String { artifactID }

    var artifactID: String
    var objectID: String
    var kind: CanonicalArtifact.Kind
    var logicalPathToken: String?
    var logicalName: String?
    var contentHashPrefix: String?
    var byteSize: Int64?
    var availability: CanonicalProductionArtifactAvailability
    var unsupportedReason: String?

    nonisolated init(
        artifactID: String,
        objectID: String,
        kind: CanonicalArtifact.Kind,
        logicalPathToken: String? = nil,
        logicalName: String? = nil,
        contentHash: CanonicalHash? = nil,
        contentHashPrefix: String? = nil,
        byteSize: Int64? = nil,
        availability: CanonicalProductionArtifactAvailability,
        unsupportedReason: String? = nil
    ) {
        self.artifactID = CanonicalProductionRedaction.safeIdentifier(artifactID, fallback: "\(kind.rawValue):unknown")
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.kind = kind
        self.logicalPathToken = logicalPathToken.flatMap(CanonicalProjectionContract.safeLogicalPathToken)
        self.logicalName = CanonicalProductionRedaction.safeFileName(logicalName)
        self.contentHashPrefix = contentHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
            ?? CanonicalProductionRedaction.hashPrefix(contentHashPrefix)
        self.byteSize = byteSize
        self.availability = availability
        self.unsupportedReason = CanonicalProductionRedaction.safeDiagnosticText(unsupportedReason)
        if logicalPathToken != nil, self.logicalPathToken == nil, self.unsupportedReason == nil {
            self.unsupportedReason = "unsafeLogicalPathToken"
        }
    }

    nonisolated init(artifact: CanonicalArtifact) {
        let availability: CanonicalProductionArtifactAvailability
        switch artifact.availability {
        case .available:
            availability = .available
        case .availableWithoutHash:
            availability = .available
        case .missing:
            availability = .missing
        case .unknown:
            availability = .unknown
        }
        self.init(
            artifactID: artifact.artifactID,
            objectID: artifact.objectID,
            kind: artifact.kind,
            logicalPathToken: artifact.logicalPathToken,
            logicalName: artifact.logicalName,
            contentHash: artifact.contentHash,
            byteSize: artifact.byteSize,
            availability: availability,
            unsupportedReason: nil
        )
    }

    nonisolated var hasUnsafePathSignal: Bool {
        logicalPathToken == nil && unsupportedReason == "unsafeLogicalPathToken"
    }
}

nonisolated struct CanonicalProductionReadProjection: Codable, Equatable, Sendable {
    var reference: CanonicalFileReference
    var wouldReadBytes: Bool
    var byteSize: Int64?
    var contentHashPrefix: String?
    var dryRun: Bool

    nonisolated init(
        reference: CanonicalFileReference,
        wouldReadBytes: Bool,
        byteSize: Int64? = nil,
        contentHash: CanonicalHash? = nil,
        dryRun: Bool = true
    ) {
        self.reference = reference
        self.wouldReadBytes = wouldReadBytes
        self.byteSize = byteSize
        self.contentHashPrefix = contentHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.dryRun = dryRun
    }
}

nonisolated struct CanonicalProductionWriteIntentProjection: Codable, Equatable, Sendable {
    var reference: CanonicalFileReference
    var purpose: CanonicalFilePurpose
    var wouldWrite: Bool
    var suppressedBecauseDryRun: Bool
    var noPhysicalDelete: Bool
    var byteSize: Int64?
    var contentHashPrefix: String?
    var disposition: CanonicalFileWriteDisposition?
    var reason: String?

    nonisolated init(
        reference: CanonicalFileReference,
        purpose: CanonicalFilePurpose,
        wouldWrite: Bool,
        suppressedBecauseDryRun: Bool = true,
        noPhysicalDelete: Bool = true,
        byteSize: Int64? = nil,
        contentHash: CanonicalHash? = nil,
        disposition: CanonicalFileWriteDisposition? = nil,
        reason: String? = nil
    ) {
        self.reference = reference
        self.purpose = purpose
        self.wouldWrite = wouldWrite
        self.suppressedBecauseDryRun = suppressedBecauseDryRun
        self.noPhysicalDelete = noPhysicalDelete
        self.byteSize = byteSize
        self.contentHashPrefix = contentHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.disposition = disposition
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason)
    }
}

nonisolated struct CanonicalProductionTransportRouteCapability: Codable, Equatable, Sendable {
    var route: CanonicalTransportRoute
    var requiresSigning: Bool
    var requiresVerification: Bool
    var dryRunOnly: Bool

    nonisolated init(
        route: CanonicalTransportRoute,
        requiresSigning: Bool = true,
        requiresVerification: Bool = true,
        dryRunOnly: Bool = true
    ) {
        self.route = route
        self.requiresSigning = requiresSigning
        self.requiresVerification = requiresVerification
        self.dryRunOnly = dryRunOnly
    }
}

nonisolated struct CanonicalProductionTransportEnvelopeDryRun: Codable, Equatable, Sendable {
    var route: CanonicalTransportRoute
    var sourceNodeID: String
    var destinationNodeID: String
    var requiresSigning: Bool
    var requiresVerification: Bool
    var bodyHashPrefix: String?
    var wouldSendNetwork: Bool
    var suppressedBecauseDryRun: Bool
    var reason: String

    nonisolated init(
        route: CanonicalTransportRoute,
        sourceNodeID: String,
        destinationNodeID: String,
        bodyHash: CanonicalHash? = nil,
        requiresSigning: Bool = true,
        requiresVerification: Bool = true,
        reason: String = "networkSuppressedDryRun"
    ) {
        self.route = route
        self.sourceNodeID = CanonicalProductionRedaction.safeIdentifier(sourceNodeID, fallback: "source:unknown")
        self.destinationNodeID = CanonicalProductionRedaction.safeIdentifier(destinationNodeID, fallback: "destination:unknown")
        self.requiresSigning = requiresSigning
        self.requiresVerification = requiresVerification
        self.bodyHashPrefix = bodyHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.wouldSendNetwork = false
        self.suppressedBecauseDryRun = true
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? "networkSuppressedDryRun"
    }
}

nonisolated struct CanonicalProductionUploadTrace: Codable, Equatable, Sendable {
    var objectID: String
    var artifactID: String?
    var totalBytes: Int64?
    var totalHashPrefix: String?
    var chunkSize: Int?
    var resumable: Bool
    var wouldUpload: Bool
    var suppressedBecauseDryRun: Bool
    var mappedToLegacyUploadCapability: Bool
    var route: CanonicalTransportRoute?
    var reason: String

    nonisolated init(
        objectID: String,
        artifactID: String? = nil,
        totalBytes: Int64? = nil,
        totalHash: CanonicalHash? = nil,
        chunkSize: Int? = nil,
        resumable: Bool = true,
        route: CanonicalTransportRoute? = .uploadStart,
        reason: String = "uploadSuppressedDryRun"
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.totalBytes = totalBytes
        self.totalHashPrefix = totalHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.chunkSize = chunkSize
        self.resumable = resumable
        self.wouldUpload = false
        self.suppressedBecauseDryRun = true
        self.mappedToLegacyUploadCapability = true
        self.route = route
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? "uploadSuppressedDryRun"
    }
}

nonisolated struct CanonicalProductionApplyTrace: Codable, Equatable, Sendable {
    var actionID: String
    var kind: CanonicalApplyActionKind
    var target: CanonicalApplyTarget
    var bridgeHint: CanonicalApplyBridgeHint?
    var wouldWrite: Bool
    var wouldCallApplySyncManifest: Bool
    var suppressedBecauseDryRun: Bool
    var reason: String

    nonisolated init(action: CanonicalApplyAction, wouldCallApplySyncManifest: Bool = false, reason: String = "applySuppressedDryRun") {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(action.actionID, fallback: action.kind.rawValue)
        self.kind = action.kind
        self.target = action.target
        self.bridgeHint = action.bridgeHint
        self.wouldWrite = true
        self.wouldCallApplySyncManifest = wouldCallApplySyncManifest
        self.suppressedBecauseDryRun = true
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? "applySuppressedDryRun"
    }
}

nonisolated struct CanonicalProductionUnsupportedFact: Codable, Equatable, Identifiable, Sendable {
    var id: String { [domain.rawValue, objectID, reason].joined(separator: "|") }

    var objectID: String
    var domain: CanonicalProductionDomain
    var reason: String

    nonisolated init(objectID: String, domain: CanonicalProductionDomain, reason: String) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown")
        self.domain = domain
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? "unsupported"
    }
}

nonisolated struct CanonicalLegacyActionSnapshot: Codable, Equatable, Sendable {
    var actionIDsByDomain: [CanonicalProductionDomain: [String]]

    nonisolated init(actionIDsByDomain: [CanonicalProductionDomain: [String]] = [:]) {
        self.actionIDsByDomain = Dictionary(uniqueKeysWithValues: actionIDsByDomain.map { domain, ids in
            (domain, Self.normalized(ids))
        })
    }

    nonisolated static let empty = CanonicalLegacyActionSnapshot()

    nonisolated func actionIDs(for domain: CanonicalProductionDomain) -> [String] {
        actionIDsByDomain[domain] ?? []
    }

    nonisolated func actionIDSet(for domain: CanonicalProductionDomain) -> Set<String> {
        Set(actionIDs(for: domain))
    }

    nonisolated func adding(_ ids: [String], domain: CanonicalProductionDomain) -> CanonicalLegacyActionSnapshot {
        var next = actionIDsByDomain
        next[domain] = Self.normalized((next[domain] ?? []) + ids)
        return CanonicalLegacyActionSnapshot(actionIDsByDomain: next)
    }

    nonisolated private static func normalized(_ ids: [String]) -> [String] {
        Array(Set(ids.compactMap { CanonicalProductionRedaction.safeDiagnosticText($0) })).sorted()
    }
}

nonisolated struct CanonicalRuntimeNodeState: Codable, Equatable, Sendable {
    var node: CanonicalNode
    var manifest: CanonicalManifest
    var transferProjection: CanonicalTransferProjection
    var inventoryCoverage: CanonicalInventoryCoverageReport
    var retirementReadiness: CanonicalRetirementReadinessReport
    var objectProjection: CanonicalLibraryProjection
    var unsupportedFacts: [CanonicalProductionUnsupportedFact]
    var diagnostics: [CanonicalProductionDiagnosticsEvent]

    nonisolated init(
        node: CanonicalNode,
        manifest: CanonicalManifest,
        transferProjection: CanonicalTransferProjection = CanonicalTransferProjection(),
        inventoryCoverage: CanonicalInventoryCoverageReport,
        retirementReadiness: CanonicalRetirementReadinessReport,
        objectProjection: CanonicalLibraryProjection,
        unsupportedFacts: [CanonicalProductionUnsupportedFact] = [],
        diagnostics: [CanonicalProductionDiagnosticsEvent] = []
    ) {
        self.node = node
        self.manifest = manifest
        self.transferProjection = transferProjection
        self.inventoryCoverage = inventoryCoverage
        self.retirementReadiness = retirementReadiness
        self.objectProjection = objectProjection
        self.unsupportedFacts = unsupportedFacts.sorted { $0.id < $1.id }
        self.diagnostics = diagnostics
    }
}

nonisolated struct CanonicalProductionSnapshot: Codable, Equatable, Sendable {
    var node: CanonicalNode
    var manifest: CanonicalManifest
    var runtimeNodeState: CanonicalRuntimeNodeState
    var legacyActions: CanonicalLegacyActionSnapshot
    var unsupportedFacts: [CanonicalProductionUnsupportedFact]
    var diagnostics: [CanonicalProductionDiagnosticsEvent]

    nonisolated init(
        node: CanonicalNode,
        manifest: CanonicalManifest,
        runtimeNodeState: CanonicalRuntimeNodeState,
        legacyActions: CanonicalLegacyActionSnapshot = .empty,
        unsupportedFacts: [CanonicalProductionUnsupportedFact] = [],
        diagnostics: [CanonicalProductionDiagnosticsEvent] = []
    ) {
        self.node = node
        self.manifest = manifest
        self.runtimeNodeState = runtimeNodeState
        self.legacyActions = legacyActions
        self.unsupportedFacts = unsupportedFacts.sorted { $0.id < $1.id }
        self.diagnostics = diagnostics
    }
}

nonisolated struct CanonicalProductionCapabilitySummary: Codable, Equatable, Sendable {
    var nodeID: String
    var capabilities: [CanonicalProductionCapability]
    var supportedDomains: [CanonicalProductionDomain]
    var dryRunOnly: Bool

    nonisolated init(
        nodeID: String,
        capabilities: [CanonicalProductionCapability] = [],
        supportedDomains: [CanonicalProductionDomain] = [],
        dryRunOnly: Bool = true
    ) {
        self.nodeID = CanonicalProductionRedaction.safeIdentifier(nodeID, fallback: "node:unknown")
        self.capabilities = Array(Set(capabilities)).sorted { $0.rawValue < $1.rawValue }
        self.supportedDomains = Array(Set(supportedDomains)).sorted { $0.rawValue < $1.rawValue }
        self.dryRunOnly = dryRunOnly
    }
}

nonisolated struct CanonicalProductionPortReadiness: Codable, Equatable, Sendable {
    var generatedAt: CanonicalTimestamp
    var declaredPorts: [CanonicalProductionPortKind: Bool]
    var missingPorts: [CanonicalProductionPortKind]
    var dryRunOnly: Bool

    nonisolated init(
        declaredPorts: [CanonicalProductionPortKind: Bool],
        missingPorts: [CanonicalProductionPortKind],
        dryRunOnly: Bool = true,
        generatedAt: Date = Date()
    ) {
        self.generatedAt = CanonicalTimestamp(generatedAt)
        self.declaredPorts = declaredPorts
        self.missingPorts = Array(Set(missingPorts)).sorted { $0.rawValue < $1.rawValue }
        self.dryRunOnly = dryRunOnly
    }

    nonisolated var hasAllRequiredDryRunPorts: Bool {
        missingPorts.filter { [.file, .transport, .upload, .apply].contains($0) }.isEmpty
    }

    nonisolated var hasAllRequiredProductionPorts: Bool {
        hasAllRequiredDryRunPorts && !dryRunOnly
    }
}

nonisolated struct CanonicalProductionFileVerificationEvidence: Codable, Equatable, Sendable {
    var reference: CanonicalFileReference
    var resolution: CanonicalPathResolutionResult
    var expectedHashPrefix: String?
    var actualHashPrefix: String?
    var expectedByteSize: Int64?
    var actualByteSize: Int64?
    var hashVerified: Bool
    var sizeVerified: Bool
    var computedStreaming: Bool

    nonisolated init(
        reference: CanonicalFileReference,
        resolution: CanonicalPathResolutionResult,
        expectedHash: CanonicalHash? = nil,
        actualHash: CanonicalHash? = nil,
        expectedByteSize: Int64? = nil,
        actualByteSize: Int64? = nil,
        computedStreaming: Bool = false
    ) {
        self.reference = reference
        self.resolution = resolution
        self.expectedHashPrefix = expectedHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.actualHashPrefix = actualHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.expectedByteSize = expectedByteSize
        self.actualByteSize = actualByteSize
        self.hashVerified = expectedHash == nil || expectedHash == actualHash
        self.sizeVerified = expectedByteSize == nil || expectedByteSize == actualByteSize
        self.computedStreaming = computedStreaming
    }
}

nonisolated struct CanonicalProductionFileReadResult: Codable, Equatable, Sendable {
    var bytes: Data
    var purpose: CanonicalFilePurpose
    var evidence: CanonicalProductionFileVerificationEvidence
    var metadataBlob: CanonicalMetadataBlob?
    var tombstoned: Bool
}

nonisolated struct CanonicalProductionFileWriteResult: Codable, Equatable, Sendable {
    var disposition: CanonicalFileWriteDisposition
    var purpose: CanonicalFilePurpose
    var evidence: CanonicalProductionFileVerificationEvidence
    var rollbackCheckpointID: String?
    var tombstoned: Bool
}

nonisolated struct CanonicalProductionMetadataReadRequest: Codable, Equatable, Sendable {
    var objectID: String
    var reference: CanonicalFileReference

    nonisolated init(objectID: String, reference: CanonicalFileReference) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.reference = reference
    }
}

nonisolated struct CanonicalProductionArtifactReadRequest: Codable, Equatable, Sendable {
    var artifactID: String
    var reference: CanonicalFileReference
    var expectedContentHash: CanonicalHash?
    var expectedByteSize: Int64?

    nonisolated init(
        artifactID: String,
        reference: CanonicalFileReference,
        expectedContentHash: CanonicalHash? = nil,
        expectedByteSize: Int64? = nil
    ) {
        self.artifactID = CanonicalProductionRedaction.safeIdentifier(artifactID, fallback: "artifact:unknown")
        self.reference = reference
        self.expectedContentHash = expectedContentHash
        self.expectedByteSize = expectedByteSize
    }
}

nonisolated struct CanonicalProductionArtifactVerifyRequest: Codable, Equatable, Sendable {
    var reference: CanonicalFileReference
    var expectedContentHash: CanonicalHash?
    var expectedByteSize: Int64?
    var requireStreamingHash: Bool

    nonisolated init(
        reference: CanonicalFileReference,
        expectedContentHash: CanonicalHash? = nil,
        expectedByteSize: Int64? = nil,
        requireStreamingHash: Bool = true
    ) {
        self.reference = reference
        self.expectedContentHash = expectedContentHash
        self.expectedByteSize = expectedByteSize
        self.requireStreamingHash = requireStreamingHash
    }
}

nonisolated struct CanonicalProductionHashRequest: Codable, Equatable, Sendable {
    var reference: CanonicalFileReference
    var requireStreaming: Bool
    var expectedByteSize: Int64?

    nonisolated init(reference: CanonicalFileReference, requireStreaming: Bool = true, expectedByteSize: Int64? = nil) {
        self.reference = reference
        self.requireStreaming = requireStreaming
        self.expectedByteSize = expectedByteSize
    }
}

nonisolated struct CanonicalProductionHashResult: Codable, Equatable, Sendable {
    var contentHash: CanonicalHash
    var byteSize: Int64
    var computedStreaming: Bool
    var evidence: CanonicalProductionFileVerificationEvidence
}

nonisolated struct CanonicalProductionTombstoneRequest: Codable, Equatable, Sendable {
    var reference: CanonicalFileReference
    var reason: String

    nonisolated init(reference: CanonicalFileReference, reason: String) {
        self.reference = reference
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? "softTombstone"
    }
}

nonisolated struct CanonicalProductionFileRollbackRequest: Codable, Equatable, Sendable {
    var checkpointID: String
    var reference: CanonicalFileReference

    nonisolated init(checkpointID: String, reference: CanonicalFileReference) {
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "rollback-checkpoint")
        self.reference = reference
    }
}

nonisolated enum CanonicalProductionHTTPMethod: String, Codable, Equatable, Sendable {
    case get = "GET"
    case post = "POST"
}

nonisolated struct CanonicalProductionTransportBuildRequest: Codable, Equatable, Sendable {
    var source: CanonicalNode
    var destination: CanonicalNode
    var route: CanonicalTransportRoute
    var method: CanonicalProductionHTTPMethod
    var existingRoutePath: String
    var contentType: String
    var body: Data
    var timestamp: CanonicalTimestamp
    var nonce: String
    var requiresExternalSigner: Bool

    nonisolated init(
        source: CanonicalNode,
        destination: CanonicalNode,
        route: CanonicalTransportRoute,
        method: CanonicalProductionHTTPMethod = .post,
        existingRoutePath: String,
        contentType: String = "application/json",
        body: Data = Data(),
        timestamp: Date = Date(),
        nonce: String,
        requiresExternalSigner: Bool = true
    ) {
        self.source = source
        self.destination = destination
        self.route = route
        self.method = method
        self.existingRoutePath = CanonicalProductionRedaction.safeDiagnosticText(existingRoutePath) ?? route.rawValue
        self.contentType = CanonicalProductionRedaction.safeDiagnosticText(contentType) ?? "application/json"
        self.body = body
        self.timestamp = CanonicalTimestamp(timestamp)
        self.nonce = CanonicalProductionRedaction.safeIdentifier(nonce, fallback: "nonce:required")
        self.requiresExternalSigner = requiresExternalSigner
    }
}

nonisolated struct CanonicalProductionSignedRequest: Codable, Equatable, Sendable {
    var buildRequest: CanonicalProductionTransportBuildRequest
    var bodyHash: CanonicalHash
    var signaturePrefix: String?
    var signerDescription: String?

    nonisolated init(
        buildRequest: CanonicalProductionTransportBuildRequest,
        bodyHash: CanonicalHash? = nil,
        signature: String? = nil,
        signerDescription: String? = nil
    ) {
        self.buildRequest = buildRequest
        self.bodyHash = bodyHash ?? CanonicalTransportEnvelope.hash(buildRequest.body)
        self.signaturePrefix = CanonicalProductionRedaction.hashPrefix(signature)
        self.signerDescription = CanonicalProductionRedaction.safeDiagnosticText(signerDescription)
    }
}

nonisolated struct CanonicalProductionTransportExchangeResult: Codable, Equatable, Sendable {
    var request: CanonicalProductionSignedRequest
    var response: CanonicalTransportResponse
    var responseVerified: Bool
    var usedExistingRoute: Bool
    var sideEffect: CanonicalProductionSideEffect?
}

nonisolated struct CanonicalProductionTransportVerification: Codable, Equatable, Sendable {
    var route: CanonicalTransportRoute
    var bodyHashVerified: Bool
    var responseHashVerified: Bool
    var timestampAccepted: Bool
    var externalVerifierRequired: Bool
}

nonisolated struct CanonicalProductionManifestExchangeRequest: Codable, Equatable, Sendable {
    var localManifest: CanonicalManifest
    var peerNode: CanonicalNode
    var trigger: CanonicalSyncPlanTrigger
}

nonisolated struct CanonicalProductionArtifactRequest: Codable, Equatable, Sendable {
    var objectID: String
    var artifactID: String
    var kind: CanonicalArtifact.Kind
    var logicalPathToken: String?

    nonisolated init(objectID: String, artifactID: String, kind: CanonicalArtifact.Kind, logicalPathToken: String? = nil) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.artifactID = CanonicalProductionRedaction.safeIdentifier(artifactID, fallback: kind.rawValue)
        self.kind = kind
        self.logicalPathToken = logicalPathToken.flatMap(CanonicalProjectionContract.safeLogicalPathToken)
    }
}

nonisolated struct CanonicalProductionUploadCancelRequest: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID
    var reason: String
}

nonisolated enum CanonicalProductionUploadFailureKind: String, Codable, Equatable, Sendable {
    case retryable
    case conflict
    case fatal
}

nonisolated struct CanonicalProductionUploadFailure: Codable, Equatable, Sendable {
    var objectID: String
    var code: String
    var message: String?

    nonisolated init(objectID: String, code: String, message: String? = nil) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.code = CanonicalProductionRedaction.safeDiagnosticText(code) ?? "unknown"
        self.message = CanonicalProductionRedaction.safeDiagnosticText(message)
    }
}

nonisolated struct CanonicalProductionUploadFailureClassification: Codable, Equatable, Sendable {
    var kind: CanonicalProductionUploadFailureKind
    var retry: CanonicalRetryPolicySnapshot?
    var reason: String
}

nonisolated struct CanonicalProductionUploadLedgerSnapshot: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID?
    var confirmedBytes: Int64
    var totalBytes: Int64?
    var contentHashPrefix: String?
    var phase: CanonicalUploadSessionPhase?
    var retry: CanonicalRetryPolicySnapshot?

    nonisolated init(
        objectID: String,
        sessionID: CanonicalUploadSessionID? = nil,
        confirmedBytes: Int64 = 0,
        totalBytes: Int64? = nil,
        contentHash: CanonicalHash? = nil,
        phase: CanonicalUploadSessionPhase? = nil,
        retry: CanonicalRetryPolicySnapshot? = nil
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.sessionID = sessionID
        self.confirmedBytes = confirmedBytes
        self.totalBytes = totalBytes
        self.contentHashPrefix = contentHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.phase = phase
        self.retry = retry
    }
}

nonisolated struct CanonicalProductionUploadRollbackRequest: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID?
    var checkpointID: String
}

nonisolated struct CanonicalProductionApplyExecutionRequest: Codable, Equatable, Sendable {
    var action: CanonicalApplyAction
    var rollbackCheckpointID: String?
}

nonisolated struct CanonicalProductionApplyPrecondition: Codable, Equatable, Sendable {
    var actionID: String
    var target: CanonicalApplyTarget
    var expectedHashPrefix: String?
    var accepted: Bool
    var reason: String?

    nonisolated init(
        actionID: String,
        target: CanonicalApplyTarget,
        expectedHashPrefix: String? = nil,
        accepted: Bool,
        reason: String? = nil
    ) {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(actionID, fallback: "apply-precondition")
        self.target = target
        self.expectedHashPrefix = CanonicalProductionRedaction.hashPrefix(expectedHashPrefix)
        self.accepted = accepted
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason)
    }
}

nonisolated struct CanonicalProductionApplyPostcondition: Codable, Equatable, Sendable {
    var actionID: String
    var target: CanonicalApplyTarget
    var actualHashPrefix: String?
    var accepted: Bool
    var reason: String?

    nonisolated init(
        actionID: String,
        target: CanonicalApplyTarget,
        actualHashPrefix: String? = nil,
        accepted: Bool,
        reason: String? = nil
    ) {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(actionID, fallback: "apply-postcondition")
        self.target = target
        self.actualHashPrefix = CanonicalProductionRedaction.hashPrefix(actualHashPrefix)
        self.accepted = accepted
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason)
    }
}

nonisolated struct CanonicalProductionApplyResult: Codable, Equatable, Sendable {
    var actionID: String
    var status: CanonicalApplyExecutionStatus
    var precondition: CanonicalProductionApplyPrecondition?
    var postcondition: CanonicalProductionApplyPostcondition?
    var sideEffect: CanonicalProductionSideEffect?
    var rollbackCheckpointID: String?
}

nonisolated protocol CanonicalProductionFilePort: Sendable {
    var isDryRunOnly: Bool { get }
    var capabilities: [CanonicalProductionCapability] { get }

    func resolveRootBound(_ reference: CanonicalFileReference) async throws -> CanonicalPathResolutionResult
    func readMetadata(_ request: CanonicalProductionMetadataReadRequest) async throws -> CanonicalProductionFileReadResult
    func writeMetadata(_ intent: CanonicalFileWriteIntent, rollbackCheckpoint: CanonicalRollbackCheckpoint?) async throws -> CanonicalProductionFileWriteResult
    func readArtifact(_ request: CanonicalProductionArtifactReadRequest) async throws -> CanonicalProductionFileReadResult
    func writeArtifactAtomic(_ intent: CanonicalFileWriteIntent, rollbackCheckpoint: CanonicalRollbackCheckpoint?) async throws -> CanonicalProductionFileWriteResult
    func verifyArtifact(_ request: CanonicalProductionArtifactVerifyRequest) async throws -> CanonicalProductionFileVerificationEvidence
    func markTombstone(_ request: CanonicalProductionTombstoneRequest) async throws -> CanonicalProductionFileWriteResult
    func listKnownArtifacts(rootToken: CanonicalRootToken, objectID: String?) async throws -> [CanonicalProductionArtifactDescriptor]
    func listKnownObjects(rootToken: CanonicalRootToken) async throws -> [String]
    func computeHash(_ request: CanonicalProductionHashRequest) async throws -> CanonicalProductionHashResult
    func rollbackWrite(_ request: CanonicalProductionFileRollbackRequest) async throws -> CanonicalRollbackResult

    func metadataSnapshot(objectID: String) async throws -> Data?
    func artifactDescriptor(for artifact: CanonicalArtifact) async throws -> CanonicalProductionArtifactDescriptor
    func validateRead(reference: CanonicalFileReference) async throws -> CanonicalProductionReadProjection
    func resolveLogicalToken(_ token: String, rootToken: CanonicalRootToken) async throws -> CanonicalPathResolutionResult
    func verifyContainment(_ reference: CanonicalFileReference) async throws -> Bool
    func projectWrite(_ intent: CanonicalFileWriteIntent) async throws -> CanonicalProductionWriteIntentProjection
}

nonisolated protocol CanonicalProductionTransportPort: Sendable {
    var isDryRunOnly: Bool { get }
    var routeCapabilities: [CanonicalProductionTransportRouteCapability] { get }
    var realNetworkExecutionEnabled: Bool { get }

    func buildSignedRequest(_ request: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionSignedRequest
    func sendRequest(_ request: CanonicalProductionSignedRequest) async throws -> CanonicalProductionTransportExchangeResult
    func receiveResponse(_ response: CanonicalTransportResponse, for request: CanonicalProductionSignedRequest) async throws -> CanonicalProductionTransportExchangeResult
    func verifyResponse(_ exchange: CanonicalProductionTransportExchangeResult) async throws -> CanonicalProductionTransportVerification
    func exchangeManifest(_ request: CanonicalProductionManifestExchangeRequest) async throws -> CanonicalProductionTransportExchangeResult
    func requestArtifact(_ request: CanonicalProductionArtifactRequest, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult
    func sendApplyMetadata(_ action: CanonicalApplyAction, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult
    func startUploadSession(_ request: CanonicalUploadStartRequest, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult
    func queryUploadSession(_ request: CanonicalUploadStatusRequest, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult
    func sendUploadChunk(_ chunk: CanonicalUploadChunk, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult
    func finalizeUploadSession(_ request: CanonicalUploadFinalizeRequest, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult
    func cancelUploadSession(_ request: CanonicalProductionUploadCancelRequest, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult

    func buildEnvelopeDryRun(
        source: CanonicalNode,
        destination: CanonicalNode,
        route: CanonicalTransportRoute,
        body: Data
    ) async throws -> CanonicalProductionTransportEnvelopeDryRun
    func decodeResponseDryRun(_ response: CanonicalTransportResponse) async throws -> CanonicalTransportResponse
}

nonisolated protocol CanonicalProductionUploadPort: Sendable {
    var isDryRunOnly: Bool { get }
    var resumableSessionSupported: Bool { get }
    var chunkSizePolicy: Int { get }

    func startResumableUpload(_ request: CanonicalUploadStartRequest, now: Date) async throws -> CanonicalUploadSessionStatus
    func resumeUpload(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> CanonicalUploadSessionStatus
    func uploadChunk(_ chunk: CanonicalUploadChunk, now: Date) async throws -> CanonicalUploadSessionStatus
    func queryConfirmedBytes(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> Int64
    func finalizeUpload(_ request: CanonicalUploadFinalizeRequest, now: Date) async throws -> CanonicalUploadSessionStatus
    func cancelUpload(_ request: CanonicalProductionUploadCancelRequest, now: Date) async throws -> CanonicalRollbackResult
    func classifyUploadFailure(_ failure: CanonicalProductionUploadFailure) -> CanonicalProductionUploadFailureClassification
    func readUploadLedger(objectID: String) async throws -> CanonicalProductionUploadLedgerSnapshot
    func writeUploadLedger(_ snapshot: CanonicalProductionUploadLedgerSnapshot) async throws -> CanonicalProductionUploadLedgerSnapshot
    func projectRetry(_ snapshot: CanonicalProductionUploadLedgerSnapshot, now: Date) -> CanonicalRetryPolicySnapshot?
    func rollbackUploadState(_ request: CanonicalProductionUploadRollbackRequest) async throws -> CanonicalRollbackResult

    func projectUploadDryRun(
        object: CanonicalRecordingObject,
        artifact: CanonicalArtifact
    ) async throws -> CanonicalProductionUploadTrace
}

nonisolated protocol CanonicalProductionApplyPort: Sendable {
    var isDryRunOnly: Bool { get }
    var metadataApplySupported: Bool { get }
    var generatedArtifactApplySupported: Bool { get }
    var tombstoneApplySupported: Bool { get }
    var conflictRecordSupported: Bool { get }

    func applyMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult
    func sendMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult
    func applyGeneratedArtifact(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult
    func requestGeneratedArtifact(_ request: CanonicalProductionArtifactRequest) async throws -> CanonicalProductionApplyResult
    func applyObjectTombstone(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult
    func applyLibraryTombstone(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult
    func recordConflict(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult
    func verifyPrecondition(_ precondition: CanonicalProductionApplyPrecondition) async throws -> CanonicalProductionApplyPrecondition
    func verifyPostcondition(_ postcondition: CanonicalProductionApplyPostcondition) async throws -> CanonicalProductionApplyPostcondition
    func rollbackApply(_ request: CanonicalRollbackAction) async throws -> CanonicalRollbackResult

    func projectApplyDryRun(_ action: CanonicalApplyAction) async throws -> CanonicalProductionApplyTrace
}

nonisolated protocol CanonicalProductionSyncClockPort: Sendable {
    func now() -> CanonicalTimestamp
    func monotonicNow() -> TimeInterval
    func validateTimestampWindow(_ timestamp: CanonicalTimestamp, now: CanonicalTimestamp, tolerance: TimeInterval) -> Bool
    func triggerContext(defaultTrigger: CanonicalSyncPlanTrigger) -> CanonicalSyncPlanTrigger
}

nonisolated protocol CanonicalProductionDiagnosticsPort: Sendable {
    func record(_ event: CanonicalProductionDiagnosticsEvent) async
    func recordKernelEvent(_ event: CanonicalProductionDiagnosticsEvent) async
    func recordDryRunEvent(_ event: CanonicalProductionDiagnosticsEvent) async
    func recordProductionEvent(_ event: CanonicalProductionDiagnosticsEvent) async
    func recordConflict(_ event: CanonicalProductionDiagnosticsEvent) async
    func recordMigrationGate(_ audit: CanonicalProductionExecutionAudit) async
    func recordRedactedTrace(_ trace: CanonicalProductionExecutionTrace) async
}

nonisolated protocol CanonicalProductionCapabilityPort: Sendable {
    func summary(for node: CanonicalNode) -> CanonicalProductionCapabilitySummary
    func supports(domain: CanonicalProductionDomain, operation: CanonicalProductionOperation) -> Bool
    func localCapabilities() -> CanonicalProductionCapabilitySummary
    func peerCapabilities() -> CanonicalProductionCapabilitySummary?
    func validateCapability(domain: CanonicalProductionDomain, operation: CanonicalProductionOperation) -> Bool
    func validateSchema(_ manifest: CanonicalManifest) -> Bool
}

nonisolated struct CanonicalProductionPortSet: Sendable {
    var file: (any CanonicalProductionFilePort)?
    var transport: (any CanonicalProductionTransportPort)?
    var upload: (any CanonicalProductionUploadPort)?
    var apply: (any CanonicalProductionApplyPort)?
    var syncClock: (any CanonicalProductionSyncClockPort)?
    var diagnostics: (any CanonicalProductionDiagnosticsPort)?
    var capability: (any CanonicalProductionCapabilityPort)?

    nonisolated init(
        file: (any CanonicalProductionFilePort)? = nil,
        transport: (any CanonicalProductionTransportPort)? = nil,
        upload: (any CanonicalProductionUploadPort)? = nil,
        apply: (any CanonicalProductionApplyPort)? = nil,
        syncClock: (any CanonicalProductionSyncClockPort)? = nil,
        diagnostics: (any CanonicalProductionDiagnosticsPort)? = nil,
        capability: (any CanonicalProductionCapabilityPort)? = nil
    ) {
        self.file = file
        self.transport = transport
        self.upload = upload
        self.apply = apply
        self.syncClock = syncClock
        self.diagnostics = diagnostics
        self.capability = capability
    }

    nonisolated var missingRequiredPorts: [CanonicalProductionPortKind] {
        var missing: [CanonicalProductionPortKind] = []
        if file == nil { missing.append(.file) }
        if transport == nil { missing.append(.transport) }
        if upload == nil { missing.append(.upload) }
        if apply == nil { missing.append(.apply) }
        return missing
    }

    nonisolated func readiness(generatedAt: Date = Date()) -> CanonicalProductionPortReadiness {
        let declared: [CanonicalProductionPortKind: Bool] = [
            .file: file != nil,
            .transport: transport != nil,
            .upload: upload != nil,
            .apply: apply != nil,
            .syncClock: syncClock != nil,
            .diagnostics: diagnostics != nil,
            .capability: capability != nil
        ]
        let dryRunOnly = (file?.isDryRunOnly ?? true)
            && (transport?.isDryRunOnly ?? true)
            && (upload?.isDryRunOnly ?? true)
            && (apply?.isDryRunOnly ?? true)
            && !(transport?.realNetworkExecutionEnabled ?? false)
        return CanonicalProductionPortReadiness(
            declaredPorts: declared,
            missingPorts: missingRequiredPorts,
            dryRunOnly: dryRunOnly,
            generatedAt: generatedAt
        )
    }
}

extension CanonicalProductionFilePort {
    nonisolated func resolveRootBound(_ reference: CanonicalFileReference) async throws -> CanonicalPathResolutionResult {
        try await resolveLogicalToken(reference.logicalPathToken, rootToken: reference.rootToken)
    }

    nonisolated func readMetadata(_ request: CanonicalProductionMetadataReadRequest) async throws -> CanonicalProductionFileReadResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionReadMetadataNotImplemented")
    }

    nonisolated func writeMetadata(_ intent: CanonicalFileWriteIntent, rollbackCheckpoint: CanonicalRollbackCheckpoint?) async throws -> CanonicalProductionFileWriteResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionWriteMetadataNotImplemented")
    }

    nonisolated func readArtifact(_ request: CanonicalProductionArtifactReadRequest) async throws -> CanonicalProductionFileReadResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionReadArtifactNotImplemented")
    }

    nonisolated func writeArtifactAtomic(_ intent: CanonicalFileWriteIntent, rollbackCheckpoint: CanonicalRollbackCheckpoint?) async throws -> CanonicalProductionFileWriteResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionWriteArtifactNotImplemented")
    }

    nonisolated func verifyArtifact(_ request: CanonicalProductionArtifactVerifyRequest) async throws -> CanonicalProductionFileVerificationEvidence {
        let resolution = try await resolveRootBound(request.reference)
        return CanonicalProductionFileVerificationEvidence(
            reference: request.reference,
            resolution: resolution,
            expectedHash: request.expectedContentHash,
            actualHash: nil,
            expectedByteSize: request.expectedByteSize,
            actualByteSize: nil,
            computedStreaming: request.requireStreamingHash
        )
    }

    nonisolated func markTombstone(_ request: CanonicalProductionTombstoneRequest) async throws -> CanonicalProductionFileWriteResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionMarkTombstoneNotImplemented")
    }

    nonisolated func listKnownArtifacts(rootToken: CanonicalRootToken, objectID: String?) async throws -> [CanonicalProductionArtifactDescriptor] {
        []
    }

    nonisolated func listKnownObjects(rootToken: CanonicalRootToken) async throws -> [String] {
        []
    }

    nonisolated func computeHash(_ request: CanonicalProductionHashRequest) async throws -> CanonicalProductionHashResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionComputeHashNotImplemented")
    }

    nonisolated func rollbackWrite(_ request: CanonicalProductionFileRollbackRequest) async throws -> CanonicalRollbackResult {
        CanonicalRollbackResult(
            planID: request.checkpointID,
            succeeded: false,
            failures: [CanonicalRollbackFailure(actionID: request.checkpointID, reason: "productionRollbackWriteNotImplemented")]
        )
    }
}

extension CanonicalProductionTransportPort {
    nonisolated func buildSignedRequest(_ request: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionSignedRequest {
        guard realNetworkExecutionEnabled else {
            throw CanonicalProductionPortError.networkExecutionSuppressed("productionNetworkExecutionDisabled")
        }
        return CanonicalProductionSignedRequest(buildRequest: request, signerDescription: "externalSignerRequired")
    }

    nonisolated func sendRequest(_ request: CanonicalProductionSignedRequest) async throws -> CanonicalProductionTransportExchangeResult {
        throw CanonicalProductionPortError.networkExecutionSuppressed("productionSendRequestNotImplemented")
    }

    nonisolated func receiveResponse(_ response: CanonicalTransportResponse, for request: CanonicalProductionSignedRequest) async throws -> CanonicalProductionTransportExchangeResult {
        guard response.hasValidBodyHash else {
            throw CanonicalTransportRuntimeError.invalidBodyHash("production-response")
        }
        return CanonicalProductionTransportExchangeResult(
            request: request,
            response: response,
            responseVerified: true,
            usedExistingRoute: true,
            sideEffect: nil
        )
    }

    nonisolated func verifyResponse(_ exchange: CanonicalProductionTransportExchangeResult) async throws -> CanonicalProductionTransportVerification {
        CanonicalProductionTransportVerification(
            route: exchange.request.buildRequest.route,
            bodyHashVerified: CanonicalTransportEnvelope.hash(exchange.request.buildRequest.body) == exchange.request.bodyHash,
            responseHashVerified: exchange.response.hasValidBodyHash,
            timestampAccepted: true,
            externalVerifierRequired: true
        )
    }

    nonisolated func exchangeManifest(_ request: CanonicalProductionManifestExchangeRequest) async throws -> CanonicalProductionTransportExchangeResult {
        let body = try CanonicalTransportJSON.encode(request.localManifest)
        let build = CanonicalProductionTransportBuildRequest(
            source: request.localManifest.node,
            destination: request.peerNode,
            route: .manifestExchange,
            existingRoutePath: "/sync/inventory",
            body: body,
            nonce: "external-nonce-required"
        )
        return try await sendRequest(try await buildSignedRequest(build))
    }

    nonisolated func requestArtifact(_ request: CanonicalProductionArtifactRequest, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    nonisolated func sendApplyMetadata(_ action: CanonicalApplyAction, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    nonisolated func startUploadSession(_ request: CanonicalUploadStartRequest, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    nonisolated func queryUploadSession(_ request: CanonicalUploadStatusRequest, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    nonisolated func sendUploadChunk(_ chunk: CanonicalUploadChunk, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    nonisolated func finalizeUploadSession(_ request: CanonicalUploadFinalizeRequest, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    nonisolated func cancelUploadSession(_ request: CanonicalProductionUploadCancelRequest, envelope: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }
}

extension CanonicalProductionUploadPort {
    nonisolated func startResumableUpload(_ request: CanonicalUploadStartRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        throw CanonicalProductionPortError.productionMutationAttempted("productionStartResumableUploadNotImplemented")
    }

    nonisolated func resumeUpload(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        throw CanonicalProductionPortError.productionMutationAttempted("productionResumeUploadNotImplemented")
    }

    nonisolated func uploadChunk(_ chunk: CanonicalUploadChunk, now: Date) async throws -> CanonicalUploadSessionStatus {
        throw CanonicalProductionPortError.productionMutationAttempted("productionUploadChunkNotImplemented")
    }

    nonisolated func queryConfirmedBytes(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> Int64 {
        try await resumeUpload(request, now: now).confirmedBytes
    }

    nonisolated func finalizeUpload(_ request: CanonicalUploadFinalizeRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        throw CanonicalProductionPortError.productionMutationAttempted("productionFinalizeUploadNotImplemented")
    }

    nonisolated func cancelUpload(_ request: CanonicalProductionUploadCancelRequest, now: Date) async throws -> CanonicalRollbackResult {
        CanonicalRollbackResult(
            planID: request.sessionID.rawValue,
            succeeded: false,
            failures: [CanonicalRollbackFailure(actionID: request.sessionID.rawValue, reason: "productionCancelUploadNotImplemented")]
        )
    }

    nonisolated func classifyUploadFailure(_ failure: CanonicalProductionUploadFailure) -> CanonicalProductionUploadFailureClassification {
        CanonicalProductionUploadFailureClassification(kind: .fatal, retry: nil, reason: failure.code)
    }

    nonisolated func readUploadLedger(objectID: String) async throws -> CanonicalProductionUploadLedgerSnapshot {
        CanonicalProductionUploadLedgerSnapshot(objectID: objectID)
    }

    nonisolated func writeUploadLedger(_ snapshot: CanonicalProductionUploadLedgerSnapshot) async throws -> CanonicalProductionUploadLedgerSnapshot {
        throw CanonicalProductionPortError.productionMutationAttempted("productionWriteUploadLedgerNotImplemented")
    }

    nonisolated func projectRetry(_ snapshot: CanonicalProductionUploadLedgerSnapshot, now: Date) -> CanonicalRetryPolicySnapshot? {
        snapshot.retry
    }

    nonisolated func rollbackUploadState(_ request: CanonicalProductionUploadRollbackRequest) async throws -> CanonicalRollbackResult {
        CanonicalRollbackResult(
            planID: request.checkpointID,
            succeeded: false,
            failures: [CanonicalRollbackFailure(actionID: request.objectID, reason: "productionRollbackUploadNotImplemented")]
        )
    }
}

extension CanonicalProductionApplyPort {
    nonisolated func applyMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionApplyMetadataNotImplemented")
    }

    nonisolated func sendMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionSendMetadataNotImplemented")
    }

    nonisolated func applyGeneratedArtifact(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionApplyGeneratedArtifactNotImplemented")
    }

    nonisolated func requestGeneratedArtifact(_ request: CanonicalProductionArtifactRequest) async throws -> CanonicalProductionApplyResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionRequestGeneratedArtifactNotImplemented")
    }

    nonisolated func applyObjectTombstone(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionApplyObjectTombstoneNotImplemented")
    }

    nonisolated func applyLibraryTombstone(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionApplyLibraryTombstoneNotImplemented")
    }

    nonisolated func recordConflict(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        throw CanonicalProductionPortError.productionMutationAttempted("productionRecordConflictNotImplemented")
    }

    nonisolated func verifyPrecondition(_ precondition: CanonicalProductionApplyPrecondition) async throws -> CanonicalProductionApplyPrecondition {
        precondition
    }

    nonisolated func verifyPostcondition(_ postcondition: CanonicalProductionApplyPostcondition) async throws -> CanonicalProductionApplyPostcondition {
        postcondition
    }

    nonisolated func rollbackApply(_ request: CanonicalRollbackAction) async throws -> CanonicalRollbackResult {
        CanonicalRollbackResult(
            planID: request.checkpointID ?? request.actionID,
            succeeded: false,
            failures: [CanonicalRollbackFailure(actionID: request.actionID, reason: "productionRollbackApplyNotImplemented")]
        )
    }
}

extension CanonicalProductionSyncClockPort {
    nonisolated func monotonicNow() -> TimeInterval {
        Date().timeIntervalSinceReferenceDate
    }

    nonisolated func validateTimestampWindow(_ timestamp: CanonicalTimestamp, now: CanonicalTimestamp, tolerance: TimeInterval) -> Bool {
        abs(now.date.timeIntervalSince(timestamp.date)) <= tolerance
    }
}

extension CanonicalProductionDiagnosticsPort {
    func recordKernelEvent(_ event: CanonicalProductionDiagnosticsEvent) async {
        await record(event)
    }

    func recordDryRunEvent(_ event: CanonicalProductionDiagnosticsEvent) async {
        await record(event)
    }

    func recordProductionEvent(_ event: CanonicalProductionDiagnosticsEvent) async {
        await record(event)
    }

    func recordConflict(_ event: CanonicalProductionDiagnosticsEvent) async {
        await record(event)
    }

    func recordMigrationGate(_ audit: CanonicalProductionExecutionAudit) async {
        await record(
            CanonicalProductionDiagnosticsEvent(
                kind: audit.allowed ? .canonicalEligibleForManualMigrationDesign : .canonicalProductionMigrationBlocked,
                reason: audit.rejectionReasons.map(\.rawValue).joined(separator: ","),
                dryRun: false,
                generatedAt: audit.generatedAt.date
            )
        )
    }

    func recordRedactedTrace(_ trace: CanonicalProductionExecutionTrace) async {
        await record(
            CanonicalProductionDiagnosticsEvent(
                kind: .canonicalProductionPortsDeclared,
                action: trace.operationID,
                reason: "sideEffects:\(trace.sideEffects.count)",
                dryRun: trace.mode != .productionExecute,
                generatedAt: trace.generatedAt.date
            )
        )
    }
}

extension CanonicalProductionCapabilityPort {
    nonisolated func localCapabilities() -> CanonicalProductionCapabilitySummary {
        CanonicalProductionCapabilitySummary(nodeID: "local")
    }

    nonisolated func peerCapabilities() -> CanonicalProductionCapabilitySummary? {
        nil
    }

    nonisolated func validateCapability(domain: CanonicalProductionDomain, operation: CanonicalProductionOperation) -> Bool {
        supports(domain: domain, operation: operation)
    }

    nonisolated func validateSchema(_ manifest: CanonicalManifest) -> Bool {
        manifest.schemaVersion == CanonicalManifest.currentSchemaVersion && manifest.hasValidManifestHash
    }
}

nonisolated enum CanonicalProductionRedaction {
    nonisolated static func hashPrefix(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return nil
        }
        return String(normalized.prefix(12))
    }

    nonisolated static func safeIdentifier(_ value: String, fallback: String) -> String {
        safeDiagnosticText(value) ?? fallback
    }

    nonisolated static func safeFileName(_ value: String?) -> String? {
        guard let text = safeDiagnosticText(value) else {
            return nil
        }
        let separators = CharacterSet(charactersIn: "/\\")
        guard text.rangeOfCharacter(from: separators) == nil else {
            return "redacted-file-\(hashPrefix(CanonicalHash.sha256String(text).value) ?? "unknown")"
        }
        return text
    }

    nonisolated static func safeDiagnosticText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard !trimmed.isEmpty else {
            return nil
        }
        if containsSensitivePathSignal(trimmed) {
            return "redacted-\(hashPrefix(CanonicalHash.sha256String(trimmed).value) ?? "diagnostic")"
        }
        return String(trimmed.prefix(160))
    }

    nonisolated static func containsSensitivePathSignal(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.contains("file://")
            || lowercased.contains("/users/")
            || lowercased.contains("/private/")
            || lowercased.contains("\\")
            || lowercased.hasPrefix("~")
    }
}
