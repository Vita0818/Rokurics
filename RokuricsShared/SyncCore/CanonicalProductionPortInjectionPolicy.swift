//
//  CanonicalProductionPortInjectionPolicy.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/12.
//

import Foundation

nonisolated struct CanonicalProductionPortInjectionDecision: Equatable, Sendable {
    var mode: CanonicalKernelSwitchMode
    var rootSafetyPassed: Bool
    var injectNonAudioApplyExecutors: Bool
    var allowProductionRootWrites: Bool
    var injectExistenceApplyPort: Bool
    var injectAudioUploadExecutor: Bool
    var blockerCode: String?

    nonisolated static func disabled(
        mode: CanonicalKernelSwitchMode,
        rootSafetyPassed: Bool,
        blockerCode: String? = nil
    ) -> CanonicalProductionPortInjectionDecision {
        CanonicalProductionPortInjectionDecision(
            mode: mode,
            rootSafetyPassed: rootSafetyPassed,
            injectNonAudioApplyExecutors: false,
            allowProductionRootWrites: false,
            injectExistenceApplyPort: false,
            injectAudioUploadExecutor: false,
            blockerCode: blockerCode
        )
    }
}

nonisolated enum CanonicalProductionPortInjectionPolicy {
    nonisolated static func decide(
        effectiveConfiguration: CanonicalKernelSwitchEffectiveConfiguration,
        productionRootURL: URL,
        fileManager: FileManager = .default
    ) -> CanonicalProductionPortInjectionDecision {
        let mode = effectiveConfiguration.migrationMatrixPolicy.mode
        let rootSafetyPassed = productionRootSafetyPassed(
            productionRootURL,
            fileManager: fileManager
        )

        switch mode {
        case .oldKernel, .diagnosticsOnly, .canonicalShadow, .canonicalDecisionOnly, .blocked:
            return .disabled(
                mode: mode,
                rootSafetyPassed: rootSafetyPassed,
                blockerCode: mode == .blocked ? "canonical_kernel_switch_blocked" : nil
            )
        case .canonicalApplyNoAudio, .canonicalFullSync:
            break
        }

        guard rootSafetyPassed else {
            return .disabled(
                mode: mode,
                rootSafetyPassed: false,
                blockerCode: "productionRootSafetyBlocked"
            )
        }

        let apply = effectiveConfiguration.applyRuntimeConfiguration
        let existence = effectiveConfiguration.existenceApplyRuntimeConfiguration
        let audio = effectiveConfiguration.audioUploadRuntimeConfiguration
        let read = effectiveConfiguration.readRuntimeConfiguration

        let applyGateAllowsNonAudio = apply.mode == .productionRootApplyWithLegacyFallback
            && apply.policy.debugInternalBuild
            && apply.policy.ownerApproved
            && !apply.policy.releaseDefaultBuild
            && apply.policy.legacyFallbackAvailable
            && apply.policy.diagnosticsRedacted
            && !apply.policy.runtimeSwitchEnabled
            && apply.policy.readPathLegacy

        let injectNonAudioApplyExecutors = applyGateAllowsNonAudio
        let injectExistenceApplyPort = existence.canWriteMetadataOnlyRecord
            && (mode == .canonicalApplyNoAudio || mode == .canonicalFullSync)

        let fullSyncProductionRootWriteAllowed = mode == .canonicalFullSync
            && applyGateAllowsNonAudio
            && existence.mode == .productionRootApply
            && existence.canWriteMetadataOnlyRecord
            && audio.mode == .canonicalUploadWithLegacyFallback
            && audio.policy.debugInternalBuild
            && audio.policy.ownerApprovedCanonicalCommit
            && audio.policy.allowCanonicalUploadWithLegacyFallback
            && audio.policy.legacyFallbackEnabled
            && audio.policy.requireExistingSecureUploadRoutes
            && read.mode == .guardedCanonicalReadWithLegacyFallback
            && read.policy.debugInternalBuild
            && read.policy.ownerApproved
            && read.policy.manualOwnerApproval
            && !read.policy.releaseDefaultBuild
            && read.policy.legacyFallbackAvailable
            && read.policy.diagnosticsRedacted
            && read.policy.readMustNotTriggerSyncUpload
            && read.policy.readMustNotMutateStore

        return CanonicalProductionPortInjectionDecision(
            mode: mode,
            rootSafetyPassed: rootSafetyPassed,
            injectNonAudioApplyExecutors: injectNonAudioApplyExecutors,
            allowProductionRootWrites: fullSyncProductionRootWriteAllowed,
            injectExistenceApplyPort: injectExistenceApplyPort,
            injectAudioUploadExecutor: fullSyncProductionRootWriteAllowed,
            blockerCode: fullSyncProductionRootWriteAllowed || mode == .canonicalApplyNoAudio
                ? nil
                : "productionRootWriteGateBlocked"
        )
    }

    nonisolated static func productionRootSafetyPassed(
        _ rootURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard rootURL.isFileURL else {
            return false
        }

        let rootPath = rootURL.standardizedFileURL.path
        guard !rootPath.isEmpty, rootPath != "/" else {
            return false
        }

        let homePath = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        if rootPath == homePath {
            return false
        }

        let tempPath = fileManager.temporaryDirectory.standardizedFileURL.path
        if rootPath == tempPath || rootPath.hasPrefix(tempPath + "/") {
            return false
        }

        if let repositoryRootPath = repositoryRootPath(
            containing: URL(fileURLWithPath: fileManager.currentDirectoryPath),
            fileManager: fileManager
        ), rootPath == repositoryRootPath || rootPath.hasPrefix(repositoryRootPath + "/") {
            return false
        }

        return true
    }

    private nonisolated static func repositoryRootPath(
        containing directoryURL: URL,
        fileManager: FileManager
    ) -> String? {
        var cursor = directoryURL.standardizedFileURL
        while cursor.path != "/" {
            let gitURL = cursor.appendingPathComponent(".git", isDirectory: true)
            let projectURL = cursor.appendingPathComponent("Rokurics.xcodeproj", isDirectory: true)
            if fileManager.fileExists(atPath: gitURL.path)
                || fileManager.fileExists(atPath: projectURL.path) {
                return cursor.path
            }
            let parent = cursor.deletingLastPathComponent().standardizedFileURL
            guard parent.path != cursor.path else {
                break
            }
            cursor = parent
        }
        return nil
    }
}
