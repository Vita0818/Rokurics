//
//  MacCanonicalDryRunPorts.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated struct MacCanonicalDryRunFilePort: CanonicalProductionFilePort {
    let isDryRunOnly = true
    let capabilities: [CanonicalProductionCapability] = [
        .dryRunOnly,
        .rootBoundFileAccess,
        .logicalTokenValidation,
        .containmentVerification,
        .atomicWriteProjection,
        .noPhysicalDelete
    ]

    private let resolver: CanonicalInMemoryPathResolver

    nonisolated init(rootBindings: [CanonicalRootToken: String] = [CanonicalRootToken("mac-production-root"): "mac/production/root"]) {
        self.resolver = CanonicalInMemoryPathResolver(rootBindings: rootBindings)
    }

    nonisolated func metadataSnapshot(objectID: String) async throws -> Data? {
        _ = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        return nil
    }

    nonisolated func artifactDescriptor(for artifact: CanonicalArtifact) async throws -> CanonicalProductionArtifactDescriptor {
        CanonicalProductionArtifactDescriptor(artifact: artifact)
    }

    nonisolated func validateRead(reference: CanonicalFileReference) async throws -> CanonicalProductionReadProjection {
        _ = try resolver.resolve(rootToken: reference.rootToken, logicalPathToken: reference.logicalPathToken)
        return CanonicalProductionReadProjection(reference: reference, wouldReadBytes: true, dryRun: true)
    }

    nonisolated func resolveLogicalToken(_ token: String, rootToken: CanonicalRootToken) async throws -> CanonicalPathResolutionResult {
        try resolver.resolve(rootToken: rootToken, logicalPathToken: token)
    }

    nonisolated func verifyContainment(_ reference: CanonicalFileReference) async throws -> Bool {
        try resolver.resolve(rootToken: reference.rootToken, logicalPathToken: reference.logicalPathToken).isInsideRoot
    }

    nonisolated func projectWrite(_ intent: CanonicalFileWriteIntent) async throws -> CanonicalProductionWriteIntentProjection {
        _ = try resolver.resolve(rootToken: intent.reference.rootToken, logicalPathToken: intent.reference.logicalPathToken)
        let hash = InMemoryCanonicalFileStore.hash(intent.bytes, policy: intent.hashPolicy)
        return CanonicalProductionWriteIntentProjection(
            reference: intent.reference,
            purpose: intent.purpose,
            wouldWrite: true,
            suppressedBecauseDryRun: true,
            noPhysicalDelete: true,
            byteSize: Int64(intent.bytes.count),
            contentHash: hash,
            disposition: intent.purpose == .tombstoneMarker ? .tombstoneMarked : .created,
            reason: "MacDryRunWriteSuppressed"
        )
    }
}

nonisolated struct MacCanonicalDryRunTransportPort: CanonicalProductionTransportPort {
    let isDryRunOnly = true
    let realNetworkExecutionEnabled = false
    let routeCapabilities: [CanonicalProductionTransportRouteCapability]

    nonisolated init(routes: [CanonicalTransportRoute] = CanonicalTransportRoute.allCases) {
        self.routeCapabilities = routes.map {
            CanonicalProductionTransportRouteCapability(route: $0, requiresSigning: true, requiresVerification: true, dryRunOnly: true)
        }
    }

    nonisolated func buildEnvelopeDryRun(
        source: CanonicalNode,
        destination: CanonicalNode,
        route: CanonicalTransportRoute,
        body: Data
    ) async throws -> CanonicalProductionTransportEnvelopeDryRun {
        guard routeCapabilities.contains(where: { $0.route == route }) else {
            throw CanonicalProductionPortError.routeBypassRisk(route.rawValue)
        }
        return CanonicalProductionTransportEnvelopeDryRun(
            route: route,
            sourceNodeID: source.nodeID,
            destinationNodeID: destination.nodeID,
            bodyHash: CanonicalTransportEnvelope.hash(body),
            requiresSigning: true,
            requiresVerification: true,
            reason: "MacDryRunNetworkSuppressed"
        )
    }

    nonisolated func decodeResponseDryRun(_ response: CanonicalTransportResponse) async throws -> CanonicalTransportResponse {
        guard response.hasValidBodyHash else {
            throw CanonicalTransportRuntimeError.invalidBodyHash("dry-run-response")
        }
        return response
    }
}

nonisolated struct MacCanonicalDryRunUploadPort: CanonicalProductionUploadPort {
    let isDryRunOnly = true
    let resumableSessionSupported = true
    let chunkSizePolicy: Int

    nonisolated init(chunkSizePolicy: Int = 4 * 1024 * 1024) {
        self.chunkSizePolicy = chunkSizePolicy
    }

    nonisolated func projectUploadDryRun(
        object: CanonicalRecordingObject,
        artifact: CanonicalArtifact
    ) async throws -> CanonicalProductionUploadTrace {
        guard artifact.kind == .audio else {
            throw CanonicalProductionPortError.unsupportedObject("uploadOnlySupportsAudio")
        }
        return CanonicalProductionUploadTrace(
            objectID: object.objectID,
            artifactID: artifact.artifactID,
            totalBytes: artifact.byteSize,
            totalHash: artifact.contentHash,
            chunkSize: chunkSizePolicy,
            resumable: true,
            route: .uploadStart,
            reason: "MacDryRunUploadSuppressed"
        )
    }
}

nonisolated struct MacCanonicalDryRunApplyPort: CanonicalProductionApplyPort {
    let isDryRunOnly = true
    let metadataApplySupported = true
    let generatedArtifactApplySupported = true
    let tombstoneApplySupported = true
    let conflictRecordSupported = true

    nonisolated init() {}

    nonisolated func projectApplyDryRun(_ action: CanonicalApplyAction) async throws -> CanonicalProductionApplyTrace {
        CanonicalProductionApplyTrace(action: action, wouldCallApplySyncManifest: false, reason: "MacDryRunApplySuppressed")
    }
}

nonisolated struct MacCanonicalDryRunClockPort: CanonicalProductionSyncClockPort {
    private let fixedDate: Date?

    nonisolated init(fixedDate: Date? = nil) {
        self.fixedDate = fixedDate
    }

    nonisolated func now() -> CanonicalTimestamp {
        CanonicalTimestamp(fixedDate ?? Date())
    }

    nonisolated func triggerContext(defaultTrigger: CanonicalSyncPlanTrigger) -> CanonicalSyncPlanTrigger {
        defaultTrigger
    }
}

actor MacCanonicalDryRunDiagnosticsPort: CanonicalProductionDiagnosticsPort {
    private(set) var events: [CanonicalProductionDiagnosticsEvent] = []

    func record(_ event: CanonicalProductionDiagnosticsEvent) async {
        events.append(event)
    }
}

nonisolated struct MacCanonicalDryRunCapabilityPort: CanonicalProductionCapabilityPort {
    private let supportedOperations: [CanonicalProductionDomain: Set<CanonicalProductionOperation>]

    nonisolated init(
        supportedOperations: [CanonicalProductionDomain: Set<CanonicalProductionOperation>] = MacCanonicalDryRunCapabilityPort.defaultSupportedOperations
    ) {
        self.supportedOperations = supportedOperations
    }

    nonisolated func summary(for node: CanonicalNode) -> CanonicalProductionCapabilitySummary {
        CanonicalProductionCapabilitySummary(
            nodeID: node.nodeID,
            capabilities: [
                .dryRunOnly,
                .rootBoundFileAccess,
                .routeSigning,
                .routeVerification,
                .resumableUploadProjection,
                .metadataApplyProjection,
                .generatedArtifactApplyProjection,
                .inMemoryDiagnostics
            ],
            supportedDomains: Array(supportedOperations.keys),
            dryRunOnly: true
        )
    }

    nonisolated func supports(domain: CanonicalProductionDomain, operation: CanonicalProductionOperation) -> Bool {
        supportedOperations[domain]?.contains(operation) ?? false
    }

    private nonisolated static let defaultSupportedOperations: [CanonicalProductionDomain: Set<CanonicalProductionOperation>] = [
        .recordingMetadata: [.metadataSnapshotRead, .applyMetadataProject],
        .recordingAudio: [.artifactDescriptorRead, .uploadStartProject, .uploadChunkProject, .uploadFinalizeProject],
        .generatedArtifacts: [.artifactDescriptorRead, .artifactBytesReadDryRun, .applyGeneratedArtifactProject],
        .folders: [.metadataSnapshotRead, .applyMetadataProject],
        .studyItems: [.metadataSnapshotRead, .applyMetadataProject],
        .standaloneNotes: [.metadataSnapshotRead, .applyMetadataProject],
        .tombstones: [.tombstoneApplyProject, .physicalDeleteSuppressed],
        .conflicts: [.recordConflictProject],
        .fileRuntime: [.logicalTokenResolve, .containmentVerify, .atomicWriteProject],
        .transportRuntime: [.routeEnvelopeBuild, .routeResponseDecode],
        .uploadRuntime: [.uploadStartProject, .uploadChunkProject, .uploadFinalizeProject],
        .apply: [.applyMetadataProject, .applyGeneratedArtifactProject, .recordConflictProject]
    ]
}

nonisolated enum MacCanonicalDryRunPorts {
    nonisolated static func makePortSet(
        rootBindings: [CanonicalRootToken: String] = [CanonicalRootToken("mac-production-root"): "mac/production/root"],
        chunkSizePolicy: Int = 4 * 1024 * 1024,
        diagnostics: MacCanonicalDryRunDiagnosticsPort = MacCanonicalDryRunDiagnosticsPort()
    ) -> CanonicalProductionPortSet {
        CanonicalProductionPortSet(
            file: MacCanonicalDryRunFilePort(rootBindings: rootBindings),
            transport: MacCanonicalDryRunTransportPort(),
            upload: MacCanonicalDryRunUploadPort(chunkSizePolicy: chunkSizePolicy),
            apply: MacCanonicalDryRunApplyPort(),
            syncClock: MacCanonicalDryRunClockPort(),
            diagnostics: diagnostics,
            capability: MacCanonicalDryRunCapabilityPort()
        )
    }
}
