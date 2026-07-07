//
//  CanonicalGeneratedArtifactDomainTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalGeneratedArtifactDomainTests {
    @Test func businessHashIgnoresPathObservationAndProviderPayloadsOnMac() throws {
        let base = Self.artifact(
            logicalPathToken: "generated/transcript.json",
            observedAt: 3_000,
            producedByNodeID: "mac-01"
        )
        let moved = Self.artifact(
            logicalPathToken: "other/transcript.json",
            observedAt: 9_000,
            producedByNodeID: "mac-02"
        )

        #expect(base.generatedArtifactBusinessHash == moved.generatedArtifactBusinessHash)
        #expect(CanonicalGeneratedArtifactHashSchema.v1.excludedFields.contains("logicalPathToken"))
        #expect(CanonicalGeneratedArtifactHashSchema.v1.excludedFields.contains("providerResponse"))
        #expect(CanonicalGeneratedArtifactHashSchema.v1.excludedFields.contains("transcriptContent"))
    }

    @Test func modifiedAtAndMissingContentPoliciesPreserveFallbackOnMac() throws {
        let peerNewer = CanonicalGeneratedArtifactModifiedAtPolicy.current.decide(
            CanonicalGeneratedArtifactDecisionInput(
                local: Self.artifact(contentHash: "aaaaaaaa", modifiedAt: 5_000),
                peer: Self.artifact(contentHash: "bbbbbbbb", modifiedAt: 6_000)
            )
        )
        let sameContent = CanonicalGeneratedArtifactModifiedAtPolicy.current.decide(
            CanonicalGeneratedArtifactDecisionInput(
                local: Self.artifact(contentHash: "aaaaaaaa", byteSize: 100, modifiedAt: 4_000),
                peer: Self.artifact(contentHash: "aaaaaaaa", byteSize: 100, modifiedAt: 5_000)
            )
        )
        let missingContent = CanonicalGeneratedArtifactModifiedAtPolicy.current.decide(
            CanonicalGeneratedArtifactDecisionInput(
                local: Self.artifact(contentHash: nil, byteSize: nil, availability: .availableWithoutHash),
                peer: Self.artifact(contentHash: "bbbbbbbb", byteSize: 100)
            )
        )
        let unsupported = CanonicalGeneratedArtifactModifiedAtPolicy.current.decide(
            CanonicalGeneratedArtifactDecisionInput(local: Self.artifact(kind: .audio), peer: nil)
        )

        #expect(peerNewer.action == .applyPeer)
        #expect(sameContent.action == .noOp)
        #expect(missingContent.action == .deferMissingContent)
        #expect(unsupported.action == .unsupportedKindBlocked)
    }

    private static func artifact(
        kind: CanonicalArtifact.Kind = .transcriptJSON,
        contentHash: String? = "aaaaaaaa",
        byteSize: Int64? = 100,
        availability: CanonicalArtifact.Availability = .available,
        modifiedAt: TimeInterval? = 5_000,
        logicalPathToken: String = "generated/transcript.json",
        observedAt: TimeInterval? = nil,
        producedByNodeID: String = "mac-01"
    ) -> CanonicalArtifact {
        let resolvedContentHash = contentHash.map { CanonicalHash($0) }
        let resolvedModifiedAt = modifiedAt.map { CanonicalTimestamp(Date(timeIntervalSince1970: $0)) }
        let resolvedObservedAt = observedAt.map { CanonicalTimestamp(Date(timeIntervalSince1970: $0)) }
        return CanonicalArtifact(
            artifactID: kind.artifactID(for: "recording-01"),
            objectID: "recording-01",
            kind: kind,
            availability: availability,
            contentHash: resolvedContentHash,
            byteSize: byteSize,
            logicalName: "transcript.json",
            logicalPathToken: logicalPathToken,
            modifiedAt: resolvedModifiedAt,
            observedAt: resolvedObservedAt,
            producedBy: .transcription,
            producedByNodeID: producedByNodeID
        )
    }
}
