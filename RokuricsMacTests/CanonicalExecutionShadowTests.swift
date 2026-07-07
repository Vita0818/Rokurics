//
//  CanonicalExecutionShadowTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalExecutionShadowTests {
    @Test func macShadowFilePortWritesOnlyShadowRootAndRejectsMutatingProductionRoot() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsMacExecutionShadowTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let productionRootURL = rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true)
        try FileManager.default.createDirectory(at: productionRootURL, withIntermediateDirectories: true)
        let receiveJSON = productionRootURL.appendingPathComponent("receive.json")
        try Data("receive-state".utf8).write(to: receiveJSON)
        let shadowRootURL = rootURL.appendingPathComponent("Shadow", isDirectory: true)
        let rootToken = CanonicalRootToken("mac-shadow-root")
        let port = try MacCanonicalShadowFilePort(
            binding: CanonicalShadowRootBinding(
                rootToken: rootToken,
                rootKind: .shadowCopy,
                rootURL: shadowRootURL,
                prohibitedProductionRootURL: productionRootURL
            )
        )
        let reference = CanonicalFileReference(rootToken: rootToken, logicalPathToken: "metadata/recording-01.json")
        let bytes = Data("metadata".utf8)
        let hash = try #require(InMemoryCanonicalFileStore.hash(bytes, policy: .sha256))
        _ = try await port.writeMetadata(
            CanonicalFileWriteIntent(
                reference: reference,
                bytes: bytes,
                purpose: .metadataBlob,
                expectedContentHash: hash,
                expectedByteSize: Int64(bytes.count),
                conflictPolicy: .replace
            ),
            rollbackCheckpoint: nil
        )

        #expect(FileManager.default.fileExists(atPath: shadowRootURL.appendingPathComponent(reference.logicalPathToken).path))
        #expect((try? Data(contentsOf: receiveJSON)) == Data("receive-state".utf8))

        await expectPortError {
            _ = try await port.resolveRootBound(CanonicalFileReference(rootToken: rootToken, logicalPathToken: "../escape"))
        }
        await expectSyncError {
            _ = try MacCanonicalShadowFilePort(
                binding: CanonicalShadowRootBinding(
                    rootToken: rootToken,
                    rootKind: .productionRootRejected,
                    rootURL: productionRootURL,
                    prohibitedProductionRootURL: productionRootURL
                )
            )
        }
        _ = try await port.markTombstone(CanonicalProductionTombstoneRequest(reference: reference, reason: "shadowOnly"))
        #expect((try? Data(contentsOf: receiveJSON)) == Data("receive-state".utf8))
    }

    @Test func macShadowTransportRejectsMutatingProbeAndDoesNotSendNetwork() async throws {
        let source = CanonicalProductionTestFixtures.node("mac-01", platform: "Mac")
        let destination = CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone")
        let port = MacCanonicalShadowTransportPort()
        let uploadRequest = CanonicalProductionTransportBuildRequest(
            source: source,
            destination: destination,
            route: .uploadChunk,
            existingRoutePath: port.existingRoutePath(for: .uploadChunk),
            body: Data("chunk".utf8),
            nonce: "nonce-shadow"
        )
        let probe = try await CanonicalShadowTransportProbe().project(
            request: uploadRequest,
            transport: port,
            networkPolicy: CanonicalShadowNetworkProbePolicy(isEnabled: true)
        )

        #expect(probe.accepted == false)
        #expect(probe.envelopeReport.classification == .mutating)
        #expect(probe.sentNetwork == false)
        #expect(probe.envelopeReport.signatureProjectionPresent)

        let signed = try await port.buildSignedRequest(uploadRequest)
        await expectPortError {
            _ = try await port.sendRequest(signed)
        }
    }

    @Test func macApplyRehearsalDoesNotMutateReceiveJSONOrProductionStore() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsMacExecutionShadowApplyTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let receiveJSON = rootURL.appendingPathComponent("receive.json")
        try Data("receive-before".utf8).write(to: receiveJSON)
        let local = CanonicalProductionTestFixtures.snapshot()
        let peer = CanonicalProductionTestFixtures.snapshot(
            node: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone")
        )
        let action = CanonicalApplyAction(
            kind: .objectTombstoneApply,
            source: .peer,
            target: CanonicalApplyTarget(objectID: "recording-01"),
            bridgeHint: .noPhysicalDelete,
            reason: "shadowTombstone"
        )
        let result = await CanonicalShadowApplyRehearsal().run(
            applyPlan: CanonicalApplyPlan(trigger: .manual, actions: [action]),
            localManifest: local.manifest,
            peerManifest: peer.manifest
        )

        #expect(result.calledApplySyncManifest == false)
        #expect(result.wroteProductionStore == false)
        #expect(result.tombstonePhysicalDelete == false)
        #expect((try? Data(contentsOf: receiveJSON)) == Data("receive-before".utf8))
    }

    @Test func macExecutionShadowDryRunReportHasNoRealNetworkOrProductionExecute() {
        let local = CanonicalProductionTestFixtures.snapshot()
        let peer = CanonicalProductionTestFixtures.snapshot(
            node: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone")
        )
        let result = CanonicalExecutionShadowPreparationRunner().run(
            configuration: .enabled(mode: .executionShadowDryRun),
            trigger: .macInventory,
            nodeRole: .mac,
            domain: .inventory,
            localSnapshot: local,
            peerSnapshot: peer,
            ports: MacCanonicalDryRunPorts.makePortSet(),
            syncRunID: "mac-execution-shadow-dry-run"
        )

        #expect(result.succeeded)
        #expect(result.report.productionAudit?.allowed == true)
        #expect(result.report.productionAudit?.nodeRole == .mac)
        #expect(result.report.productionAudit?.deniedSideEffects.contains(.networkRequest) == true)
        #expect(result.report.events.contains { $0.kind == .canonicalExecutionShadowProductionExecuteBlocked } == false)
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
