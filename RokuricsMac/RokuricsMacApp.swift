//
//  RokuricsMacApp.swift
//  RokuricsMac
//
//  Created by Vita on 2026/5/10.
//

import SwiftUI

@main
struct RokuricsMacApp: App {
    @StateObject private var secureReceiverService = Self.makeSecureReceiverService()

    var body: some Scene {
        WindowGroup {
            ContentView(secureReceiverService: secureReceiverService)
        }
    }

    @MainActor
    static func makeSecureReceiverService() -> SecureReceiverService {
        let recordingFileStore = MacRecordingFileStore()
        let kernelSwitchResultProvider: () -> CanonicalKernelSwitchResult = {
            CanonicalKernelSwitchConfiguration.runtimeConfigurationFromStoredDefaults().resolve()
        }
        let kernelSwitchResult = kernelSwitchResultProvider()
        let productionPortInjection = MacCanonicalProductionPortFactory.make(
            result: kernelSwitchResult,
            productionRootURL: recordingFileStore.libraryRootURL,
            recordingFileStore: recordingFileStore
        )

        if let uiTestHost = MacAppStorageProfile.uiTestPreferredHost {
            return SecureReceiverService(
                port: MacAppStorageProfile.receiverPort,
                recordingFileStore: recordingFileStore,
                canonicalLibraryMetadataDebugPilotConfiguration: productionPortInjection.libraryMetadataDebugPilotConfiguration,
                canonicalRecordingMetadataCutoverExecutor: productionPortInjection.recordingMetadataCutoverExecutor,
                canonicalGeneratedArtifactCutoverExecutor: productionPortInjection.generatedArtifactCutoverExecutor,
                canonicalLibraryMetadataCutoverExecutor: productionPortInjection.libraryMetadataCutoverExecutor,
                canonicalTombstoneConflictCutoverExecutor: productionPortInjection.tombstoneConflictCutoverExecutor,
                canonicalSyncRuntimeConfiguration: kernelSwitchResult.effectiveConfiguration.syncRuntimeConfiguration,
                canonicalApplyRuntimeConfiguration: kernelSwitchResult.effectiveConfiguration.applyRuntimeConfiguration,
                canonicalExistenceApplyRuntimeConfiguration: kernelSwitchResult.effectiveConfiguration.existenceApplyRuntimeConfiguration,
                canonicalReadRuntimeConfiguration: kernelSwitchResult.effectiveConfiguration.readRuntimeConfiguration,
                canonicalRecordingExistenceApplyPort: productionPortInjection.recordingExistenceApplyPort,
                canonicalAudioUploadCutoverExecutor: productionPortInjection.audioUploadCutoverExecutor,
                canonicalKernelSwitchResultProvider: kernelSwitchResultProvider,
                preferredIPAddressProvider: { uiTestHost }
            )
        }

        return SecureReceiverService(
            port: MacAppStorageProfile.receiverPort,
            recordingFileStore: recordingFileStore,
            canonicalLibraryMetadataDebugPilotConfiguration: productionPortInjection.libraryMetadataDebugPilotConfiguration,
            canonicalRecordingMetadataCutoverExecutor: productionPortInjection.recordingMetadataCutoverExecutor,
            canonicalGeneratedArtifactCutoverExecutor: productionPortInjection.generatedArtifactCutoverExecutor,
            canonicalLibraryMetadataCutoverExecutor: productionPortInjection.libraryMetadataCutoverExecutor,
            canonicalTombstoneConflictCutoverExecutor: productionPortInjection.tombstoneConflictCutoverExecutor,
            canonicalSyncRuntimeConfiguration: kernelSwitchResult.effectiveConfiguration.syncRuntimeConfiguration,
            canonicalApplyRuntimeConfiguration: kernelSwitchResult.effectiveConfiguration.applyRuntimeConfiguration,
            canonicalExistenceApplyRuntimeConfiguration: kernelSwitchResult.effectiveConfiguration.existenceApplyRuntimeConfiguration,
            canonicalReadRuntimeConfiguration: kernelSwitchResult.effectiveConfiguration.readRuntimeConfiguration,
            canonicalRecordingExistenceApplyPort: productionPortInjection.recordingExistenceApplyPort,
            canonicalAudioUploadCutoverExecutor: productionPortInjection.audioUploadCutoverExecutor,
            canonicalKernelSwitchResultProvider: kernelSwitchResultProvider
        )
    }
}
