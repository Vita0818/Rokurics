//
//  IPhoneCanonicalShadowPortFactory.swift
//  Rokurics
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated struct IPhoneCanonicalShadowPortFactory: Sendable {
    var configuration: CanonicalShadowMigrationConfiguration

    nonisolated init(configuration: CanonicalShadowMigrationConfiguration = .disabled) {
        self.configuration = configuration
    }

    nonisolated func makeOutput(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory?,
        legacyPlan: LocalNetworkSyncDiffPlan?,
        generatedAt: Date = Date()
    ) -> CanonicalShadowPortFactoryOutput {
        let portOutput = Self.makePortSet(for: configuration)
        let localSnapshot = Self.snapshot(
            from: localInventory,
            legacyActions: Self.legacyActionSnapshot(from: legacyPlan),
            action: "iPhoneShadowPortFactoryLocal",
            generatedAt: generatedAt
        )
        let peerSnapshot = peerInventory.flatMap {
            Self.snapshot(
                from: $0,
                legacyActions: .empty,
                action: "iPhoneShadowPortFactoryPeer",
                generatedAt: generatedAt
            )
        }
        let node = localSnapshot?.node ?? CanonicalNode(
            nodeID: localInventory.sourceDeviceID,
            platform: localInventory.sourcePlatform.rawValue,
            displayName: localInventory.device.deviceName
        )
        let capabilitySummary = portOutput.portSet.capability?.summary(for: node) ?? CanonicalProductionCapabilitySummary(nodeID: node.nodeID)
        let missingPortReport = portOutput.portSet.readiness(generatedAt: generatedAt)
        return CanonicalShadowPortFactoryOutput(
            portSet: portOutput.portSet,
            localSnapshot: localSnapshot,
            peerSnapshot: peerSnapshot,
            capabilities: capabilitySummary,
            missingPortReport: missingPortReport,
            suppressedSideEffects: CanonicalShadowMigrationSuppressedSideEffectSummary(configuration.policy.suppressedSideEffects),
            diagnosticsSafeSummary: Self.diagnosticsSummary(
                localInventory: localInventory,
                peerInventory: peerInventory,
                legacyPlan: legacyPlan,
                mode: configuration.effectiveMode,
                portReadiness: missingPortReport
            ),
            networkProbePolicy: configuration.policy.networkProbePolicy,
            shadowRootLifecycle: portOutput.lifecycle,
            realDataShadowCopyResult: nil,
            readOnlyTransportProbeResult: nil
        )
    }

    nonisolated private static func makePortSet(for configuration: CanonicalShadowMigrationConfiguration) -> (portSet: CanonicalProductionPortSet, lifecycle: CanonicalShadowRootLifecycle?) {
        guard configuration.effectiveMode.runsExecutionShadowPreparation else {
            return (IPhoneCanonicalDryRunPorts.makePortSet(), nil)
        }
        let rootKind: CanonicalShadowRootKind = configuration.effectiveMode == .executionShadowWithShadowFileStore
            ? .shadowCopy
            : .temporary
        let rootID = UUID().uuidString
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsCanonicalExecutionShadow", isDirectory: true)
            .appendingPathComponent("iPhone", isDirectory: true)
            .appendingPathComponent(rootID, isDirectory: true)
        let rootToken = CanonicalRootToken("iphone-execution-shadow-root")
        let binding = CanonicalShadowRootBinding(
            rootToken: rootToken,
            rootKind: rootKind,
            rootURL: rootURL
        )
        guard let filePort = try? IPhoneCanonicalShadowFilePort(binding: binding) else {
            return (IPhoneCanonicalDryRunPorts.makePortSet(), nil)
        }
        let lifecycle = CanonicalShadowRootLifecycle(
            rootID: rootID,
            rootKind: rootKind,
            rootURL: rootURL
        )
        return (CanonicalProductionPortSet(
            file: filePort,
            transport: IPhoneCanonicalShadowTransportPort(),
            upload: CanonicalShadowUploadPort(),
            apply: CanonicalShadowApplyPort()
        ), lifecycle)
    }

    nonisolated private static func snapshot(
        from inventory: LocalNetworkSyncInventory,
        legacyActions: CanonicalLegacyActionSnapshot,
        action: String,
        generatedAt: Date
    ) -> CanonicalProductionSnapshot? {
        guard let manifest = inventory.canonicalManifest else {
            return nil
        }
        let coverage = coverageReport(for: manifest)
        let transferProjection = CanonicalTransferProjection()
        let objectProjection = CanonicalObjectProjectionBuilder.build(
            manifest: manifest,
            transferProjection: transferProjection,
            builtAt: generatedAt
        )
        let retirement = CanonicalRetirementReadinessEvaluator().evaluate(
            manifest: manifest,
            libraryPlan: nil,
            applyPlan: nil,
            transferProjection: transferProjection,
            inventoryCoverage: coverage,
            fallbackUsed: false,
            generatedAt: generatedAt
        )
        let diagnostics = [
            CanonicalProductionDiagnosticsEvent(
                kind: .canonicalProductionSnapshotBuilt,
                domain: .inventory,
                action: action,
                reason: "alreadyLoadedInventoryFactsOnly",
                hash: manifest.manifestHash,
                generatedAt: generatedAt
            )
        ]
        let runtimeState = CanonicalRuntimeNodeState(
            node: manifest.node,
            manifest: manifest,
            transferProjection: transferProjection,
            inventoryCoverage: coverage,
            retirementReadiness: retirement,
            objectProjection: objectProjection,
            diagnostics: diagnostics
        )
        return CanonicalProductionSnapshot(
            node: manifest.node,
            manifest: manifest,
            runtimeNodeState: runtimeState,
            legacyActions: legacyActions,
            diagnostics: diagnostics
        )
    }

    nonisolated private static func coverageReport(for manifest: CanonicalManifest) -> CanonicalInventoryCoverageReport {
        let generatedArtifactCoverage = manifest.objects.reduce(0) { count, object in
            count + object.artifacts.filter { CanonicalProjectionContract.generatedArtifactKinds.contains($0.kind) }.count
        }
        return CanonicalInventoryCoverageReport(
            recordingCoverage: manifest.objects.count,
            audioCoverage: manifest.objects.filter(\.audioAvailable).count,
            generatedArtifactCoverage: generatedArtifactCoverage,
            folderCoverage: manifest.folders.count,
            studyItemCoverage: manifest.studyItems.count,
            tombstoneCoverage: manifest.libraryTombstones.count,
            unsupportedLegacyObjectCount: manifest.libraryObjects.filter { $0.kind == .unknownUnsupported }.count,
            fallbackRequiredCount: 0
        )
    }

    nonisolated private static func legacyActionSnapshot(from plan: LocalNetworkSyncDiffPlan?) -> CanonicalLegacyActionSnapshot {
        guard let plan else {
            return .empty
        }
        let metadataIDs = plan.uploadMetadataActions
            .filter { $0.entityKind == "recording" }
            .map { "recordingMetadataSend:\($0.entityID)" }
            + plan.downloadMetadataActions
            .filter { $0.entityKind == "recording" }
            .map { "recordingMetadataApply:\($0.entityID)" }
        let nonRecordingMetadataIDs = (plan.uploadMetadataActions + plan.downloadMetadataActions)
            .filter { $0.entityKind != "recording" }
            .map(\.id)
        let artifactIDs = (plan.uploadArtifactActions + plan.downloadArtifactActions).map(\.id)
        let audioIDs = plan.uploadRecordingAudioActions.map(\.id)
        let conflictIDs = plan.conflictActions.map(\.id)
        let applyIDs = metadataIDs + nonRecordingMetadataIDs + artifactIDs + conflictIDs
        return CanonicalLegacyActionSnapshot(actionIDsByDomain: [
            .recordingMetadata: metadataIDs,
            .generatedArtifacts: artifactIDs,
            .recordingAudio: audioIDs,
            .conflicts: conflictIDs,
            .apply: applyIDs
        ])
    }

    nonisolated private static func diagnosticsSummary(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory?,
        legacyPlan: LocalNetworkSyncDiffPlan?,
        mode: CanonicalShadowMigrationMode,
        portReadiness: CanonicalProductionPortReadiness
    ) -> String {
        let legacyActionCount = (legacyPlan?.uploadMetadataActions.count ?? 0)
            + (legacyPlan?.uploadArtifactActions.count ?? 0)
            + (legacyPlan?.downloadMetadataActions.count ?? 0)
            + (legacyPlan?.downloadArtifactActions.count ?? 0)
            + (legacyPlan?.uploadRecordingAudioActions.count ?? 0)
            + (legacyPlan?.conflictActions.count ?? 0)
        return [
            "role=iPhone",
            "mode=\(mode.rawValue)",
            "localManifest=\(localInventory.canonicalManifest == nil ? "missing" : "present")",
            "peerManifest=\(peerInventory?.canonicalManifest == nil ? "missing" : "present")",
            "localRecordings=\(localInventory.recordings.count)",
            "peerRecordings=\(peerInventory?.recordings.count ?? 0)",
            "legacyActions=\(legacyActionCount)",
            "missingPorts=\(portReadiness.missingPorts.count)",
            "dryRunOnly=\(portReadiness.dryRunOnly)"
        ].joined(separator: ",")
    }
}
