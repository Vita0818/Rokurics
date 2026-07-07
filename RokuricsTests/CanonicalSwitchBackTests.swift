//
//  CanonicalSwitchBackTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import Testing
@testable import Rokurics

@Suite(.serialized)
struct CanonicalSwitchBackTests {
    @Test func rootSafetyRejectsProductionLikeRootsAndAcceptsTempClone() throws {
        let fileManager = FileManager()
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CanonicalSwitchBackTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let accepted = CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: tempRoot)
        #expect(accepted.accepted)
        #expect(accepted.testClonedRoot)
        #expect(accepted.diagnosticsSummary.contains("/Users/") == false)

        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #expect(CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: home).accepted == false)
        #expect(CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: URL(fileURLWithPath: "/", isDirectory: true)).accepted == false)

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        #expect(CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: repoRoot).accepted == false)

        let appSupport = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Rokurics", isDirectory: true)
        #expect(CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: appSupport).accepted == false)

        let documentsRoot = home
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Rokurics", isDirectory: true)
        #expect(CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: documentsRoot).accepted == false)
        #expect(CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: documentsRoot.appendingPathComponent("Recordings", isDirectory: true)).accepted == false)

        let desktopRoot = home
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("Rokurics", isDirectory: true)
        #expect(CanonicalSwitchBackRootSafetyGuard.evaluate(rootURL: desktopRoot).accepted == false)
    }

    @Test func realisticFixtureAndCloneContainRequiredComponents() throws {
        let fileManager = FileManager()
        let sourceRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CanonicalRealisticSource-\(UUID().uuidString)", isDirectory: true)
        let cloneRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CanonicalRealisticClone-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: sourceRoot)
            try? fileManager.removeItem(at: cloneRoot)
        }

        let fixture = try CanonicalRealisticLibraryRootFixture().write(to: sourceRoot)
        #expect(fixture.isComplete)
        #expect(Set(fixture.components) == Set(CanonicalRealisticLibraryRootFixtureComponent.allCases))
        #expect(fixture.diagnosticsSummary.contains("/Users/") == false)

        let clone = try CanonicalRealisticAppDataRootClone().createClone(
            sourceRootURL: sourceRoot,
            destinationRootURL: cloneRoot
        )
        #expect(clone.cloned)
        #expect(clone.destinationSafety.accepted)
        #expect(clone.fixtureResult.isComplete)
        #expect(clone.diagnosticsSummary.contains("/Users/") == false)
    }

    @Test func domainSwitchBackMatrixCoversAllFiveBusinessDomains() {
        let matrix = CanonicalDomainSwitchBackMatrix.prove()

        #expect(matrix.isProven)
        #expect(Set(matrix.results.map(\.domain)) == Set(CanonicalDomainSwitchBackMatrix.v857Domains))
        #expect(matrix.results.count == 5)
        #expect(matrix.blockers.isEmpty)

        for result in matrix.results {
            #expect(result.legacyWriteCanonicalRead)
            #expect(result.canonicalWriteLegacyRead)
            #expect(result.canonicalWriteOldKernelRead)
            #expect(result.oldKernelWriteCanonicalFullSyncRead)
            #expect(result.noDataMigrationNeeded)
            #expect(result.noCanonicalOnlyRequiredField)
            #expect(result.noLegacyIncompatibleDiskFormat)
            #expect(result.legacyFallbackAvailable)
            #expect(result.diagnosticsRedacted)
            #expect(result.domainSpecificProofs.values.allSatisfy { $0 })
        }
    }

    @Test func kernelSwitchBackProofCoversOldNewOldNewSequenceAndEvidence() throws {
        let fileManager = FileManager()
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CanonicalKernelSwitchBackProof-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let proof = try CanonicalSwitchBackRealisticRootHarness(rootURL: root).runKernelSwitchBackProof()
        let evidence = CanonicalSwitchBackEvidenceExporter().export(
            proof: proof,
            rawDiagnostics: [
                "canonicalSwitchBack root=/Users/example/full/path hash=0123456789abcdef0123456789abcdef",
                "canonicalCrashRecovery state=partial redacted=true"
            ]
        )

        #expect(proof.isProven)
        #expect(proof.sequenceProof.steps.map(\.phase) == CanonicalKernelSwitchSequencePhase.allCases)
        #expect(proof.sequenceProof.isProven)
        #expect(proof.domainMatrix.isProven)
        #expect(proof.realDeviceEvidencePresent == false)
        #expect(evidence.switchBackStatus == .passed)
        #expect(evidence.realisticRootProofStatus == .passed)
        #expect(evidence.realDeviceProofStatus == .needsRealDeviceEvidence)
        #expect(evidence.diagnosticsRedactionStatus == .passed)
        #expect(evidence.redactedDiagnostics.joined(separator: "\n").contains("/Users/") == false)
        #expect(evidence.redactedDiagnostics.joined(separator: "\n").contains("0123456789abcdef0123456789abcdef") == false)
    }

    @Test func v857ScorecardRequiresRealDeviceEvidenceAfterCodeProofPasses() throws {
        let fileManager = FileManager()
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CanonicalScorecardV857-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let proof = try CanonicalSwitchBackRealisticRootHarness(rootURL: root).runKernelSwitchBackProof()
        let scorecard = CanonicalSyncKernelCompletionScorecard.v857(
            realisticRootSwitchBackProof: proof
        )

        #expect(scorecard.codeComplete)
        #expect(scorecard.status == .codeCompleteNeedsDeviceEvidence)
        #expect(scorecard.blockers.contains(.realDeviceEvidenceMissing))
        #expect(scorecard.diagnosticsSummary.contains("p3RealisticSwitchBackProofComplete=true"))
        #expect(scorecard.diagnosticsSummary.contains("needsRealDeviceEvidence=true"))
    }

    @Test func debugSwitchBackDriverRejectsProductionCloneRoot() throws {
        let fileManager = FileManager()
        let sourceRoot = try makeDriverSourceRoot(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: sourceRoot) }

        let productionCloneRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("RokuricsLocal", isDirectory: true)
        let result = try CanonicalRealisticRootSwitchBackProofDriver().run(
            appDataRootURL: sourceRoot,
            cloneRootURL: productionCloneRoot,
            fileManager: fileManager,
            realDeviceEvidencePresent: true,
            ownerApprovedForManualGate: true,
            manualBackupAcknowledgedForManualGate: true
        )

        #expect(result.isProofComplete == false)
        #expect(result.cloneRootSafety.accepted == false)
        #expect(result.blockers.contains(.cloneDestinationRejected))
        #expect(result.proofRanOnProductionRoot == false)
        #expect(result.scorecard.status == .blocked)
        #expect(result.scorecard.blockers.contains(.realisticRootSwitchBackProofMissing))
        #expect(result.manualSwitchGateResult.allowedForManualTrial == false)
        #expect(result.manualSwitchGateResult.blockers.contains(.switchBackProofMissing))
    }

    @Test func debugSwitchBackDriverRunsTempCloneRoundtripAndExportsRedactedEvidence() throws {
        let fileManager = FileManager()
        let sourceRoot = try makeDriverSourceRoot(fileManager: fileManager)
        let cloneRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CanonicalSwitchBackDriverClone-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: sourceRoot)
            try? fileManager.removeItem(at: cloneRoot)
        }

        let result = try CanonicalRealisticRootSwitchBackProofDriver().run(
            appDataRootURL: sourceRoot,
            cloneRootURL: cloneRoot,
            fileManager: fileManager,
            ownerApprovedForManualGate: true,
            manualBackupAcknowledgedForManualGate: true
        )

        #expect(result.cloneRootSafety.accepted)
        #expect(result.cloneResult?.cloned == true)
        #expect(result.proof?.isProven == true)
        #expect(result.isProofComplete)
        #expect(result.proofRanOnProductionRoot == false)
        #expect(fileManager.fileExists(atPath: sourceRoot.appendingPathComponent(CanonicalSwitchBackRootSafetyGuard.testCloneMarkerFileName).path) == false)

        let proof = try #require(result.proof)
        #expect(proof.domainMatrix.isProven)
        #expect(Set(proof.domainMatrix.results.map(\.domain)) == Set(CanonicalDomainSwitchBackMatrix.v857Domains))
        #expect(proof.sequenceProof.steps.map(\.phase) == CanonicalKernelSwitchSequencePhase.allCases)
        #expect(proof.sequenceProof.steps.contains { $0.phase == .switchBackOldKernel && $0.mode == .oldKernel })
        #expect(proof.realisticHarnessResult.physicalDeleteCount == 0)
        #expect(proof.realisticHarnessResult.legacyRetirementPerformed == false)

        for domainResult in proof.domainMatrix.results {
            #expect(domainResult.canonicalWriteLegacyRead)
            #expect(domainResult.legacyWriteCanonicalRead)
            #expect(domainResult.canonicalWriteOldKernelRead)
            #expect(domainResult.oldKernelWriteCanonicalFullSyncRead)
        }

        #expect(proof.crashRecoveryProofs.contains { $0.crashPoint == .beforeCheckpoint && $0.recoveredSafely })
        #expect(proof.crashRecoveryProofs.contains { $0.crashPoint == .afterWriteBeforePostcondition && $0.recoveredSafely })

        let audioProof = try #require(proof.domainMatrix.results.first { $0.domain == .audioUpload })
        #expect(audioProof.domainSpecificProofs["pendingInterruptedStateRoundtrip"] == true)
        #expect(audioProof.domainSpecificProofs["finalizedProofStateRoundtrip"] == true)

        let evidence = try #require(result.evidencePackage)
        #expect(evidence.switchBackStatus == .passed)
        #expect(evidence.diagnosticsRedactionStatus == .passed)
        #expect(result.evidenceRedacted)
        #expect(evidence.redactedDiagnostics.joined(separator: "\n").contains("/Users/") == false)
        #expect(evidence.redactedDiagnostics.joined(separator: "\n").contains(sourceRoot.path) == false)
        #expect(result.scorecard.status == .codeCompleteNeedsDeviceEvidence)
        #expect(result.scorecard.blockers.contains(.realDeviceEvidenceMissing))
    }

    @Test func debugRunnerWritesRedactedJSONLEvidenceAndUISafeSummary() throws {
        let fileManager = FileManager()
        let sourceRoot = try makeDriverSourceRoot(fileManager: fileManager)
        let runID = "t6-\(sourceRoot.lastPathComponent)"
        let evidenceRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CanonicalSwitchBackProofDebugRunner", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        try? fileManager.removeItem(at: evidenceRoot)
        defer { try? fileManager.removeItem(at: sourceRoot) }
        defer { try? fileManager.removeItem(at: evidenceRoot) }

        let summary = CanonicalSwitchBackProofDebugRunner(fileManager: fileManager).run(
            nodeRole: .iPhone,
            appDataRootURL: sourceRoot,
            runID: runID
        )

        #expect(summary.status == .passed, Comment(rawValue: summary.displayText))
        #expect(summary.realDeviceEvidence == false)
        #expect(summary.evidencePath.hasPrefix("temp/CanonicalSwitchBackProofDebugRunner/"))
        #expect(summary.evidencePath.hasSuffix(CanonicalSwitchBackProofEvidenceJSONLWriter.relativeEvidencePath))
        #expect(summary.displayText.contains(sourceRoot.path) == false)
        #expect(summary.warning.contains("realDeviceEvidence=false"))

        let evidenceURL = evidenceRoot.appendingPathComponent(CanonicalSwitchBackProofEvidenceJSONLWriter.relativeEvidencePath)
        let text = try String(contentsOf: evidenceURL, encoding: .utf8)
        #expect(text.contains("canonicalSwitchBackProofDriverStarted"))
        #expect(text.contains("canonicalSwitchBackProofCloneCreated"))
        #expect(text.contains("canonicalSwitchBackProofHarnessCompleted"))
        #expect(text.contains("canonicalSwitchBackProofEvidenceWritten"))
        #expect(text.contains("canonicalSwitchBackProofRealDeviceEvidenceMissing"))
        #expect(text.contains("\"evidenceKind\":\"realisticRoot\""))
        #expect(text.contains("\"realDeviceEvidencePresent\":false"))
        #expect(text.contains(sourceRoot.path) == false)
        #expect(text.contains("/Users/example") == false)
        #expect(text.contains("0123456789abcdef0123456789abcdef") == false)
    }

    @Test func debugRunnerSurfacesBlockerForMissingSourceRootWithoutCrash() throws {
        let fileManager = FileManager()
        let missingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CanonicalSwitchBackMissingSource-\(UUID().uuidString)", isDirectory: true)

        let summary = CanonicalSwitchBackProofDebugRunner(fileManager: fileManager).run(
            nodeRole: .iPhone,
            appDataRootURL: missingRoot
        )

        #expect(summary.status == .blocked)
        #expect(summary.blockers.contains("sourceRootMissing"))
        #expect(summary.realDeviceEvidence == false)
        #expect(summary.evidencePath.contains("/Users/") == false)
    }

    @Test func iPhoneDebugDriverAndSettingsButtonAreWiredUnderDebug() throws {
        _ = IPhoneCanonicalSwitchBackProofDriver(fileManager: .default)
        #expect(IPhoneCanonicalSwitchBackProofDriver.appDataRootURL().lastPathComponent == "Rokurics")

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsURL = repoRoot.appendingPathComponent("Rokurics/IPhoneSettingsView.swift", isDirectory: false)
        let settingsText = try String(contentsOf: settingsURL, encoding: .utf8)

        #expect(settingsText.contains("#if DEBUG"))
        #expect(settingsText.contains("运行新旧内核切回证明"))
        #expect(settingsText.contains("IPhoneCanonicalSwitchBackProofDriver().run()"))
        #expect(settingsText.contains("不直接写当前生产库"))
        #expect(settingsText.contains("不触发 sync/upload"))
    }

    @Test func v862ScorecardBlocksManualSwitchWhenDriverProofIsMissing() {
        let scorecard = CanonicalSyncKernelCompletionScorecard.v862(
            switchBackDriverResult: nil,
            realDeviceEvidencePresent: true
        )

        #expect(scorecard.status == .blocked)
        #expect(scorecard.blockers.contains(.realisticRootSwitchBackProofMissing))
        #expect(scorecard.diagnosticsSummary.contains("readyForManualSwitchTrial=false"))
    }

    private func makeDriverSourceRoot(fileManager: FileManager) throws -> URL {
        let sourceRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CanonicalSwitchBackDriverSource-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try "schema=legacy-source-v1\nrecordingID=source-recording\n".data(using: .utf8)?.write(
            to: sourceRoot.appendingPathComponent("source-recording.json", isDirectory: false),
            options: .atomic
        )
        return sourceRoot
    }
}
