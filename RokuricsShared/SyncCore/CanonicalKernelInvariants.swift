//
//  CanonicalKernelInvariants.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalKernelInvariantSeverity: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case required
    case safetyCritical
}

nonisolated struct CanonicalKernelInvariant: Codable, Equatable, Hashable, Sendable {
    var id: String
    var domain: CanonicalDomain?
    var severity: CanonicalKernelInvariantSeverity
    var summary: String

    nonisolated init(
        id: String,
        domain: CanonicalDomain? = nil,
        severity: CanonicalKernelInvariantSeverity,
        summary: String
    ) {
        self.id = id
        self.domain = domain
        self.severity = severity
        self.summary = summary
    }
}

nonisolated struct CanonicalKernelInvariantViolation: Codable, Equatable, Hashable, Sendable {
    var invariantID: String
    var domain: CanonicalDomain?
    var reason: String

    nonisolated init(invariantID: String, domain: CanonicalDomain? = nil, reason: String) {
        self.invariantID = invariantID
        self.domain = domain
        self.reason = CanonicalKernelStringSanitizer.required(reason, fallback: "invariantViolation")
    }
}

nonisolated struct CanonicalKernelInvariantReport: Codable, Equatable, Hashable, Sendable {
    var checkedAt: CanonicalTimestamp
    var invariants: [CanonicalKernelInvariant]
    var violations: [CanonicalKernelInvariantViolation]

    nonisolated init(
        checkedAt: CanonicalTimestamp,
        invariants: [CanonicalKernelInvariant],
        violations: [CanonicalKernelInvariantViolation] = []
    ) {
        self.checkedAt = checkedAt
        self.invariants = invariants.sorted { $0.id < $1.id }
        self.violations = violations.sorted { $0.invariantID < $1.invariantID }
    }

    nonisolated var passed: Bool {
        violations.isEmpty
    }
}

nonisolated enum CanonicalKernelInvariantCatalog {
    nonisolated static let v900Required: [CanonicalKernelInvariant] = [
        CanonicalKernelInvariant(
            id: "connection-owner-only-carrier-liveness",
            domain: .connection,
            severity: .required,
            summary: "Connection owns carrier, identity, pairing, heartbeat, status hints, and peer liveness only."
        ),
        CanonicalKernelInvariant(
            id: "transfer-owner-finalize-proof-required",
            domain: .transfer,
            severity: .safetyCritical,
            summary: "Transfer owns sessions, chunks, offset resume, retry, and receiver finalize proof."
        ),
        CanonicalKernelInvariant(
            id: "sync-owner-status-truth",
            domain: .sync,
            severity: .safetyCritical,
            summary: "Sync owns status truth, realtime exchange, reconciliation, apply plans, triggers, and read projection."
        ),
        CanonicalKernelInvariant(
            id: "file-owner-root-bound-no-freeze",
            domain: .file,
            severity: .safetyCritical,
            summary: "File owns tree snapshots, manifests, metadata store, checksum cache, root-bound writes, rollback, and no-freeze budgets."
        ),
        CanonicalKernelInvariant(
            id: "default-release-old-kernel",
            severity: .safetyCritical,
            summary: "Default and release mode remain oldKernel until a separate runtime rollout is approved."
        ),
        CanonicalKernelInvariant(
            id: "legacy-fallback-preserved",
            severity: .safetyCritical,
            summary: "Legacy fallback remains available for all canonical runtime adoption steps."
        ),
        CanonicalKernelInvariant(
            id: "no-route-or-upload-schema-change",
            severity: .safetyCritical,
            summary: "Contract freeze does not add routes or change upload route schemas."
        ),
        CanonicalKernelInvariant(
            id: "peer-audio-proof-hard-rules",
            domain: .sync,
            severity: .safetyCritical,
            summary: "Metadata-only, receive-record-only, completed-ledger-only, partial receive, local file, and expected manifest are not peer audio proof."
        ),
        CanonicalKernelInvariant(
            id: "view-refresh-no-upload-job",
            domain: .sync,
            severity: .safetyCritical,
            summary: "Read projection or view refresh never creates upload jobs."
        ),
        CanonicalKernelInvariant(
            id: "retry-drainer-existing-job-only",
            domain: .transfer,
            severity: .safetyCritical,
            summary: "Retry drainers only resume existing eligible work."
        ),
        CanonicalKernelInvariant(
            id: "main-actor-heavy-work-forbidden",
            domain: .file,
            severity: .safetyCritical,
            summary: "File scans, manifest builds, full-file hashing, and diagnostics writes stay off main-actor hot paths."
        ),
        CanonicalKernelInvariant(
            id: "diagnostics-redaction-required",
            severity: .safetyCritical,
            summary: "Diagnostics never expose forbidden path, hash, secret, fingerprint, payload, audio, transcript, note, summary, or provider-response material."
        )
    ]
}
