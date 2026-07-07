//
//  IPhoneLibraryMetadataProductionCanaryBootstrap.swift
//  Rokurics
//
//  Created by Codex on 2026/6/5.
//

import Foundation

struct IPhoneLibraryMetadataProductionCanaryBootstrapResult {
    var configuration: CanonicalLibraryMetadataProductionCanaryConfiguration
    var applyPort: IPhoneLibraryMetadataRealApplyPort?
    var executor: (any CanonicalLibraryMetadataCutoverExecutor)?
    var evidence: CanonicalLibraryMetadataCutoverEvidence
    var blockers: [CanonicalLibraryMetadataRealCanaryBlocker]

    var executorInjected: Bool {
        executor != nil
    }

    var applyPortInjected: Bool {
        applyPort != nil && evidence.realRootBoundApplyPortAvailable
    }
}

struct IPhoneLibraryMetadataProductionCanaryBootstrap {
    var configuration: CanonicalLibraryMetadataProductionCanaryConfiguration
    var fileManager: FileManager
    var failureInjection: CanonicalLibraryMetadataCommitFailureInjection

    init(
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration = .disabled,
        fileManager: FileManager = .default,
        failureInjection: CanonicalLibraryMetadataCommitFailureInjection = .none
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        self.failureInjection = failureInjection
    }

    func prepare(
        testRootURL: URL? = nil,
        productionRootURL: URL? = nil,
        evidence baseEvidence: CanonicalLibraryMetadataCutoverEvidence = CanonicalLibraryMetadataCutoverEvidence()
    ) throws -> IPhoneLibraryMetadataProductionCanaryBootstrapResult {
        guard configuration.mode != .disabled else {
            return IPhoneLibraryMetadataProductionCanaryBootstrapResult(
                configuration: configuration,
                applyPort: nil,
                executor: nil,
                evidence: baseEvidence,
                blockers: [.disabled]
            )
        }

        var evidence = baseEvidence
        let applyPort: IPhoneLibraryMetadataRealApplyPort?
        var blockers: [CanonicalLibraryMetadataRealCanaryBlocker] = []
        switch configuration.rootMode {
        case .disabled:
            applyPort = nil
            blockers.append(.productionRootNotExplicit)
        case .testRoot:
            guard let testRootURL else {
                applyPort = nil
                blockers.append(.testRootMissing)
                break
            }
            let port = try IPhoneLibraryMetadataRealApplyPort(
                testRootURL: testRootURL,
                fileManager: fileManager,
                failureInjection: failureInjection
            )
            applyPort = port
            evidence = Self.rootBoundEvidence(from: evidence, mode: port.applyPortMode, testRootUsed: true)
        case .productionRootExplicit:
            guard configuration.allowProductionRootWrites else {
                applyPort = nil
                blockers.append(.productionRootWritesDisabled)
                break
            }
            guard let productionRootURL else {
                applyPort = nil
                blockers.append(.productionRootGuardMissing)
                break
            }
            let port = try IPhoneLibraryMetadataRealApplyPort(
                productionRootURL: productionRootURL,
                allowProductionRootWrites: true,
                fileManager: fileManager,
                failureInjection: failureInjection
            )
            applyPort = port
            evidence = Self.rootBoundEvidence(from: evidence, mode: port.applyPortMode, testRootUsed: evidence.testRootUsed)
        }

        let executor = applyPort.map {
            IPhoneLibraryMetadataCutoverExecutor(applyPort: $0, failureInjection: failureInjection)
        }
        return IPhoneLibraryMetadataProductionCanaryBootstrapResult(
            configuration: configuration,
            applyPort: applyPort,
            executor: executor,
            evidence: evidence,
            blockers: Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        )
    }

    private static func rootBoundEvidence(
        from base: CanonicalLibraryMetadataCutoverEvidence,
        mode: CanonicalLibraryMetadataApplyPortMode,
        testRootUsed: Bool
    ) -> CanonicalLibraryMetadataCutoverEvidence {
        var evidence = base
        evidence.productionPortAvailable = true
        evidence.realRootBoundApplyPortAvailable = mode.isNonDryRunRootBound
        evidence.applyPortMode = mode
        evidence.rootBoundWriteAvailable = mode.isNonDryRunRootBound
        evidence.atomicReplaceAvailable = mode.isNonDryRunRootBound
        evidence.rollbackCheckpointAvailable = mode.isNonDryRunRootBound
        evidence.productionRootDisabledByDefault = true
        evidence.testRootUsed = testRootUsed
        return evidence
    }
}
