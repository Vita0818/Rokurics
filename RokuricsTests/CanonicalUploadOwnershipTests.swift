//
//  CanonicalUploadOwnershipTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/11.
//

import Testing
@testable import Rokurics

struct CanonicalUploadOwnershipTests {
    @Test func nonCanonicalModesCreateNoCanonicalUploadJob() {
        let old = CanonicalUploadDuplicateJobGuard.evaluate(objectID: Self.objectID, mode: .oldKernel)
        let shadow = CanonicalUploadDuplicateJobGuard.evaluate(objectID: Self.objectID, mode: .canonicalShadow)
        let decisionOnly = CanonicalUploadDuplicateJobGuard.evaluate(objectID: Self.objectID, mode: .canonicalDecisionOnly)
        let applyNoAudio = CanonicalUploadDuplicateJobGuard.evaluate(objectID: Self.objectID, mode: .canonicalApplyNoAudio)

        #expect(old.owner == .legacy)
        #expect(old.canonicalJobAllowed == false)
        #expect(shadow.canonicalJobAllowed == false)
        #expect(decisionOnly.canonicalJobAllowed == false)
        #expect(applyNoAudio.canonicalJobAllowed == false)
        #expect(shadow.suppressCanonicalFreshJob)
        #expect(decisionOnly.suppressCanonicalFreshJob)
        #expect(applyNoAudio.suppressCanonicalFreshJob)
    }

    @Test func canonicalFullSyncCanOwnAndSuppressExactLegacyFreshDuplicate() {
        let decision = CanonicalUploadDuplicateJobGuard.evaluate(
            objectID: Self.objectID,
            mode: .canonicalFullSync,
            gateAllowsCanonical: true,
            canonicalJobStarted: true
        )

        #expect(decision.owner == .canonical)
        #expect(decision.canonicalJobAllowed)
        #expect(decision.suppressLegacyFreshJob)
        #expect(decision.diagnostics.contains { $0.kind == .canonicalUploadOwnershipSelectedCanonical })
        #expect(decision.diagnostics.contains { $0.kind == .canonicalUploadDuplicateJobSuppressed })
    }

    @Test func canonicalBlockedBeforeStartAllowsSafeLegacyFallback() {
        let decision = CanonicalUploadDuplicateJobGuard.evaluate(
            objectID: Self.objectID,
            mode: .canonicalFullSync,
            gateAllowsCanonical: true,
            canonicalBlockedBeforeStart: true,
            legacyFallbackAvailable: true
        )

        #expect(decision.owner == .legacy)
        #expect(decision.allowLegacyFallback)
        #expect(decision.suppressLegacyFreshJob == false)
    }

    @Test func securityFailureAndConflictDoNotFallbackByBypassOrOverwrite() {
        let security = CanonicalUploadDuplicateJobGuard.evaluate(
            objectID: Self.objectID,
            mode: .canonicalFullSync,
            canonicalSecurityFailure: true
        )
        let conflict = CanonicalUploadDuplicateJobGuard.evaluate(
            objectID: Self.objectID,
            mode: .canonicalFullSync,
            canonicalConflict: true
        )

        #expect(security.owner == .none)
        #expect(security.allowLegacyFallback == false)
        #expect(security.blockers.contains(.securityFailure))
        #expect(conflict.owner == .none)
        #expect(conflict.allowLegacyFallback == false)
        #expect(conflict.blockers.contains(.differentHashOrSizeConflict))
    }

    @Test func finalizeSuccessSuppressesLegacyDuplicateButMissingProofDoesNotSuppressCompletedState() {
        let finalized = CanonicalUploadDuplicateJobGuard.evaluate(
            objectID: Self.objectID,
            mode: .canonicalFullSync,
            canonicalFinalizeSucceeded: true,
            canonicalFinalizeProofAccepted: true
        )
        let missingProof = CanonicalUploadDuplicateJobGuard.evaluate(
            objectID: Self.objectID,
            mode: .canonicalFullSync,
            canonicalFinalizeSucceeded: true,
            canonicalFinalizeProofAccepted: false
        )

        #expect(finalized.owner == .canonical)
        #expect(finalized.suppressLegacyFreshJob)
        #expect(finalized.suppressLegacyCompletedState)
        #expect(missingProof.owner == .legacy)
        #expect(missingProof.suppressLegacyCompletedState == false)
        #expect(missingProof.blockers.contains(.finalizedProofMissing))
    }

    @Test func existingLegacyRunningSuppressesCanonicalDuplicateAndViewRefreshCreatesNoJob() {
        let legacyRunning = CanonicalUploadDuplicateJobGuard.evaluate(
            objectID: Self.objectID,
            mode: .canonicalFullSync,
            gateAllowsCanonical: true,
            legacyJobRunning: true
        )
        let viewRefresh = CanonicalUploadDuplicateJobGuard.evaluate(
            objectID: Self.objectID,
            mode: .canonicalFullSync,
            gateAllowsCanonical: true,
            viewRefresh: true
        )

        #expect(legacyRunning.owner == .legacy)
        #expect(legacyRunning.suppressCanonicalFreshJob)
        #expect(legacyRunning.diagnostics.contains { $0.kind == .canonicalUploadDuplicateJobDetected })
        #expect(viewRefresh.owner == .none)
        #expect(viewRefresh.suppressLegacyFreshJob)
        #expect(viewRefresh.suppressCanonicalFreshJob)
        #expect(viewRefresh.blockers.contains(.viewRefreshCannotCreateUploadJob))
    }

    @Test func peerUnknownDefersWithoutLegacyOverwriteFallback() {
        let decision = CanonicalUploadDuplicateJobGuard.evaluate(
            objectID: Self.objectID,
            mode: .canonicalFullSync,
            gateAllowsCanonical: true,
            peerUnknownDeferred: true
        )

        #expect(decision.owner == .none)
        #expect(decision.canonicalJobAllowed == false)
        #expect(decision.allowLegacyFallback == false)
        #expect(decision.suppressLegacyFreshJob)
        #expect(decision.blockers.contains(.peerUnknown))
    }

    private static let objectID = "recording-v850-owner"
}
