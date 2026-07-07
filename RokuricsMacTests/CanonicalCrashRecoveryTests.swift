//
//  CanonicalCrashRecoveryTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalCrashRecoveryTests {
    @Test func allV857CrashPointsRecoverOrFailClosedForBusinessDomainsOnMac() {
        #expect(CanonicalCrashPoint.allCases.count == 12)

        for domain in CanonicalDomainSwitchBackMatrix.v857Domains {
            for crashPoint in CanonicalCrashPoint.allCases {
                var harness = CanonicalLegacySwitchBackHarness()
                let result = harness.simulateCrashAndRestart(
                    domain: domain,
                    crashPoint: crashPoint,
                    restartMode: .oldKernel
                )

                #expect(result.recoveredSafely)
                #expect(result.oldKernelCanRead)
                #expect(result.canonicalFullSyncCanRead)
                #expect(result.noDataLoss)
                #expect(result.incompleteStateBlockedOrRecovered)
                #expect(result.partialStateTreatedAsCompleted == false)
                #expect(result.partialStateTreatedAsAudioAvailable == false)
                #expect(result.duplicateJobStormDetected == false)
                #expect(result.legacyIncompatibleCorruptionDetected == false)
                #expect(result.physicalDeleteCount == 0)
                #expect(result.diagnosticsSummary.contains("/Users/") == false)
            }
        }
    }

    @Test func audioUploadCrashPointsNeverTreatPartialStateAsCompletedOrAvailableOnMac() {
        let audioCrashPoints: [CanonicalCrashPoint] = [
            .duringAudioSessionStart,
            .duringAudioChunkWrite,
            .duringAudioFinalize,
            .afterAudioFinalizeBeforeLocalLedgerUpdate,
            .duringRetryStatePersist
        ]

        for crashPoint in audioCrashPoints {
            var harness = CanonicalLegacySwitchBackHarness()
            let result = harness.simulateCrashAndRestart(
                domain: .audioUpload,
                crashPoint: crashPoint,
                restartMode: .canonicalFullSync
            )

            #expect(result.recoveredSafely)
            #expect(result.partialStateTreatedAsCompleted == false)
            #expect(result.partialStateTreatedAsAudioAvailable == false)
            #expect(result.duplicateJobStormDetected == false)
            #expect(result.blockers.isEmpty)
        }
    }
}
