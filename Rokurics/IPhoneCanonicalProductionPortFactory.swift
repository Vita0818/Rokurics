//
//  IPhoneCanonicalProductionPortFactory.swift
//  Rokurics
//
//  Created by Codex on 2026/6/12.
//

import Foundation

struct IPhoneCanonicalProductionPortFactoryOutput {
    var decision: CanonicalProductionPortInjectionDecision
    var libraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration
    var recordingMetadataCutoverExecutor: (any CanonicalRecordingMetadataCutoverExecutor)?
    var libraryMetadataCutoverExecutor: (any CanonicalLibraryMetadataCutoverExecutor)?
    var generatedArtifactCutoverExecutor: (any CanonicalGeneratedArtifactCutoverExecutor)?
    var tombstoneConflictCutoverExecutor: (any CanonicalTombstoneConflictCutoverExecutor)?
    var audioUploadExecutorEnabled: Bool
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

enum IPhoneCanonicalProductionPortFactory {
    static func make(
        result: CanonicalKernelSwitchResult,
        productionRootURL: URL,
        fileManager: FileManager = .default
    ) -> IPhoneCanonicalProductionPortFactoryOutput {
        make(
            effectiveConfiguration: result.effectiveConfiguration,
            productionRootURL: productionRootURL,
            fileManager: fileManager,
            blockedBySwitch: result.isBlocked
        )
    }

    static func make(
        effectiveConfiguration: CanonicalKernelSwitchEffectiveConfiguration,
        productionRootURL: URL,
        fileManager: FileManager = .default,
        blockedBySwitch: Bool = false
    ) -> IPhoneCanonicalProductionPortFactoryOutput {
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

        guard decision.injectNonAudioApplyExecutors else {
            return IPhoneCanonicalProductionPortFactoryOutput(
                decision: decision,
                libraryMetadataDebugPilotConfiguration: libraryPilotConfiguration,
                recordingMetadataCutoverExecutor: nil,
                libraryMetadataCutoverExecutor: libraryPilotExecutor,
                generatedArtifactCutoverExecutor: nil,
                tombstoneConflictCutoverExecutor: nil,
                audioUploadExecutorEnabled: false,
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

            return IPhoneCanonicalProductionPortFactoryOutput(
                decision: decision,
                libraryMetadataDebugPilotConfiguration: libraryPilotConfiguration,
                recordingMetadataCutoverExecutor: IPhoneRecordingMetadataCutoverExecutor(applyPort: recordingApplyPort),
                libraryMetadataCutoverExecutor: IPhoneLibraryMetadataCutoverExecutor(applyPort: libraryApplyPort),
                generatedArtifactCutoverExecutor: IPhoneGeneratedArtifactCutoverExecutor(applyPort: generatedArtifactApplyPort),
                tombstoneConflictCutoverExecutor: IPhoneTombstoneConflictCutoverExecutor(applyPort: tombstoneConflictApplyPort),
                audioUploadExecutorEnabled: decision.injectAudioUploadExecutor,
                diagnosticsSummary: diagnosticsSummary(decision: decision)
            )
        } catch {
            let blockedDecision = CanonicalProductionPortInjectionDecision.disabled(
                mode: decision.mode,
                rootSafetyPassed: decision.rootSafetyPassed,
                blockerCode: "productionRootPortConstructionFailed"
            )
            return IPhoneCanonicalProductionPortFactoryOutput(
                decision: blockedDecision,
                libraryMetadataDebugPilotConfiguration: libraryPilotConfiguration,
                recordingMetadataCutoverExecutor: nil,
                libraryMetadataCutoverExecutor: libraryPilotExecutor,
                generatedArtifactCutoverExecutor: nil,
                tombstoneConflictCutoverExecutor: nil,
                audioUploadExecutorEnabled: false,
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
            return IPhoneRecordingMetadataRealApplyPort()
        }
        return try IPhoneRecordingMetadataRealApplyPort(
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
            return IPhoneLibraryMetadataRealApplyPort()
        }
        return try IPhoneLibraryMetadataRealApplyPort(
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
            return IPhoneGeneratedArtifactRealApplyPort()
        }
        return try IPhoneGeneratedArtifactRealApplyPort(
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
            return IPhoneTombstoneConflictRealApplyPort()
        }
        return try IPhoneTombstoneConflictRealApplyPort(
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
        let runtime = CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotRuntime(
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
            "audioUpload=\(decision.injectAudioUploadExecutor ? "injected" : "disabled")",
            decision.blockerCode.map { "blocker=\($0)" }
        ].compactMap { $0 }.joined(separator: ";")
    }
}
