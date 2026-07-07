//
//  MacCanonicalProductionPortFactory.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/12.
//

import Foundation

struct MacCanonicalProductionPortFactoryOutput {
    var decision: CanonicalProductionPortInjectionDecision
    var libraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration
    var recordingMetadataCutoverExecutor: (any CanonicalRecordingMetadataCutoverExecutor)?
    var libraryMetadataCutoverExecutor: (any CanonicalLibraryMetadataCutoverExecutor)?
    var generatedArtifactCutoverExecutor: (any CanonicalGeneratedArtifactCutoverExecutor)?
    var tombstoneConflictCutoverExecutor: (any CanonicalTombstoneConflictCutoverExecutor)?
    var recordingExistenceApplyPort: (any MacCanonicalRecordingExistenceApplyPort)?
    var audioUploadCutoverExecutor: MacAudioUploadCutoverExecutor?
    var diagnosticsSummary: String

    var allowProductionRootWrites: Bool {
        decision.allowProductionRootWrites
    }

    var hasNonAudioApplyExecutors: Bool {
        recordingMetadataCutoverExecutor != nil
            && libraryMetadataCutoverExecutor != nil
            && generatedArtifactCutoverExecutor != nil
            && tombstoneConflictCutoverExecutor != nil
    }
}

@MainActor
enum MacCanonicalProductionPortFactory {
    static func make(
        result: CanonicalKernelSwitchResult,
        productionRootURL: URL,
        recordingFileStore: MacRecordingFileStore,
        fileManager: FileManager = .default
    ) -> MacCanonicalProductionPortFactoryOutput {
        make(
            effectiveConfiguration: result.effectiveConfiguration,
            productionRootURL: productionRootURL,
            recordingFileStore: recordingFileStore,
            fileManager: fileManager,
            blockedBySwitch: result.isBlocked
        )
    }

    static func make(
        effectiveConfiguration: CanonicalKernelSwitchEffectiveConfiguration,
        productionRootURL: URL,
        recordingFileStore: MacRecordingFileStore,
        fileManager: FileManager = .default,
        blockedBySwitch: Bool = false
    ) -> MacCanonicalProductionPortFactoryOutput {
        let baseDecision = CanonicalProductionPortInjectionPolicy.decide(
            effectiveConfiguration: effectiveConfiguration,
            productionRootURL: productionRootURL,
            fileManager: fileManager
        )
        let decision = blockedBySwitch
            ? .disabled(
                mode: effectiveConfiguration.migrationMatrixPolicy.mode,
                rootSafetyPassed: baseDecision.rootSafetyPassed,
                blockerCode: "canonical_kernel_switch_blocked"
            )
            : baseDecision

        let libraryPilotConfiguration = effectiveConfiguration.libraryMetadataDebugPilotConfiguration
        let libraryPilotExecutor = makeLibraryMetadataDebugPilotExecutor(
            configuration: libraryPilotConfiguration,
            productionRootURL: decision.allowProductionRootWrites ? productionRootURL : nil,
            fileManager: fileManager
        )
        let existencePort = decision.injectExistenceApplyPort
            ? MacCanonicalRecordingExistenceLedgerPort(fileManager: fileManager, rootURL: productionRootURL)
            : nil
        let audioExecutor = decision.injectAudioUploadExecutor
            ? MacAudioUploadCutoverExecutor(recordingFileStore: recordingFileStore)
            : nil

        guard decision.injectNonAudioApplyExecutors else {
            return MacCanonicalProductionPortFactoryOutput(
                decision: decision,
                libraryMetadataDebugPilotConfiguration: libraryPilotConfiguration,
                recordingMetadataCutoverExecutor: nil,
                libraryMetadataCutoverExecutor: libraryPilotExecutor,
                generatedArtifactCutoverExecutor: nil,
                tombstoneConflictCutoverExecutor: nil,
                recordingExistenceApplyPort: existencePort,
                audioUploadCutoverExecutor: audioExecutor,
                diagnosticsSummary: diagnosticsSummary(decision: decision)
            )
        }

        do {
            let recordingApplyPort = try makeRecordingApplyPort(
                productionRootURL: productionRootURL,
                allowProductionRootWrites: decision.allowProductionRootWrites,
                fileManager: fileManager
            )
            let libraryApplyPort = try makeLibraryApplyPort(
                productionRootURL: productionRootURL,
                allowProductionRootWrites: decision.allowProductionRootWrites,
                fileManager: fileManager
            )
            let generatedArtifactApplyPort = try makeGeneratedArtifactApplyPort(
                productionRootURL: productionRootURL,
                allowProductionRootWrites: decision.allowProductionRootWrites,
                fileManager: fileManager
            )
            let tombstoneConflictApplyPort = try makeTombstoneConflictApplyPort(
                productionRootURL: productionRootURL,
                allowProductionRootWrites: decision.allowProductionRootWrites,
                fileManager: fileManager
            )

            return MacCanonicalProductionPortFactoryOutput(
                decision: decision,
                libraryMetadataDebugPilotConfiguration: libraryPilotConfiguration,
                recordingMetadataCutoverExecutor: MacRecordingMetadataCutoverExecutor(applyPort: recordingApplyPort),
                libraryMetadataCutoverExecutor: MacLibraryMetadataCutoverExecutor(applyPort: libraryApplyPort),
                generatedArtifactCutoverExecutor: MacGeneratedArtifactCutoverExecutor(applyPort: generatedArtifactApplyPort),
                tombstoneConflictCutoverExecutor: MacTombstoneConflictCutoverExecutor(applyPort: tombstoneConflictApplyPort),
                recordingExistenceApplyPort: existencePort,
                audioUploadCutoverExecutor: audioExecutor,
                diagnosticsSummary: diagnosticsSummary(decision: decision)
            )
        } catch {
            let blockedDecision = CanonicalProductionPortInjectionDecision.disabled(
                mode: decision.mode,
                rootSafetyPassed: decision.rootSafetyPassed,
                blockerCode: "productionRootPortConstructionFailed"
            )
            return MacCanonicalProductionPortFactoryOutput(
                decision: blockedDecision,
                libraryMetadataDebugPilotConfiguration: libraryPilotConfiguration,
                recordingMetadataCutoverExecutor: nil,
                libraryMetadataCutoverExecutor: libraryPilotExecutor,
                generatedArtifactCutoverExecutor: nil,
                tombstoneConflictCutoverExecutor: nil,
                recordingExistenceApplyPort: nil,
                audioUploadCutoverExecutor: nil,
                diagnosticsSummary: diagnosticsSummary(decision: blockedDecision)
            )
        }
    }

    private static func makeRecordingApplyPort(
        productionRootURL: URL,
        allowProductionRootWrites: Bool,
        fileManager: FileManager
    ) throws -> any CanonicalProductionApplyPort {
        guard allowProductionRootWrites else {
            return MacRecordingMetadataRealApplyPort()
        }
        return try MacRecordingMetadataRealApplyPort(
            productionRootURL: productionRootURL,
            allowProductionRootWrites: true,
            fileManager: fileManager
        )
    }

    private static func makeLibraryApplyPort(
        productionRootURL: URL,
        allowProductionRootWrites: Bool,
        fileManager: FileManager
    ) throws -> any CanonicalProductionApplyPort {
        guard allowProductionRootWrites else {
            return MacLibraryMetadataRealApplyPort()
        }
        return try MacLibraryMetadataRealApplyPort(
            productionRootURL: productionRootURL,
            allowProductionRootWrites: true,
            fileManager: fileManager
        )
    }

    private static func makeGeneratedArtifactApplyPort(
        productionRootURL: URL,
        allowProductionRootWrites: Bool,
        fileManager: FileManager
    ) throws -> any CanonicalProductionApplyPort {
        guard allowProductionRootWrites else {
            return MacGeneratedArtifactRealApplyPort()
        }
        return try MacGeneratedArtifactRealApplyPort(
            productionRootURL: productionRootURL,
            allowProductionRootWrites: true,
            fileManager: fileManager
        )
    }

    private static func makeTombstoneConflictApplyPort(
        productionRootURL: URL,
        allowProductionRootWrites: Bool,
        fileManager: FileManager
    ) throws -> any CanonicalProductionApplyPort {
        guard allowProductionRootWrites else {
            return MacTombstoneConflictRealApplyPort()
        }
        return try MacTombstoneConflictRealApplyPort(
            productionRootURL: productionRootURL,
            allowProductionRootWrites: true,
            fileManager: fileManager
        )
    }

    private static func makeLibraryMetadataDebugPilotExecutor(
        configuration: CanonicalLibraryMetadataDebugPilotConfiguration,
        productionRootURL: URL?,
        fileManager: FileManager
    ) -> (any CanonicalLibraryMetadataCutoverExecutor)? {
        guard configuration.mode.isConfigured else {
            return nil
        }
        let runtime = CanonicalLibraryMetadataDebugPilotConfiguration.macRealDeviceDebugPilotRuntime(
            productionRootURL: productionRootURL,
            fileManager: fileManager
        )
        guard runtime.configuration.mode == configuration.mode else {
            return nil
        }
        return runtime.executor
    }

    private static func diagnosticsSummary(
        decision: CanonicalProductionPortInjectionDecision
    ) -> String {
        [
            "mode=\(decision.mode.rawValue)",
            "rootSafety=\(decision.rootSafetyPassed ? "passed" : "blocked")",
            "nonAudioApply=\(decision.injectNonAudioApplyExecutors ? "injected" : "disabled")",
            "productionRootWrite=\(decision.allowProductionRootWrites ? "allowed" : "blocked")",
            "existence=\(decision.injectExistenceApplyPort ? "injected" : "disabled")",
            "audioUpload=\(decision.injectAudioUploadExecutor ? "injected" : "disabled")",
            decision.blockerCode.map { "blocker=\($0)" }
        ].compactMap { $0 }.joined(separator: ";")
    }
}
