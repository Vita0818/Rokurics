//
//  CanonicalLegacyCompatibilityTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalLegacyCompatibilityTests {
    @Test func compatibilityMatrixProvesEveryDomain() {
        let matrix = CanonicalLegacyCompatibilityMatrix.defaultV844()

        #expect(matrix.isFullyProven)
        #expect(matrix.results.count == CanonicalLegacyCompatibilityDomain.allCases.count)
        #expect(Set(matrix.provenDomains) == Set(CanonicalLegacyCompatibilityDomain.allCases))
        #expect(matrix.blockers.isEmpty)
        #expect(matrix.diagnosticsSummary.contains("legacyDeletion=false"))
        #expect(matrix.diagnosticsSummary.contains("/Users/") == false)

        for result in matrix.results {
            #expect(result.canonicalWriteFormatLegacyReadable)
            #expect(result.legacyWriteFormatCanonicalReadable)
            #expect(result.switchBackNoMigration)
            #expect(result.noCanonicalOnlyRequiredField)
            #expect(result.unknownFieldsIgnoredOrBackwardCompatible)
            #expect(result.rollbackAvailable)
            #expect(result.diagnosticsRedacted)
            #expect(result.legacyReadPathAvailable)
            #expect(result.legacyWritePathAvailable)
            #expect(result.noPhysicalDeleteRequired)
            #expect(result.isProven)
        }
    }

    @Test func matrixReportsCanonicalOnlyRequiredFieldAsBlocker() {
        let result = CanonicalLegacyCompatibilityResult.prove(
            domain: .recordingMetadata,
            noCanonicalOnlyRequiredField: false
        )

        #expect(result.isProven == false)
        #expect(result.blockers.contains(.canonicalOnlyRequiredFieldRequired))
    }

    @Test func roundtripCompatibilityForEveryDomain() throws {
        for domain in CanonicalLegacyCompatibilityDomain.allCases {
            var harness = CanonicalLegacySwitchBackHarness(seedLegacyRecords: false)

            let legacyWrite = harness.legacyWrite(domain: domain, value: "legacy-\(domain.rawValue)")
            let canonicalRead = try #require(harness.canonicalRead(domain: domain))
            #expect(canonicalRead.value == legacyWrite.value)
            #expect(canonicalRead.formatVersion == "legacy-v1")

            let canonicalWrite = harness.canonicalWrite(domain: domain, value: "canonical-\(domain.rawValue)")
            let legacyRead = try #require(harness.legacyRead(domain: domain))
            #expect(legacyRead.value == canonicalWrite.value)
            #expect(legacyRead.formatVersion == "legacy-v1")
            #expect(legacyRead.ignoredUnknownFieldCount == 2)

            harness.switchMode(.oldKernel)
            let legacyModify = harness.legacyWrite(domain: domain, value: "legacy-modified-\(domain.rawValue)")
            harness.switchMode(.canonicalFullSync)
            let canonicalAgain = try #require(harness.canonicalRead(domain: domain))
            #expect(canonicalAgain.value == legacyModify.value)
            #expect(canonicalAgain.formatVersion == "legacy-v1")

            var rollbackHarness = CanonicalLegacySwitchBackHarness(seedLegacyRecords: false)
            let baseline = rollbackHarness.legacyWrite(domain: domain, value: "rollback-baseline-\(domain.rawValue)")
            let rollbackRead = rollbackHarness.canonicalWriteWithRollbackAfterPartialFailure(domain: domain)
            let readAfterRollback = try #require(rollbackRead)
            #expect(readAfterRollback.value == baseline.value)
            #expect(readAfterRollback.revision == baseline.revision)

            var diagnosticHarness = CanonicalLegacySwitchBackHarness(seedLegacyRecords: false)
            _ = diagnosticHarness.canonicalWrite(domain: domain, value: "diagnostic-\(domain.rawValue)")
            let beforeDiagnostic = diagnosticHarness.dataFormatFingerprint(domain: domain)
            diagnosticHarness.recordCanonicalDiagnostic(domain: domain)
            let afterDiagnostic = diagnosticHarness.dataFormatFingerprint(domain: domain)
            #expect(beforeDiagnostic == afterDiagnostic)

            var fullSyncHarness = CanonicalLegacySwitchBackHarness(seedLegacyRecords: false)
            _ = fullSyncHarness.canonicalWrite(domain: domain, value: "full-sync-\(domain.rawValue)")
            fullSyncHarness.switchMode(.oldKernel)
            let oldKernelRead = try #require(fullSyncHarness.legacyRead(domain: domain))
            #expect(oldKernelRead.value == "full-sync-\(domain.rawValue)")
            #expect(oldKernelRead.formatVersion == "legacy-v1")
        }
    }

    @Test func crashRestartSafetyForEveryDomainAndCheckpoint() {
        let restartModes: [CanonicalKernelSwitchMode] = [.oldKernel, .canonicalFullSync]

        for domain in CanonicalLegacyCompatibilityDomain.allCases {
            for crashPoint in CanonicalLegacyCrashPoint.allCases {
                for restartMode in restartModes {
                    var harness = CanonicalLegacySwitchBackHarness()
                    let result = harness.simulateCrashAndRestart(
                        domain: domain,
                        crashPoint: crashPoint,
                        restartMode: restartMode
                    )

                    #expect(result.recoveredSafely)
                    #expect(result.oldKernelCanRead)
                    #expect(result.canonicalFullSyncCanRead)
                    #expect(result.noDataLoss)
                    #expect(result.incompleteStateBlockedOrRecovered)
                    #expect(result.physicalDeleteCount == 0)
                    #expect(result.duplicateSuppressionApplied == false)
                    #expect(result.blockers.isEmpty)
                    #expect(result.diagnosticsSummary.contains("/Users/") == false)
                }
            }
        }
    }

    @Test func switchBackRuntimeHarnessComparesOldAndCanonicalState() {
        var harness = CanonicalLegacySwitchBackHarness()
        let result = harness.runSwitchBackProof()

        #expect(result.isProven)
        #expect(result.switchBackNoMigration)
        #expect(result.switchBackComparisonPassed)
        #expect(result.switchForwardComparisonPassed)
        #expect(result.physicalDeleteCount == 0)
        #expect(result.oldKernelCrashedAfterCanonicalFullSync == false)
        #expect(result.canonicalFullSyncCrashedAfterSwitchBack == false)
        #expect(result.blockers.isEmpty)

        for domain in CanonicalLegacyCompatibilityDomain.allCases {
            #expect(result.legacyReadsAfterCanonicalWrite[domain]?.value == "canonical-full-sync-\(domain.rawValue)")
            #expect(result.canonicalReadsAfterLegacyModify[domain]?.value == "legacy-modified-\(domain.rawValue)")
        }
    }

    @Test func realisticRootHarnessProvesSwitchBackWithoutLegacyRetirement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalSwitchBackRealisticRootHarness-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try CanonicalSwitchBackRealisticRootHarness(rootURL: root).run()

        #expect(result.isProven)
        #expect(result.testClonedRoot)
        #expect(result.usesProductionRoot == false)
        #expect(result.legacyReadableStateCount == CanonicalLegacyCompatibilityDomain.allCases.count)
        #expect(result.canonicalReadableStateCount == CanonicalLegacyCompatibilityDomain.allCases.count)
        #expect(result.physicalDeleteCount == 0)
        #expect(result.resourceMoveCount == 0)
        #expect(result.legacyRetirementPerformed == false)
        #expect(result.diagnosticsSummary.contains("legacyRetirementPerformed=false"))
        #expect(result.diagnosticsSummary.contains("/Users/") == false)
    }
}
