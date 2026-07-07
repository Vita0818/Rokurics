//
//  CanonicalExecutionShadowTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalExecutionShadowTests {
    @Test func executionShadowDryRunBuildsReportWithoutProductionSideEffects() {
        let local = CanonicalProductionTestFixtures.snapshot()
        let peer = CanonicalProductionTestFixtures.snapshot(
            node: CanonicalProductionTestFixtures.node("mac-01", platform: "Mac")
        )

        let result = CanonicalExecutionShadowPreparationRunner().run(
            configuration: .enabled(mode: .executionShadowDryRun),
            trigger: .iPhoneSyncTick,
            nodeRole: .iPhone,
            domain: .inventory,
            localSnapshot: local,
            peerSnapshot: peer,
            ports: IPhoneCanonicalDryRunPorts.makePortSet(),
            syncRunID: "execution-shadow-dry-run"
        )

        #expect(result.succeeded)
        #expect(result.report.events.contains { $0.kind == .canonicalExecutionShadowStarted })
        #expect(result.report.events.contains { $0.kind == .canonicalExecutionShadowFileWriteSuppressed })
        #expect(result.report.events.contains { $0.kind == .canonicalExecutionShadowUploadRehearsed })
        #expect(result.report.events.contains { $0.kind == .canonicalExecutionShadowApplyRehearsed })
        #expect(result.report.events.contains { $0.kind == .canonicalExecutionShadowCompleted })
        #expect(result.report.productionAudit?.allowed == true)
        #expect(result.report.productionAudit?.nodeRole == .iPhone)
        #expect(result.report.productionAudit?.allowedMode == .executionShadowDryRun)
        #expect(result.report.productionAudit?.deniedSideEffects.contains(.fileWrite) == true)
        #expect(result.report.productionAudit?.deniedSideEffects.contains(.networkRequest) == true)
    }

    @Test func routePolicyAndTransportProbeAcceptReadOnlyAndRejectMutatingRoutes() async throws {
        let source = CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone")
        let destination = CanonicalProductionTestFixtures.node("mac-01", platform: "Mac")
        let port = IPhoneCanonicalShadowTransportPort()
        let enabledPolicy = CanonicalShadowNetworkProbePolicy(isEnabled: true)
        let manifestRequest = CanonicalProductionTransportBuildRequest(
            source: source,
            destination: destination,
            route: .manifestExchange,
            existingRoutePath: port.existingRoutePath(for: .manifestExchange),
            body: Data("{}".utf8),
            nonce: "nonce-shadow"
        )
        let manifestProbe = try await CanonicalShadowTransportProbe().project(
            request: manifestRequest,
            transport: port,
            networkPolicy: enabledPolicy
        )

        #expect(manifestProbe.accepted)
        #expect(manifestProbe.sentNetwork == false)
        #expect(manifestProbe.envelopeReport.classification == .readOnly)
        #expect(manifestProbe.envelopeReport.bodyHashPrefix != nil)
        #expect(manifestProbe.envelopeReport.timestampPresent)
        #expect(manifestProbe.envelopeReport.noncePresent)
        #expect(manifestProbe.envelopeReport.signatureProjectionPresent)
        #expect(manifestProbe.envelopeReport.reason.contains("networkSendSuppressedShadow"))

        let uploadRequest = CanonicalProductionTransportBuildRequest(
            source: source,
            destination: destination,
            route: .uploadStart,
            existingRoutePath: port.existingRoutePath(for: .uploadStart),
            body: Data("{}".utf8),
            nonce: "nonce-shadow"
        )
        let uploadProbe = try await CanonicalShadowTransportProbe().project(
            request: uploadRequest,
            transport: port,
            networkPolicy: enabledPolicy
        )

        #expect(uploadProbe.accepted == false)
        #expect(uploadProbe.sentNetwork == false)
        #expect(uploadProbe.envelopeReport.classification == .mutating)
        #expect(uploadProbe.failureReason == "mutatingRouteRejected")
    }

    @Test func uploadRehearsalUsesShadowReceiverAndSupportsResumeNoOpConflictAndHashFailure() async throws {
        let root = CanonicalRootToken("shadow-upload-root")
        let reference = CanonicalFileReference(rootToken: root, logicalPathToken: "audio/recording-01.m4a", artifactKind: .audio)
        let bytes = Data("abcdefghi".utf8)
        let receiver = CanonicalShadowUploadReceiver(rootToken: root)
        let resumed = await CanonicalShadowUploadRehearsal().run(
            input: CanonicalShadowUploadRehearsalInput(
                objectID: "recording-01",
                targetReference: reference,
                bytes: bytes,
                chunkSize: 4,
                simulateInterruptionAfterFirstChunk: true
            ),
            receiver: receiver
        )
        let stored = try await receiver.read(reference: reference)

        #expect(resumed.completed)
        #expect(resumed.divergence == .interruptedAndResumed)
        #expect(resumed.calledProductionUploadCoordinator == false)
        #expect(resumed.calledRecordingUploadClient == false)
        #expect(resumed.calledSecureMacUploadClient == false)
        #expect(resumed.wroteProductionInbox == false)
        #expect(resumed.wroteReceiveJSON == false)
        #expect(resumed.wroteShadowReceiver)
        #expect(stored.bytes == bytes)

        let noOpReceiver = CanonicalShadowUploadReceiver(rootToken: root)
        let noOp = await CanonicalShadowUploadRehearsal().run(
            input: CanonicalShadowUploadRehearsalInput(
                objectID: "recording-01",
                targetReference: reference,
                bytes: bytes,
                existingReceiverBytes: bytes
            ),
            receiver: noOpReceiver
        )
        #expect(noOp.completed)
        #expect(noOp.divergence == .sameHashNoOp)
        #expect(noOp.wroteShadowReceiver == false)

        let conflict = await CanonicalShadowUploadRehearsal().run(
            input: CanonicalShadowUploadRehearsalInput(
                objectID: "recording-01",
                targetReference: reference,
                bytes: bytes,
                existingReceiverBytes: Data("different".utf8)
            ),
            receiver: CanonicalShadowUploadReceiver(rootToken: root)
        )
        #expect(conflict.completed == false)
        #expect(conflict.divergence == .differentHashConflict)

        let mismatch = await CanonicalShadowUploadRehearsal().run(
            input: CanonicalShadowUploadRehearsalInput(
                objectID: "recording-02",
                targetReference: CanonicalFileReference(rootToken: root, logicalPathToken: "audio/recording-02.m4a", artifactKind: .audio),
                bytes: bytes,
                declaredTotalHash: CanonicalHash.sha256String("wrong")
            ),
            receiver: CanonicalShadowUploadReceiver(rootToken: root)
        )
        #expect(mismatch.completed == false)
        #expect(mismatch.divergence == .finalizeHashMismatch)
    }

    @Test func applyRehearsalWritesOnlyShadowStoreAndTombstoneDoesNotDelete() async {
        let local = CanonicalProductionTestFixtures.snapshot()
        let peer = CanonicalProductionTestFixtures.snapshot(
            node: CanonicalProductionTestFixtures.node("mac-01", platform: "Mac")
        )
        let action = CanonicalApplyAction(
            kind: .objectTombstoneApply,
            source: .peer,
            target: CanonicalApplyTarget(objectID: "recording-01"),
            bridgeHint: .noPhysicalDelete,
            reason: "peerTombstone"
        )
        let result = await CanonicalShadowApplyRehearsal().run(
            applyPlan: CanonicalApplyPlan(trigger: .manual, actions: [action]),
            localManifest: local.manifest,
            peerManifest: peer.manifest
        )

        #expect(result.calledApplySyncManifest == false)
        #expect(result.calledArtifactApply == false)
        #expect(result.wroteProductionStore == false)
        #expect(result.wroteShadowStore)
        #expect(result.tombstonePhysicalDelete == false)
        #expect(result.rollbackResult?.succeeded == true)
    }

    @Test func productionExecuteStillBlockedForOnDeviceRolesAndShadowAuditIsAllowed() {
        let shadowAudit = CanonicalProductionExecutionGuard.evaluateShadow(
            mode: .executionShadowWithShadowFileStore,
            token: CanonicalProductionExecutionToken(
                mode: .executionShadowWithShadowFileStore,
                domainAllowlist: [.fileRuntime],
                nodeRole: .mac,
                syncRunID: "shadow-audit"
            ),
            domains: [.fileRuntime],
            rollbackPlan: CanonicalRollbackPlan(planID: "shadow-rollback", checkpoints: [], actions: []),
            dryRunEquivalence: nil,
            unresolvedConflictCount: 2
        )
        #expect(shadowAudit.allowed)
        #expect(shadowAudit.nodeRole == .mac)
        #expect(shadowAudit.requestedMode == .executionShadowWithShadowFileStore)
        #expect(shadowAudit.allowedMode == .executionShadowWithShadowFileStore)
        #expect(shadowAudit.unresolvedConflictCount == 2)

        let productionAudit = CanonicalProductionExecutionGuard.evaluate(
            mode: .productionExecute,
            token: CanonicalProductionExecutionToken(
                mode: .productionExecute,
                domainAllowlist: [],
                nodeRole: .mac,
                syncRunID: "blocked-production",
                ownerApproved: true
            ),
            policy: CanonicalProductionExecutionPolicy(
                requiredDomains: [],
                requiredPorts: [],
                requireOwnerApproval: false,
                requireRollbackPlan: false,
                requireDryRunEquivalence: false,
                requireMigrationGateUnblocked: false,
                rejectUnresolvedConflicts: false
            ),
            domains: [],
            ports: CanonicalProductionPortSet(),
            rollbackPlan: nil,
            dryRunReportID: nil,
            dryRunEquivalence: nil,
            readinessReport: nil,
            unresolvedConflictCount: 0
        )
        #expect(productionAudit.allowed == false)
        #expect(productionAudit.rejectionReasons.contains(.blockedProductionExecute))
        #expect(productionAudit.deniedSideEffects.contains(.uploadChunkSend))
    }

    @Test func iPhoneShadowFilePortWritesOnlyShadowRootAndRejectsUnsafeAccess() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsExecutionShadowTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let realRootURL = rootURL.appendingPathComponent("RealDocuments", isDirectory: true)
        try FileManager.default.createDirectory(at: realRootURL, withIntermediateDirectories: true)
        let realFileURL = realRootURL.appendingPathComponent("audio.m4a")
        try Data("real".utf8).write(to: realFileURL)
        let shadowRootURL = rootURL.appendingPathComponent("Shadow", isDirectory: true)
        let rootToken = CanonicalRootToken("iphone-shadow-root")
        let port = try IPhoneCanonicalShadowFilePort(
            binding: CanonicalShadowRootBinding(
                rootToken: rootToken,
                rootKind: .shadowCopy,
                rootURL: shadowRootURL,
                prohibitedProductionRootURL: realRootURL
            )
        )
        let reference = CanonicalFileReference(rootToken: rootToken, logicalPathToken: "metadata/recording-01.json")
        let initialBytes = Data("initial".utf8)
        let initialHash = try #require(InMemoryCanonicalFileStore.hash(initialBytes, policy: .sha256))
        _ = try await port.writeMetadata(
            CanonicalFileWriteIntent(
                reference: reference,
                bytes: initialBytes,
                purpose: .metadataBlob,
                expectedContentHash: initialHash,
                expectedByteSize: Int64(initialBytes.count),
                conflictPolicy: .replace
            ),
            rollbackCheckpoint: nil
        )
        let updatedBytes = Data("updated".utf8)
        _ = try await port.writeMetadata(
            CanonicalFileWriteIntent(
                reference: reference,
                bytes: updatedBytes,
                purpose: .metadataBlob,
                conflictPolicy: .replace
            ),
            rollbackCheckpoint: CanonicalRollbackCheckpoint(checkpointID: "shadow-checkpoint", domain: .fileRuntime)
        )
        _ = try await port.rollbackWrite(CanonicalProductionFileRollbackRequest(checkpointID: "shadow-checkpoint", reference: reference))
        let restored = try await port.readMetadata(CanonicalProductionMetadataReadRequest(objectID: "recording-01", reference: reference))

        #expect(restored.bytes == initialBytes)
        #expect(FileManager.default.fileExists(atPath: shadowRootURL.appendingPathComponent(reference.logicalPathToken).path))
        #expect((try? Data(contentsOf: realFileURL)) == Data("real".utf8))

        await expectPortError {
            _ = try await port.resolveRootBound(CanonicalFileReference(rootToken: rootToken, logicalPathToken: "../escape"))
        }
        await expectPortError {
            _ = try await port.writeMetadata(
                CanonicalFileWriteIntent(
                    reference: reference,
                    bytes: Data("bad".utf8),
                    purpose: .metadataBlob,
                    expectedContentHash: CanonicalHash.sha256String("different"),
                    conflictPolicy: .replace
                ),
                rollbackCheckpoint: nil
            )
        }
        await expectSyncError {
            _ = try IPhoneCanonicalShadowFilePort(
                binding: CanonicalShadowRootBinding(
                    rootToken: rootToken,
                    rootKind: .productionRootRejected,
                    rootURL: realRootURL,
                    prohibitedProductionRootURL: realRootURL
                )
            )
        }
        _ = try await port.markTombstone(CanonicalProductionTombstoneRequest(reference: reference, reason: "shadowTombstone"))
        #expect((try? Data(contentsOf: realFileURL)) == Data("real".utf8))
    }

    @Test func iPhoneShadowTransportNeverSendsNetworkByDefault() async throws {
        let source = CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone")
        let destination = CanonicalProductionTestFixtures.node("mac-01", platform: "Mac")
        let port = IPhoneCanonicalShadowTransportPort()
        let request = CanonicalProductionTransportBuildRequest(
            source: source,
            destination: destination,
            route: .manifestExchange,
            existingRoutePath: port.existingRoutePath(for: .manifestExchange),
            body: Data("{}".utf8),
            nonce: "nonce-shadow"
        )
        let signed = try await port.buildSignedRequest(request)

        #expect(signed.bodyHash == CanonicalTransportEnvelope.hash(request.body))
        #expect(signed.signaturePrefix != nil)
        await expectPortError {
            _ = try await port.sendRequest(signed)
        }
    }

    private func expectPortError(operation: () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("Expected shadow port error")
        } catch {
            #expect(String(describing: error).isEmpty == false)
        }
    }

    private func expectSyncError(operation: () throws -> Void) async {
        do {
            try operation()
            Issue.record("Expected shadow sync error")
        } catch {
            #expect(String(describing: error).isEmpty == false)
        }
    }
}
