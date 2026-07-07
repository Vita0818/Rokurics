//
//  CanonicalProductionPortsTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalProductionPortsTests {
    @Test func dryRunPortSetDeclaresRequiredPortsAndCapabilities() {
        let ports = MacCanonicalDryRunPorts.makePortSet()
        let readiness = ports.readiness(generatedAt: CanonicalProductionTestFixtures.date(10))
        let summary = MacCanonicalDryRunCapabilityPort().summary(for: CanonicalProductionTestFixtures.node())

        #expect(readiness.missingPorts.isEmpty)
        #expect(readiness.hasAllRequiredDryRunPorts)
        #expect(readiness.dryRunOnly)
        #expect(summary.dryRunOnly)
        #expect(summary.capabilities.contains(.routeSigning))
        #expect(summary.supportedDomains.contains(.recordingAudio))
    }

    @Test func fileTransportUploadAndApplyPortsOnlyProjectSuppressedWork() async throws {
        let root = CanonicalRootToken("mac-production-root")
        let file = MacCanonicalDryRunFilePort(rootBindings: [root: "mac/production/root"])
        let reference = CanonicalFileReference(rootToken: root, logicalPathToken: "generated/recording-01/note.md", artifactKind: .noteMarkdown)
        let projection = try await file.projectWrite(
            CanonicalFileWriteIntent(reference: reference, bytes: Data("note".utf8), purpose: .generatedArtifact)
        )
        let descriptor = try await file.artifactDescriptor(for: CanonicalProductionTestFixtures.audioArtifact())

        #expect(projection.wouldWrite)
        #expect(projection.suppressedBecauseDryRun)
        #expect(projection.noPhysicalDelete)
        #expect(descriptor.logicalPathToken == "audio/recording-01.m4a")

        let transport = MacCanonicalDryRunTransportPort()
        let envelope = try await transport.buildEnvelopeDryRun(
            source: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"),
            destination: CanonicalProductionTestFixtures.node("mac-01"),
            route: .manifestExchange,
            body: Data("{}".utf8)
        )
        #expect(envelope.requiresSigning)
        #expect(envelope.requiresVerification)
        #expect(envelope.wouldSendNetwork == false)

        let object = CanonicalProductionTestFixtures.recording(audio: true)
        let upload = try await MacCanonicalDryRunUploadPort().projectUploadDryRun(
            object: object,
            artifact: CanonicalProductionTestFixtures.audioArtifact()
        )
        #expect(upload.wouldUpload == false)
        #expect(upload.suppressedBecauseDryRun)
        #expect(upload.mappedToLegacyUploadCapability)

        let action = CanonicalApplyAction(
            kind: .recordingMetadataApply,
            source: .peer,
            target: CanonicalApplyTarget(objectID: "recording-01"),
            reason: "peerMetadataNewer"
        )
        let apply = try await MacCanonicalDryRunApplyPort().projectApplyDryRun(action)
        #expect(apply.wouldWrite)
        #expect(apply.wouldCallApplySyncManifest == false)
        #expect(apply.suppressedBecauseDryRun)
    }

    @Test func unsafeLogicalTokensAreRejectedByDryRunFilePort() async {
        let root = CanonicalRootToken("mac-production-root")
        let file = MacCanonicalDryRunFilePort(rootBindings: [root: "mac/production/root"])

        do {
            _ = try await file.resolveLogicalToken("../escape.m4a", rootToken: root)
            Issue.record("Expected unsafe token rejection")
        } catch let error as CanonicalFileRuntimeError {
            #expect(error == .pathTraversalRejected("../escape.m4a"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func productionFilePortDefaultAndReleaseRemainBlocked() async throws {
        let rootURL = try makeTempRoot("mac-file-release")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let reference = CanonicalFileReference(rootToken: CanonicalRootToken("mac-production-root"), logicalPathToken: "metadata/recording-01.json")
        let intent = makeIntent(reference: reference, bytes: Data("blocked".utf8), purpose: .metadataBlob)
        let defaultPort = MacCanonicalProductionFilePort()

        #expect(defaultPort.isDryRunOnly)
        await expectProductionWriteBlocked(defaultPort, intent: intent)

        let releasePolicy = CanonicalProductionFilePortWritePolicy.explicitProductionRoot(
            explicitDebugInternalConfiguration: true,
            ownerApproved: true,
            manualConfirmation: true,
            allowProductionRootWrites: true,
            releaseDefaultBuild: true,
            testHarnessConfirmed: true
        )
        let releasePort = MacCanonicalProductionFilePort(productionRootURL: rootURL, policy: releasePolicy)

        #expect(releasePort.isDryRunOnly)
        #expect(releasePort.productionRootGate?.blockers.contains(.releaseDefaultBuild) == true)
        await expectProductionWriteBlocked(releasePort, intent: intent)
    }

    @Test func productionFilePortTestRootTrueWriteIsRootBoundAtomicAndRedacted() async throws {
        let rootURL = try makeTempRoot("mac-file-test-root")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let port = MacCanonicalProductionFilePort(testRootURL: rootURL)
        let reference = CanonicalFileReference(rootToken: CanonicalRootToken("mac-test-root"), logicalPathToken: "metadata/recording-01.json")
        let bytes = Data("{\"title\":\"recording\"}".utf8)
        let write = try await port.writeMetadata(makeIntent(reference: reference, bytes: bytes, purpose: .metadataBlob), rollbackCheckpoint: nil)
        let read = try await port.readMetadata(CanonicalProductionMetadataReadRequest(objectID: "recording-01", reference: reference))

        #expect(port.isDryRunOnly == false)
        #expect(write.disposition == .created)
        #expect(write.evidence.hashVerified)
        #expect(write.evidence.sizeVerified)
        #expect(read.bytes == bytes)
        let storedBytes = try Data(contentsOf: rootURL.appendingPathComponent("metadata/recording-01.json"))
        #expect(storedBytes == bytes)
        #expect(write.evidence.resolution.resolvedPathToken == "mac-test-root/metadata/recording-01.json")
        #expect(write.evidence.resolution.resolvedPathToken.contains(rootURL.path) == false)
        #expect(port.productionRootGate?.diagnosticsSummary.contains(rootURL.path) == false)
    }

    @Test func productionFilePortProductionRootRequiresConfirmationAndTestHarnessClone() async throws {
        let rootURL = try makeTempRoot("mac-file-production-gate")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let reference = CanonicalFileReference(rootToken: CanonicalRootToken("mac-production-root"), logicalPathToken: "metadata/recording-01.json")
        let intent = makeIntent(reference: reference, bytes: Data("blocked".utf8), purpose: .metadataBlob)

        let missingConfirmation = MacCanonicalProductionFilePort(
            productionRootURL: rootURL,
            policy: .explicitProductionRoot(
                explicitDebugInternalConfiguration: true,
                ownerApproved: true,
                manualConfirmation: false,
                allowProductionRootWrites: true,
                testHarnessConfirmed: true
            )
        )
        #expect(missingConfirmation.isDryRunOnly)
        #expect(missingConfirmation.productionRootGate?.blockers.contains(.missingManualConfirmation) == true)
        await expectProductionWriteBlocked(missingConfirmation, intent: intent)

        let missingHarness = MacCanonicalProductionFilePort(
            productionRootURL: rootURL,
            policy: .explicitProductionRoot(
                explicitDebugInternalConfiguration: true,
                ownerApproved: true,
                manualConfirmation: true,
                allowProductionRootWrites: true,
                testHarnessConfirmed: false
            )
        )
        #expect(missingHarness.isDryRunOnly)
        #expect(missingHarness.productionRootGate?.blockers.contains(.missingTestHarnessConfirmation) == true)
        await expectProductionWriteBlocked(missingHarness, intent: intent)

        let allowed = MacCanonicalProductionFilePort(
            productionRootURL: rootURL,
            policy: .explicitProductionRoot(
                explicitDebugInternalConfiguration: true,
                ownerApproved: true,
                manualConfirmation: true,
                allowProductionRootWrites: true,
                testHarnessConfirmed: true
            )
        )
        let write = try await allowed.writeMetadata(intent, rollbackCheckpoint: nil)
        #expect(allowed.isDryRunOnly == false)
        #expect(allowed.productionRootGate?.allowed == true)
        #expect(allowed.productionRootGate?.rootSafety?.testClonedRoot == true)
        #expect(write.evidence.hashVerified)
        let storedBytes = try Data(contentsOf: rootURL.appendingPathComponent("metadata/recording-01.json"))
        #expect(storedBytes == Data("blocked".utf8))
    }

    @Test func productionFilePortPathEscapeIsBlocked() async throws {
        let rootURL = try makeTempRoot("mac-file-escape")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let port = MacCanonicalProductionFilePort(testRootURL: rootURL)

        do {
            _ = try await port.resolveLogicalToken("../escape.json", rootToken: CanonicalRootToken("mac-test-root"))
            Issue.record("Expected path traversal to be rejected")
        } catch let error as CanonicalFileRuntimeError {
            #expect(error == .pathTraversalRejected("../escape.json"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func productionFilePortRollbackRestoresOldBytesAndDeletesNewFile() async throws {
        let rootURL = try makeTempRoot("mac-file-rollback")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let port = MacCanonicalProductionFilePort(testRootURL: rootURL)
        let reference = CanonicalFileReference(rootToken: CanonicalRootToken("mac-test-root"), logicalPathToken: "metadata/recording-01.json")
        let oldBytes = Data("old".utf8)
        let newBytes = Data("new".utf8)

        _ = try await port.writeMetadata(makeIntent(reference: reference, bytes: oldBytes, purpose: .metadataBlob), rollbackCheckpoint: nil)
        _ = try await port.writeMetadata(
            makeIntent(reference: reference, bytes: newBytes, purpose: .metadataBlob),
            rollbackCheckpoint: CanonicalRollbackCheckpoint(checkpointID: "checkpoint-existing", domain: .fileRuntime)
        )
        let rollbackExisting = try await port.rollbackWrite(CanonicalProductionFileRollbackRequest(checkpointID: "checkpoint-existing", reference: reference))
        let restored = try await port.readMetadata(CanonicalProductionMetadataReadRequest(objectID: "recording-01", reference: reference))
        #expect(rollbackExisting.succeeded)
        #expect(restored.bytes == oldBytes)

        let newReference = CanonicalFileReference(rootToken: CanonicalRootToken("mac-test-root"), logicalPathToken: "metadata/recording-02.json")
        _ = try await port.writeMetadata(
            makeIntent(reference: newReference, bytes: newBytes, purpose: .metadataBlob),
            rollbackCheckpoint: CanonicalRollbackCheckpoint(checkpointID: "checkpoint-new", domain: .fileRuntime)
        )
        let rollbackNew = try await port.rollbackWrite(CanonicalProductionFileRollbackRequest(checkpointID: "checkpoint-new", reference: newReference))
        #expect(rollbackNew.succeeded)
        #expect(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("metadata/recording-02.json").path) == false)
    }

    @Test func productionFilePortPostconditionAndDomainRoutesAreVerified() async throws {
        let rootURL = try makeTempRoot("mac-file-domains")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let port = MacCanonicalProductionFilePort(testRootURL: rootURL)
        let routes: [(CanonicalFileReference, CanonicalFilePurpose)] = [
            (CanonicalFileReference(rootToken: CanonicalRootToken("mac-test-root"), logicalPathToken: "recordingMetadata/recording-01.json"), .metadataBlob),
            (CanonicalFileReference(rootToken: CanonicalRootToken("mac-test-root"), logicalPathToken: "libraryMetadata/folders/folder-01.json"), .metadataBlob),
            (CanonicalFileReference(rootToken: CanonicalRootToken("mac-test-root"), logicalPathToken: "generatedArtifacts/recording-01/note.md", artifactKind: .noteMarkdown), .generatedArtifact)
        ]

        for (reference, purpose) in routes {
            let bytes = Data(reference.logicalPathToken.utf8)
            let intent = makeIntent(reference: reference, bytes: bytes, purpose: purpose)
            let write = try await port.writeMetadata(intent, rollbackCheckpoint: nil)
            let verification = try await port.verifyArtifact(CanonicalProductionArtifactVerifyRequest(reference: reference, expectedContentHash: intent.expectedContentHash, expectedByteSize: intent.expectedByteSize))
            #expect(write.evidence.hashVerified)
            #expect(verification.hashVerified)
            #expect(verification.sizeVerified)
        }

        do {
            let reference = routes[0].0
            _ = try await port.verifyArtifact(CanonicalProductionArtifactVerifyRequest(reference: reference, expectedContentHash: CanonicalHash.sha256String("wrong")))
            Issue.record("Expected postcondition hash mismatch")
        } catch let error as CanonicalFileRuntimeError {
            if case .postWriteHashMismatch = error {
                #expect(true)
            } else {
                Issue.record("Unexpected postcondition error \(error)")
            }
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func oldKernelSwitchMappingUnaffectedByProductionFilePortGate() {
        let result = CanonicalKernelSwitchConfiguration.default.resolve()

        #expect(result.effectiveMode == .oldKernel)
        #expect(result.effectiveConfiguration.syncRuntimeConfiguration.mode == .disabled)
        #expect(result.effectiveConfiguration.applyRuntimeConfiguration.mode == .disabled)
    }

    private func makeTempRoot(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rokurics-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeIntent(reference: CanonicalFileReference, bytes: Data, purpose: CanonicalFilePurpose) -> CanonicalFileWriteIntent {
        CanonicalFileWriteIntent(
            reference: reference,
            bytes: bytes,
            purpose: purpose,
            expectedContentHash: InMemoryCanonicalFileStore.hash(bytes, policy: .sha256),
            expectedByteSize: Int64(bytes.count),
            conflictPolicy: .replace
        )
    }

    private func expectProductionWriteBlocked(_ port: MacCanonicalProductionFilePort, intent: CanonicalFileWriteIntent) async {
        do {
            _ = try await port.writeMetadata(intent, rollbackCheckpoint: nil)
            Issue.record("Expected production file write to be blocked")
        } catch let error as CanonicalProductionPortError {
            if case .productionMutationAttempted = error {
                #expect(true)
            } else {
                Issue.record("Unexpected production port error \(error)")
            }
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }
}
