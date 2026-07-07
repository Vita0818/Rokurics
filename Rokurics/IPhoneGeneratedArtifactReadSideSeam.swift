//
//  IPhoneGeneratedArtifactReadSideSeam.swift
//  Rokurics
//
//  Created by Codex on 2026/6/5.
//

import Foundation

struct IPhoneGeneratedArtifactReadSideSeam {
    var configuration: CanonicalGeneratedArtifactReadSideConfiguration

    init(configuration: CanonicalGeneratedArtifactReadSideConfiguration = .disabled) {
        self.configuration = configuration
    }

    func evaluate(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        trigger: CanonicalSyncPlanTrigger,
        syncRunID: String?
    ) -> CanonicalGeneratedArtifactReadSideEvaluationResult {
        let legacySnapshot = legacySnapshot(
            localInventory: localInventory,
            peerInventory: peerInventory
        )
        let canonicalSnapshot = CanonicalGeneratedArtifactReadProjection.snapshot(
            source: .canonical,
            localManifest: localInventory.canonicalManifest,
            peerManifest: peerInventory.canonicalManifest
        )
        return evaluate(
            legacySnapshot: legacySnapshot,
            canonicalSnapshot: canonicalSnapshot,
            trigger: trigger,
            syncRunID: syncRunID
        )
    }

    func evaluate(
        legacySnapshot: CanonicalGeneratedArtifactReadSnapshot?,
        canonicalSnapshot: CanonicalGeneratedArtifactReadSnapshot?,
        trigger: CanonicalSyncPlanTrigger,
        syncRunID: String?
    ) -> CanonicalGeneratedArtifactReadSideEvaluationResult {
        CanonicalGeneratedArtifactReadSideEvaluator().evaluate(
            configuration: configuration,
            legacySnapshot: legacySnapshot,
            canonicalSnapshot: canonicalSnapshot,
            trigger: trigger,
            nodeRole: .iPhone,
            syncRunID: syncRunID
        )
    }

    func readSource(
        sourceConfiguration: CanonicalGeneratedArtifactReadSourceConfiguration = .legacy,
        legacySnapshot: CanonicalGeneratedArtifactReadSnapshot,
        canonicalSnapshot: CanonicalGeneratedArtifactReadSnapshot?,
        writeSideEvidence: CanonicalGeneratedArtifactWriteSideEvidenceLinkage = .missing,
        trigger: CanonicalSyncPlanTrigger,
        syncRunID: String?,
        canonicalReadFailureReason: String? = nil,
        matrix: CanonicalMigrationDomainMatrix = .v824GeneratedArtifactsStagedCanary(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        )
    ) -> CanonicalGeneratedArtifactReadSourceResult {
        CanonicalGeneratedArtifactReadSourceProvider(
            configuration: sourceConfiguration,
            matrix: matrix
        ).read(
            legacySnapshot: legacySnapshot,
            canonicalSnapshot: canonicalSnapshot,
            writeSideEvidence: writeSideEvidence,
            trigger: trigger,
            nodeRole: .iPhone,
            syncRunID: syncRunID,
            canonicalReadFailureReason: canonicalReadFailureReason
        )
    }

    func readSource(
        sourceConfiguration: CanonicalGeneratedArtifactReadSourceConfiguration = .legacy,
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        writeSideEvidence: CanonicalGeneratedArtifactWriteSideEvidenceLinkage = .missing,
        trigger: CanonicalSyncPlanTrigger,
        syncRunID: String?,
        canonicalReadFailureReason: String? = nil,
        matrix: CanonicalMigrationDomainMatrix = .v824GeneratedArtifactsStagedCanary(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        )
    ) -> CanonicalGeneratedArtifactReadSourceResult {
        let legacySnapshot = legacySnapshot(
            localInventory: localInventory,
            peerInventory: peerInventory
        )
        let canonicalSnapshot = CanonicalGeneratedArtifactReadProjection.snapshot(
            source: .canonical,
            localManifest: localInventory.canonicalManifest,
            peerManifest: peerInventory.canonicalManifest
        )
        return readSource(
            sourceConfiguration: sourceConfiguration,
            legacySnapshot: legacySnapshot,
            canonicalSnapshot: canonicalSnapshot,
            writeSideEvidence: writeSideEvidence,
            trigger: trigger,
            syncRunID: syncRunID,
            canonicalReadFailureReason: canonicalReadFailureReason,
            matrix: matrix
        )
    }

    private func legacySnapshot(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory
    ) -> CanonicalGeneratedArtifactReadSnapshot {
        let local = legacyFacts(from: localInventory, peerAuthoritative: false)
        let peer = legacyFacts(from: peerInventory, peerAuthoritative: true)
        return CanonicalGeneratedArtifactReadProjection.snapshot(
            source: .legacy,
            facts: local.facts + peer.facts,
            failures: local.failures + peer.failures
        )
    }

    private func legacyFacts(
        from inventory: LocalNetworkSyncInventory,
        peerAuthoritative: Bool
    ) -> (
        facts: [CanonicalGeneratedArtifactReadProjectionArtifactFact],
        failures: [CanonicalGeneratedArtifactReadProjectionFailure]
    ) {
        var facts: [CanonicalGeneratedArtifactReadProjectionArtifactFact] = []
        var failures: [CanonicalGeneratedArtifactReadProjectionFailure] = []
        for artifact in inventory.artifacts {
            if artifact.kind == .metadataJSON || artifact.kind == .receiveJSON {
                continue
            }
            guard let canonicalKind = Self.canonicalArtifactKind(from: artifact.kind) else {
                failures.append(CanonicalGeneratedArtifactReadProjectionFailure(
                    kind: artifact.kind == .summaryMarkdown ? .unsupportedArtifactKind : .audioConfusionRisk,
                    source: .legacy,
                    objectID: artifact.ownerID,
                    artifactID: artifact.artifactID,
                    artifactKind: artifact.kind == .audio ? .audio : nil,
                    reason: "legacyArtifactKind=\(artifact.kind.rawValue)"
                ))
                continue
            }
            let safeToken = CanonicalProjectionContract.safeLogicalPathToken(artifact.logicalPathToken)
            let unsafePathTokenObserved = safeToken == nil
            let canonicalArtifact = CanonicalProjectionContract.makeArtifact(
                objectID: artifact.ownerID,
                kind: canonicalKind,
                availability: Self.canonicalAvailability(
                    from: artifact.availability,
                    checksum: artifact.checksum,
                    size: artifact.size
                ),
                contentHash: artifact.checksum.map { CanonicalHash($0) },
                byteSize: artifact.size,
                logicalPathToken: artifact.logicalPathToken,
                modifiedAt: CanonicalTimestamp(artifact.updatedAt),
                observedAt: CanonicalTimestamp(artifact.updatedAt),
                producedByNodeID: inventory.sourcePlatform == .Mac ? inventory.sourceDeviceID : nil,
                platform: inventory.sourcePlatform.rawValue
            )
            facts.append(CanonicalGeneratedArtifactReadProjectionArtifactFact(
                artifact: canonicalArtifact,
                parentTombstoned: false,
                localAvailability: !peerAuthoritative && Self.isAvailable(artifact.availability),
                peerAuthoritativeAvailability: peerAuthoritative
                    && CanonicalProjectionContract.isAuthoritativeProducer(canonicalArtifact, node: Self.node(from: inventory)),
                producerSummary: canonicalArtifact.producedBy?.rawValue,
                unsafePathTokenObserved: unsafePathTokenObserved
            ))
        }
        return (facts, failures)
    }

    private static func canonicalArtifactKind(from kind: LocalNetworkSyncArtifactKind) -> CanonicalArtifact.Kind? {
        switch kind {
        case .transcriptJSON:
            return .transcriptJSON
        case .transcriptMarkdown:
            return .transcriptMarkdown
        case .noteMarkdown:
            return .noteMarkdown
        case .noteJSON:
            return .noteJSON
        case .summaryJSON:
            return .summaryJSON
        case .metadataJSON, .receiveJSON, .summaryMarkdown, .audio:
            return nil
        }
    }

    private static func canonicalAvailability(
        from availability: LocalNetworkSyncArtifactAvailability,
        checksum: String?,
        size: Int64?
    ) -> CanonicalArtifact.Availability {
        switch availability {
        case .local, .availableOnPeer, .complete:
            return checksum != nil && size != nil ? .available : .availableWithoutHash
        case .missing:
            return .missing
        case .transferring:
            return .unknown
        }
    }

    private static func isAvailable(_ availability: LocalNetworkSyncArtifactAvailability) -> Bool {
        switch availability {
        case .local, .availableOnPeer, .complete:
            return true
        case .missing, .transferring:
            return false
        }
    }

    private static func node(from inventory: LocalNetworkSyncInventory) -> CanonicalNode {
        if let node = inventory.canonicalManifest?.node {
            return node
        }
        return CanonicalNode(
            nodeID: inventory.sourceDeviceID,
            platform: inventory.sourcePlatform.rawValue,
            capabilities: [
                .transcriptArtifact,
                .noteArtifact,
                .summaryArtifact
            ]
        )
    }
}
