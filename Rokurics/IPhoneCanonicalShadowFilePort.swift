//
//  IPhoneCanonicalShadowFilePort.swift
//  Rokurics
//
//  Created by Codex on 2026/6/2.
//

import Foundation

actor IPhoneCanonicalShadowFilePort: CanonicalProductionFilePort {
    nonisolated let isDryRunOnly = false
    nonisolated let capabilities: [CanonicalProductionCapability] = [
        .rootBoundFileAccess,
        .rootBoundRead,
        .rootBoundWrite,
        .logicalTokenValidation,
        .containmentVerification,
        .atomicWriteExecution,
        .hashSizeVerification,
        .streamingHash,
        .rollbackCheckpoint,
        .noPhysicalDelete
    ]
    nonisolated let shadowRootKind: CanonicalShadowRootKind
    nonisolated let rootToken: CanonicalRootToken

    private let wrapped: IPhoneCanonicalProductionFilePort

    init(binding: CanonicalShadowRootBinding, fileManager: FileManager = .default) throws {
        let rootURL = try binding.validatedShadowRootURL()
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        self.shadowRootKind = binding.rootKind
        self.rootToken = binding.rootToken
        self.wrapped = IPhoneCanonicalProductionFilePort(
            testRootURL: rootURL,
            rootToken: binding.rootToken,
            fileManager: fileManager
        )
    }

    func resolveRootBound(_ reference: CanonicalFileReference) async throws -> CanonicalPathResolutionResult {
        try await wrapped.resolveRootBound(reference)
    }

    func readMetadata(_ request: CanonicalProductionMetadataReadRequest) async throws -> CanonicalProductionFileReadResult {
        try await wrapped.readMetadata(request)
    }

    func writeMetadata(_ intent: CanonicalFileWriteIntent, rollbackCheckpoint: CanonicalRollbackCheckpoint?) async throws -> CanonicalProductionFileWriteResult {
        try await wrapped.writeMetadata(intent, rollbackCheckpoint: rollbackCheckpoint)
    }

    func readArtifact(_ request: CanonicalProductionArtifactReadRequest) async throws -> CanonicalProductionFileReadResult {
        try await wrapped.readArtifact(request)
    }

    func writeArtifactAtomic(_ intent: CanonicalFileWriteIntent, rollbackCheckpoint: CanonicalRollbackCheckpoint?) async throws -> CanonicalProductionFileWriteResult {
        try await wrapped.writeArtifactAtomic(intent, rollbackCheckpoint: rollbackCheckpoint)
    }

    func verifyArtifact(_ request: CanonicalProductionArtifactVerifyRequest) async throws -> CanonicalProductionFileVerificationEvidence {
        try await wrapped.verifyArtifact(request)
    }

    func markTombstone(_ request: CanonicalProductionTombstoneRequest) async throws -> CanonicalProductionFileWriteResult {
        try await wrapped.markTombstone(request)
    }

    func listKnownArtifacts(rootToken: CanonicalRootToken, objectID: String?) async throws -> [CanonicalProductionArtifactDescriptor] {
        try await wrapped.listKnownArtifacts(rootToken: rootToken, objectID: objectID)
    }

    func listKnownObjects(rootToken: CanonicalRootToken) async throws -> [String] {
        try await wrapped.listKnownObjects(rootToken: rootToken)
    }

    func computeHash(_ request: CanonicalProductionHashRequest) async throws -> CanonicalProductionHashResult {
        try await wrapped.computeHash(request)
    }

    func rollbackWrite(_ request: CanonicalProductionFileRollbackRequest) async throws -> CanonicalRollbackResult {
        try await wrapped.rollbackWrite(request)
    }

    func metadataSnapshot(objectID: String) async throws -> Data? {
        try await wrapped.metadataSnapshot(objectID: objectID)
    }

    func artifactDescriptor(for artifact: CanonicalArtifact) async throws -> CanonicalProductionArtifactDescriptor {
        try await wrapped.artifactDescriptor(for: artifact)
    }

    func validateRead(reference: CanonicalFileReference) async throws -> CanonicalProductionReadProjection {
        try await wrapped.validateRead(reference: reference)
    }

    func resolveLogicalToken(_ token: String, rootToken: CanonicalRootToken) async throws -> CanonicalPathResolutionResult {
        try await wrapped.resolveLogicalToken(token, rootToken: rootToken)
    }

    func verifyContainment(_ reference: CanonicalFileReference) async throws -> Bool {
        try await wrapped.verifyContainment(reference)
    }

    func projectWrite(_ intent: CanonicalFileWriteIntent) async throws -> CanonicalProductionWriteIntentProjection {
        var projection = try await wrapped.projectWrite(intent)
        projection.reason = "iphoneShadowRootWriteAvailable"
        projection.suppressedBecauseDryRun = false
        return projection
    }
}
