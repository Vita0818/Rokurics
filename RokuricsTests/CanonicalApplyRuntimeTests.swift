//
//  CanonicalApplyRuntimeTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalApplyRuntimeTests {
    @Test func defaultDisabledUsesLegacy() async {
        let result = await Self.execute(mode: .disabled)

        #expect(result.gateResult.state == .legacyOwner)
        #expect(result.legacyFallbackUsed)
        #expect(result.executedActionIDs.isEmpty)
    }

    @Test func diagnosticsOnlyExecutesNothing() async {
        let result = await Self.execute(mode: .diagnosticsOnly)

        #expect(result.gateResult.state == .diagnosticsOnly)
        #expect(result.executedActionIDs.isEmpty)
        #expect(result.legacyFallbackUsed)
    }

    @Test func noCommitExecutesNothing() async {
        let result = await Self.execute(mode: .noCommit)

        #expect(result.gateResult.state == .noCommit)
        #expect(result.executedActionIDs.isEmpty)
        #expect(result.legacyFallbackUsed)
    }

    @Test func testRootApplyExecutesEnabledNonAudioAction() async {
        let action = Self.action()
        let result = await Self.execute(
            mode: .testRootApply,
            action: action,
            registry: Self.registry(domain: .recordingMetadata, result: .success(action: action, domain: .recordingMetadata))
        )

        #expect(result.gateResult.executesCommit)
        #expect(result.executedActionIDs == [action.actionID])
        #expect(result.duplicateLegacySuppressedActionIDs == [action.actionID])
    }

    @Test func productionRootApplyBlockedInReleaseDefault() async {
        let action = Self.action()
        let result = await CanonicalApplyRuntimeOwner().execute(
            Self.context(
                configuration: CanonicalApplyRuntimeConfiguration(
                    mode: .productionRootApplyWithLegacyFallback,
                    policy: CanonicalApplyRuntimePolicy(enabledDomains: [.recordingMetadata])
                ),
                action: action,
                registry: Self.registry(domain: .recordingMetadata, result: .success(action: action, domain: .recordingMetadata))
            )
        )

        #expect(result.gateResult.blockers.contains(.releaseDefaultProductionApplyBlocked))
        #expect(result.legacyFallbackUsed)
        #expect(result.executedActionIDs.isEmpty)
    }

    @Test func missingExecutorBlocksAndFallsBack() async {
        let result = await Self.execute(registry: CanonicalApplyRuntimeExecutorRegistry())

        #expect(result.gateResult.blockers.contains(.missingExecutor))
        #expect(result.legacyFallbackUsed)
        #expect(result.executedActionIDs.isEmpty)
    }

    @Test func audioActionBlocked() async {
        let action = CanonicalApplyAction(
            kind: .generatedArtifactDownloadApply,
            source: .peer,
            target: CanonicalApplyTarget(
                objectID: "recording-audio",
                artifactID: CanonicalArtifact.Kind.audio.artifactID(for: "recording-audio"),
                artifactKind: .audio
            ),
            reason: "audioUpload"
        )
        let result = await Self.execute(
            action: action,
            enabledDomains: [.generatedArtifacts, .audioUpload],
            registry: Self.registry(domain: .generatedArtifacts, result: .success(action: action, domain: .generatedArtifacts))
        )

        #expect(result.gateResult.blockers.contains(.audioActionBlocked))
        #expect(result.executedActionIDs.isEmpty)
    }

    @Test func rollbackFailureIsFatalAndFallsBack() async {
        let action = Self.action()
        let result = await Self.execute(
            action: action,
            registry: Self.registry(
                domain: .recordingMetadata,
                result: .failure(
                    action: action,
                    domain: .recordingMetadata,
                    rollbackAttempted: true,
                    rollbackSucceeded: false,
                    rollbackFatal: true,
                    reason: "rollbackFailure"
                )
            )
        )

        #expect(result.report.fatalBlocker)
        #expect(result.legacyFallbackUsed)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.report.diagnostics.contains { $0.kind == .canonicalApplyRuntimeRollbackFailed })
    }

    @Test func duplicateSuppressionOnlyAfterSuccess() async {
        let action = Self.action()
        let failure = await Self.execute(
            action: action,
            registry: Self.registry(
                domain: .recordingMetadata,
                result: .failure(action: action, domain: .recordingMetadata, reason: "preconditionMismatch")
            )
        )
        let success = await Self.execute(
            action: action,
            registry: Self.registry(domain: .recordingMetadata, result: .success(action: action, domain: .recordingMetadata))
        )

        #expect(failure.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(success.duplicateLegacySuppressedActionIDs == [action.actionID])
    }

    @Test func diagnosticsDoNotExposeFullPathHashOrContent() async {
        let action = Self.action()
        let result = await Self.execute(
            action: action,
            registry: Self.registry(
                domain: .recordingMetadata,
                result: .success(
                    action: action,
                    domain: .recordingMetadata,
                    detail: "/Users/vita/secret/{\"hash\":\"0123456789abcdef0123456789abcdef\"}"
                )
            )
        )
        let summaries = result.report.diagnostics.map { $0.summary() }.joined(separator: "\n")
        let allDiagnosticsRedacted = result.report.diagnostics.allSatisfy { $0.isRedacted }

        #expect(allDiagnosticsRedacted)
        #expect(!summaries.contains("/Users/vita"))
        #expect(!summaries.contains("0123456789abcdef"))
        #expect(!summaries.contains("{\"hash\""))
    }

    private static func execute(
        mode: CanonicalApplyRuntimeMode = .testRootApply,
        action: CanonicalApplyAction = action(),
        enabledDomains: [CanonicalApplyRuntimeDomain] = [.recordingMetadata],
        registry: CanonicalApplyRuntimeExecutorRegistry? = nil
    ) async -> CanonicalApplyRuntimeResult {
        let resolvedRegistry = registry ?? Self.registry(
            domain: CanonicalApplyRuntimeGate.domain(for: action),
            result: .success(action: action, domain: CanonicalApplyRuntimeGate.domain(for: action))
        )
        return await CanonicalApplyRuntimeOwner().execute(
            context(
                configuration: CanonicalApplyRuntimeConfiguration(
                    mode: mode,
                    policy: CanonicalApplyRuntimePolicy(
                        debugInternalBuild: true,
                        ownerApproved: true,
                        releaseDefaultBuild: false,
                        enabledDomains: enabledDomains
                    )
                ),
                action: action,
                registry: resolvedRegistry
            )
        )
    }

    private static func context(
        configuration: CanonicalApplyRuntimeConfiguration,
        action: CanonicalApplyAction,
        registry: CanonicalApplyRuntimeExecutorRegistry
    ) -> CanonicalApplyRuntimeOwnerContext {
        CanonicalApplyRuntimeOwnerContext(
            configuration: configuration,
            applyPlan: CanonicalApplyPlan(trigger: .manual, actions: [action]),
            localManifest: manifest(nodeID: "iphone-01", platform: "iPhone"),
            peerManifest: manifest(nodeID: "mac-01", platform: "Mac"),
            inventorySnapshotValid: true,
            canonicalPlanAuthorityAllowed: true,
            legacyFallbackAvailable: true,
            registry: registry,
            syncRunID: "apply-runtime-test"
        )
    }

    private static func registry(
        domain: CanonicalApplyRuntimeDomain,
        result: CanonicalApplyRuntimeExecutorResult
    ) -> CanonicalApplyRuntimeExecutorRegistry {
        CanonicalApplyRuntimeExecutorRegistry(entries: [
            CanonicalApplyRuntimeExecutorEntry(domain: domain) { _ in result }
        ])
    }

    private static func action(
        kind: CanonicalApplyActionKind = .recordingMetadataApply,
        objectID: String = "recording-01"
    ) -> CanonicalApplyAction {
        CanonicalApplyAction(
            kind: kind,
            source: .peer,
            target: CanonicalApplyTarget(objectID: objectID),
            reason: kind.rawValue
        )
    }

    private static func manifest(nodeID: String, platform: String) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(nodeID: nodeID, platform: platform, capabilities: [.recordingMetadata]),
            objects: [],
            manifestCapabilities: [.recordingMetadata]
        )
    }
}
