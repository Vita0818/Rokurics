//
//  IPhoneCanonicalProductionFilePort.swift
//  Rokurics
//
//  Created by Codex on 2026/6/2.
//

import Foundation

actor IPhoneCanonicalProductionFilePort: CanonicalProductionFilePort {
    private enum Mode: Sendable {
        case disabled
        case blocked(rootToken: CanonicalRootToken, gate: CanonicalProductionFilePortGateResult)
        case testRoot(rootToken: CanonicalRootToken, rootURL: URL)
        case productionRoot(rootToken: CanonicalRootToken, rootURL: URL, gate: CanonicalProductionFilePortGateResult)
    }

    nonisolated let isDryRunOnly: Bool
    nonisolated let capabilities: [CanonicalProductionCapability]
    nonisolated let rootMode: CanonicalProductionFilePortRootMode
    nonisolated let productionRootGate: CanonicalProductionFilePortGateResult?

    private let mode: Mode
    private let fileManager: FileManager
    private var rollbackCheckpoints: [String: CanonicalFileRollbackCheckpoint] = [:]

    init() {
        let defaultCapabilities = Self.capabilities(writable: false)
        mode = .disabled
        fileManager = .default
        isDryRunOnly = defaultCapabilities.contains(.dryRunOnly)
        rootMode = .disabled
        productionRootGate = nil
        capabilities = defaultCapabilities
    }

    init(testRootURL: URL, rootToken: CanonicalRootToken = CanonicalRootToken("iphone-test-root"), fileManager: FileManager = .default) {
        let rootURL = testRootURL.standardizedFileURL
        let gate = CanonicalProductionFilePortWritePolicy.explicitTestRoot().evaluate(rootURL: rootURL, fileManager: fileManager)
        mode = gate.allowed
            ? .testRoot(rootToken: rootToken, rootURL: rootURL)
            : .blocked(rootToken: rootToken, gate: gate)
        self.fileManager = fileManager
        isDryRunOnly = !gate.allowed
        rootMode = .testRoot
        productionRootGate = gate
        capabilities = Self.capabilities(writable: gate.allowed)
    }

    init(
        productionRootURL: URL,
        rootToken: CanonicalRootToken = CanonicalRootToken("iphone-production-root"),
        policy: CanonicalProductionFilePortWritePolicy = .disabled,
        fileManager: FileManager = .default
    ) {
        let rootURL = productionRootURL.standardizedFileURL
        let gate = policy.evaluate(rootURL: rootURL, fileManager: fileManager)
        mode = gate.allowed
            ? .productionRoot(rootToken: rootToken, rootURL: rootURL, gate: gate)
            : .blocked(rootToken: rootToken, gate: gate)
        self.fileManager = fileManager
        isDryRunOnly = !gate.allowed
        rootMode = .productionRootExplicit
        productionRootGate = gate
        capabilities = Self.capabilities(writable: gate.allowed)
    }

    private nonisolated static func capabilities(writable: Bool) -> [CanonicalProductionCapability] {
        if writable {
            return [
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
        }
        return [
            .dryRunOnly,
            .rootBoundFileAccess,
            .logicalTokenValidation,
            .containmentVerification,
            .hashSizeVerification,
            .noPhysicalDelete
        ]
    }

    func resolveRootBound(_ reference: CanonicalFileReference) async throws -> CanonicalPathResolutionResult {
        try resolvedURL(for: reference).resolution
    }

    func readMetadata(_ request: CanonicalProductionMetadataReadRequest) async throws -> CanonicalProductionFileReadResult {
        try read(reference: request.reference, purpose: .metadataBlob, expectedHash: nil, expectedByteSize: nil)
    }

    func writeMetadata(_ intent: CanonicalFileWriteIntent, rollbackCheckpoint: CanonicalRollbackCheckpoint?) async throws -> CanonicalProductionFileWriteResult {
        try write(intent, rollbackCheckpoint: rollbackCheckpoint)
    }

    func readArtifact(_ request: CanonicalProductionArtifactReadRequest) async throws -> CanonicalProductionFileReadResult {
        try read(
            reference: request.reference,
            purpose: .generatedArtifact,
            expectedHash: request.expectedContentHash,
            expectedByteSize: request.expectedByteSize
        )
    }

    func writeArtifactAtomic(_ intent: CanonicalFileWriteIntent, rollbackCheckpoint: CanonicalRollbackCheckpoint?) async throws -> CanonicalProductionFileWriteResult {
        try write(intent, rollbackCheckpoint: rollbackCheckpoint)
    }

    func verifyArtifact(_ request: CanonicalProductionArtifactVerifyRequest) async throws -> CanonicalProductionFileVerificationEvidence {
        let resolved = try resolvedURL(for: request.reference)
        let data = try readBytes(at: resolved.url)
        let actualHash = InMemoryCanonicalFileStore.hash(data, policy: .sha256)
        let actualSize = Int64(data.count)
        if let expectedSize = request.expectedByteSize, expectedSize != actualSize {
            throw CanonicalFileRuntimeError.postWriteSizeMismatch(expected: expectedSize, actual: actualSize)
        }
        if let expectedHash = request.expectedContentHash,
           let actualHash,
           expectedHash != actualHash {
            throw CanonicalFileRuntimeError.postWriteHashMismatch(expected: expectedHash.value, actual: actualHash.value)
        }
        return evidence(
            reference: request.reference,
            resolution: resolved.resolution,
            expectedHash: request.expectedContentHash,
            actualHash: actualHash,
            expectedByteSize: request.expectedByteSize,
            actualByteSize: actualSize,
            streaming: request.requireStreamingHash
        )
    }

    func markTombstone(_ request: CanonicalProductionTombstoneRequest) async throws -> CanonicalProductionFileWriteResult {
        let marker = try CanonicalTransportJSON.encode([
            "tombstoned": "true",
            "reason": request.reason
        ])
        let intent = CanonicalFileWriteIntent(
            reference: request.reference,
            bytes: marker,
            purpose: .tombstoneMarker,
            expectedContentHash: InMemoryCanonicalFileStore.hash(marker, policy: .sha256),
            expectedByteSize: Int64(marker.count),
            conflictPolicy: .replace,
            metadataBlob: CanonicalMetadataBlob([
                "tombstoned": "true",
                "reason": request.reason
            ])
        )
        return try write(intent, rollbackCheckpoint: nil, forcedDisposition: .tombstoneMarked)
    }

    func listKnownArtifacts(rootToken: CanonicalRootToken, objectID: String?) async throws -> [CanonicalProductionArtifactDescriptor] {
        let root = try rootURL(for: rootToken)
        let urls = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return urls
            .filter { !$0.hasDirectoryPath }
            .map { url in
                let fileName = url.lastPathComponent
                let artifactID = objectID.map { "\($0):\(fileName)" } ?? fileName
                return CanonicalProductionArtifactDescriptor(
                    artifactID: artifactID,
                    objectID: objectID ?? "unknown-recording",
                    kind: .noteMarkdown,
                    logicalPathToken: fileName,
                    logicalName: fileName,
                    byteSize: (try? fileSize(at: url)),
                    availability: .available
                )
            }
    }

    func listKnownObjects(rootToken: CanonicalRootToken) async throws -> [String] {
        let root = try rootURL(for: rootToken)
        return try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "object") }
            .sorted()
    }

    func computeHash(_ request: CanonicalProductionHashRequest) async throws -> CanonicalProductionHashResult {
        let resolved = try resolvedURL(for: request.reference)
        let data = try readBytes(at: resolved.url)
        let hash = InMemoryCanonicalFileStore.hash(data, policy: .sha256) ?? CanonicalHash("")
        let size = Int64(data.count)
        let evidence = evidence(
            reference: request.reference,
            resolution: resolved.resolution,
            expectedHash: hash,
            actualHash: hash,
            expectedByteSize: request.expectedByteSize,
            actualByteSize: size,
            streaming: request.requireStreaming
        )
        return CanonicalProductionHashResult(contentHash: hash, byteSize: size, computedStreaming: request.requireStreaming, evidence: evidence)
    }

    func rollbackWrite(_ request: CanonicalProductionFileRollbackRequest) async throws -> CanonicalRollbackResult {
        guard let checkpoint = rollbackCheckpoints[request.checkpointID] else {
            return CanonicalRollbackResult(
                planID: request.checkpointID,
                succeeded: false,
                failures: [CanonicalRollbackFailure(actionID: request.checkpointID, reason: "checkpointMissing")]
            )
        }
        guard checkpoint.reference == request.reference else {
            return CanonicalRollbackResult(
                planID: request.checkpointID,
                succeeded: false,
                failures: [CanonicalRollbackFailure(actionID: request.checkpointID, reason: "checkpointReferenceMismatch")]
            )
        }
        do {
            try restore(checkpoint: checkpoint)
            let verified = try rollbackVerified(checkpoint: checkpoint)
            return CanonicalRollbackResult(
                planID: request.checkpointID,
                succeeded: verified,
                completedActionIDs: verified ? [request.checkpointID] : [],
                failures: verified ? [] : [
                    CanonicalRollbackFailure(actionID: request.checkpointID, reason: "rollbackVerificationFailed")
                ]
            )
        } catch {
            return CanonicalRollbackResult(
                planID: request.checkpointID,
                succeeded: false,
                failures: [CanonicalRollbackFailure(actionID: request.checkpointID, reason: "rollbackFailed")]
            )
        }
    }

    func metadataSnapshot(objectID: String) async throws -> Data? {
        guard let rootToken = activeRootToken else {
            return nil
        }
        let safeObjectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        let reference = CanonicalFileReference(rootToken: rootToken, logicalPathToken: "metadata/\(safeObjectID).json")
        return try? readBytes(at: resolvedURL(for: reference).url)
    }

    func artifactDescriptor(for artifact: CanonicalArtifact) async throws -> CanonicalProductionArtifactDescriptor {
        CanonicalProductionArtifactDescriptor(artifact: artifact)
    }

    func validateRead(reference: CanonicalFileReference) async throws -> CanonicalProductionReadProjection {
        let resolved = try resolvedURL(for: reference)
        return CanonicalProductionReadProjection(
            reference: reference,
            wouldReadBytes: fileManager.fileExists(atPath: resolved.url.path),
            byteSize: try? fileSize(at: resolved.url),
            dryRun: isDryRunOnly
        )
    }

    func resolveLogicalToken(_ token: String, rootToken: CanonicalRootToken) async throws -> CanonicalPathResolutionResult {
        try resolvedURL(for: CanonicalFileReference(rootToken: rootToken, logicalPathToken: token)).resolution
    }

    func verifyContainment(_ reference: CanonicalFileReference) async throws -> Bool {
        try resolvedURL(for: reference).resolution.isInsideRoot
    }

    func projectWrite(_ intent: CanonicalFileWriteIntent) async throws -> CanonicalProductionWriteIntentProjection {
        _ = try resolvedURL(for: intent.reference)
        return CanonicalProductionWriteIntentProjection(
            reference: intent.reference,
            purpose: intent.purpose,
            wouldWrite: !isDryRunOnly,
            suppressedBecauseDryRun: isDryRunOnly,
            noPhysicalDelete: true,
            byteSize: Int64(intent.bytes.count),
            contentHash: InMemoryCanonicalFileStore.hash(intent.bytes, policy: intent.hashPolicy),
            disposition: nil,
            reason: projectionReason
        )
    }

    private func write(
        _ intent: CanonicalFileWriteIntent,
        rollbackCheckpoint: CanonicalRollbackCheckpoint?,
        forcedDisposition: CanonicalFileWriteDisposition? = nil
    ) throws -> CanonicalProductionFileWriteResult {
        guard !isDryRunOnly else {
            throw CanonicalProductionPortError.productionMutationAttempted("iphoneProductionFilePortDisabled")
        }
        let resolved = try resolvedURL(for: intent.reference)
        let actualHash = InMemoryCanonicalFileStore.hash(intent.bytes, policy: intent.hashPolicy)
        try validate(intent: intent, actualHash: actualHash)
        let existed = fileManager.fileExists(atPath: resolved.url.path)
        if let rollbackCheckpoint {
            let previousBytes = existed ? try Data(contentsOf: resolved.url) : nil
            rollbackCheckpoints[rollbackCheckpoint.checkpointID] = CanonicalFileRollbackCheckpoint(
                reference: intent.reference,
                previousBytes: previousBytes,
                existedBeforeWrite: existed
            )
        }
        try validateConflictPolicy(intent: intent, existingURL: existed ? resolved.url : nil, newHash: actualHash)
        let stored: Data
        let storedHash: CanonicalHash?
        do {
            try fileManager.createDirectory(at: resolved.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try intent.bytes.write(to: resolved.url, options: .atomic)
            stored = try readBytes(at: resolved.url)
            storedHash = InMemoryCanonicalFileStore.hash(stored, policy: intent.hashPolicy)
            try validatePostWrite(intent: intent, storedBytes: stored, storedHash: storedHash)
        } catch {
            if let checkpointID = rollbackCheckpoint?.checkpointID,
               let checkpoint = rollbackCheckpoints[checkpointID] {
                try? restore(checkpoint: checkpoint)
            }
            throw error
        }
        return CanonicalProductionFileWriteResult(
            disposition: forcedDisposition ?? (existed ? .replaced : .created),
            purpose: intent.purpose,
            evidence: evidence(
                reference: intent.reference,
                resolution: resolved.resolution,
                expectedHash: intent.expectedContentHash,
                actualHash: storedHash,
                expectedByteSize: intent.expectedByteSize,
                actualByteSize: Int64(stored.count)
            ),
            rollbackCheckpointID: rollbackCheckpoint?.checkpointID,
            tombstoned: intent.purpose == .tombstoneMarker
        )
    }

    private func read(
        reference: CanonicalFileReference,
        purpose: CanonicalFilePurpose,
        expectedHash: CanonicalHash?,
        expectedByteSize: Int64?
    ) throws -> CanonicalProductionFileReadResult {
        guard !isDryRunOnly else {
            throw CanonicalProductionPortError.productionMutationAttempted("iphoneProductionFilePortReadDisabled")
        }
        let resolved = try resolvedURL(for: reference)
        let bytes = try readBytes(at: resolved.url)
        let actualHash = InMemoryCanonicalFileStore.hash(bytes, policy: .sha256)
        let actualSize = Int64(bytes.count)
        if let expectedByteSize, expectedByteSize != actualSize {
            throw CanonicalFileRuntimeError.postWriteSizeMismatch(expected: expectedByteSize, actual: actualSize)
        }
        if let expectedHash, let actualHash, expectedHash != actualHash {
            throw CanonicalFileRuntimeError.postWriteHashMismatch(expected: expectedHash.value, actual: actualHash.value)
        }
        return CanonicalProductionFileReadResult(
            bytes: bytes,
            purpose: purpose,
            evidence: evidence(
                reference: reference,
                resolution: resolved.resolution,
                expectedHash: expectedHash,
                actualHash: actualHash,
                expectedByteSize: expectedByteSize,
                actualByteSize: actualSize
            ),
            metadataBlob: purpose == .metadataBlob ? CanonicalMetadataBlob(["source": "iphoneProductionFilePort"]) : nil,
            tombstoned: purpose == .tombstoneMarker
        )
    }

    private func resolvedURL(for reference: CanonicalFileReference) throws -> (url: URL, resolution: CanonicalPathResolutionResult) {
        let root = try rootURL(for: reference.rootToken)
        let token = try validatedLogicalToken(reference.logicalPathToken)
        let url = root.appendingPathComponent(token, isDirectory: false).standardizedFileURL
        guard isInsideRoot(url, root: root) else {
            throw CanonicalProductionPortError.pathEscapeRisk("iphoneRootEscape")
        }
        return (
            url,
            CanonicalPathResolutionResult(
                rootToken: reference.rootToken,
                logicalPathToken: token,
                resolvedPathToken: "\(reference.rootToken.rawValue)/\(token)",
                isInsideRoot: true
            )
        )
    }

    private func rootURL(for rootToken: CanonicalRootToken) throws -> URL {
        let binding: (CanonicalRootToken, URL)?
        switch mode {
        case let .testRoot(boundToken, rootURL):
            binding = (boundToken, rootURL)
        case let .productionRoot(boundToken, rootURL, _):
            binding = (boundToken, rootURL)
        case let .blocked(_, gate):
            throw CanonicalProductionPortError.productionMutationAttempted("iphoneProductionFilePortGateBlocked:\(gate.blockers.map(\.rawValue).joined(separator: ","))")
        case .disabled:
            throw CanonicalProductionPortError.productionMutationAttempted("iphoneProductionFilePortDisabled")
        }
        guard let (boundToken, rootURL) = binding,
              boundToken == rootToken else {
            throw CanonicalFileRuntimeError.rootNotBound(rootToken.rawValue)
        }
        return rootURL
    }

    private func validatedLogicalToken(_ token: String) throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CanonicalFileRuntimeError.invalidPathToken(token)
        }
        guard !trimmed.hasPrefix("/") else {
            throw CanonicalFileRuntimeError.absolutePathRejected(token)
        }
        guard !trimmed.contains("://") else {
            throw CanonicalFileRuntimeError.schemeURLRejected(token)
        }
        guard !trimmed.contains("\\") else {
            throw CanonicalFileRuntimeError.backslashTraversalRejected(token)
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CanonicalFileRuntimeError.pathTraversalRejected(token)
        }
        guard let safe = CanonicalProjectionContract.safeLogicalPathToken(trimmed) else {
            throw CanonicalFileRuntimeError.invalidPathToken(token)
        }
        return safe
    }

    private func validate(intent: CanonicalFileWriteIntent, actualHash: CanonicalHash?) throws {
        if let expectedByteSize = intent.expectedByteSize,
           expectedByteSize != Int64(intent.bytes.count) {
            throw CanonicalFileRuntimeError.preWriteSizeMismatch(expected: expectedByteSize, actual: Int64(intent.bytes.count))
        }
        if let expectedContentHash = intent.expectedContentHash,
           let actualHash,
           expectedContentHash != actualHash {
            throw CanonicalFileRuntimeError.preWriteHashMismatch(expected: expectedContentHash.value, actual: actualHash.value)
        }
    }

    private func validateConflictPolicy(intent: CanonicalFileWriteIntent, existingURL: URL?, newHash: CanonicalHash?) throws {
        guard let existingURL else {
            return
        }
        let existingBytes = try readBytes(at: existingURL)
        let existingHash = InMemoryCanonicalFileStore.hash(existingBytes, policy: intent.hashPolicy)
        if let expectedExistingHash = intent.expectedExistingHash,
           expectedExistingHash != existingHash {
            throw CanonicalFileRuntimeError.existingHashMismatch(expected: expectedExistingHash.value, actual: existingHash?.value)
        }
        switch intent.conflictPolicy {
        case .replace:
            return
        case .replaceIfExistingHashMatches:
            guard intent.expectedExistingHash != nil else {
                throw CanonicalFileRuntimeError.existingHashMismatch(expected: "required", actual: existingHash?.value)
            }
        case .idempotentIfSameContent, .noOverwrite:
            guard let existingHash,
                  let newHash,
                  existingHash == newHash,
                  existingBytes.count == intent.bytes.count else {
                throw CanonicalFileRuntimeError.conflict(intent.reference.logicalPathToken)
            }
        }
    }

    private func validatePostWrite(intent: CanonicalFileWriteIntent, storedBytes: Data, storedHash: CanonicalHash?) throws {
        if let expectedByteSize = intent.expectedByteSize,
           expectedByteSize != Int64(storedBytes.count) {
            throw CanonicalFileRuntimeError.postWriteSizeMismatch(expected: expectedByteSize, actual: Int64(storedBytes.count))
        }
        if let expectedHash = intent.expectedContentHash,
           let storedHash,
           expectedHash != storedHash {
            throw CanonicalFileRuntimeError.postWriteHashMismatch(expected: expectedHash.value, actual: storedHash.value)
        }
    }

    private func evidence(
        reference: CanonicalFileReference,
        resolution: CanonicalPathResolutionResult,
        expectedHash: CanonicalHash?,
        actualHash: CanonicalHash?,
        expectedByteSize: Int64?,
        actualByteSize: Int64?,
        streaming: Bool = false
    ) -> CanonicalProductionFileVerificationEvidence {
        CanonicalProductionFileVerificationEvidence(
            reference: reference,
            resolution: resolution,
            expectedHash: expectedHash,
            actualHash: actualHash,
            expectedByteSize: expectedByteSize,
            actualByteSize: actualByteSize,
            computedStreaming: streaming
        )
    }

    private func readBytes(at url: URL) throws -> Data {
        guard fileManager.fileExists(atPath: url.path) else {
            throw CanonicalFileRuntimeError.fileNotFound(url.lastPathComponent)
        }
        return try Data(contentsOf: url)
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let size = try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.int64Value ?? 0
    }

    private func isInsideRoot(_ url: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private var activeRootToken: CanonicalRootToken? {
        switch mode {
        case let .testRoot(rootToken, _), let .productionRoot(rootToken, _, _):
            return rootToken
        case .disabled, .blocked(_, _):
            return nil
        }
    }

    private var projectionReason: String {
        if isDryRunOnly {
            if let gate = productionRootGate, !gate.allowed {
                return "iphoneProductionFilePortGateBlocked:\(gate.blockers.map(\.rawValue).joined(separator: ","))"
            }
            return "iphoneProductionFilePortDisabled"
        }
        switch mode {
        case .testRoot(_, _):
            return "iphoneTestRootWriteAvailable"
        case .productionRoot(_, _, _):
            return "iphoneProductionRootGatedWriteAvailable"
        case .disabled, .blocked(_, _):
            return "iphoneProductionFilePortDisabled"
        }
    }

    private func restore(checkpoint: CanonicalFileRollbackCheckpoint) throws {
        let resolved = try resolvedURL(for: checkpoint.reference)
        if checkpoint.existedBeforeWrite, let previousBytes = checkpoint.previousBytes {
            try fileManager.createDirectory(at: resolved.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try previousBytes.write(to: resolved.url, options: .atomic)
        } else if fileManager.fileExists(atPath: resolved.url.path) {
            try fileManager.removeItem(at: resolved.url)
        }
    }

    private func rollbackVerified(checkpoint: CanonicalFileRollbackCheckpoint) throws -> Bool {
        let resolved = try resolvedURL(for: checkpoint.reference)
        let exists = fileManager.fileExists(atPath: resolved.url.path)
        if !checkpoint.existedBeforeWrite {
            return !exists
        }
        guard exists, let previousBytes = checkpoint.previousBytes else {
            return false
        }
        return try Data(contentsOf: resolved.url) == previousBytes
    }
}

private struct CanonicalFileRollbackCheckpoint: Sendable {
    var reference: CanonicalFileReference
    var previousBytes: Data?
    var existedBeforeWrite: Bool
}
