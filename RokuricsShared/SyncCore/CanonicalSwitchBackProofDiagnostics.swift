//
//  CanonicalSwitchBackProofDiagnostics.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/12.
//

import Foundation

#if DEBUG
nonisolated enum CanonicalSwitchBackProofNodeRole: String, Codable, Equatable, Hashable, Sendable {
    case iPhone
    case mac
}

nonisolated struct CanonicalSwitchBackProofDomainCounts: Codable, Equatable, Sendable {
    var total: Int
    var proven: Int
    var blocked: Int
}

nonisolated struct CanonicalSwitchBackProofCrashPointCounts: Codable, Equatable, Sendable {
    var total: Int
    var recovered: Int
    var blocked: Int
}

nonisolated struct CanonicalSwitchBackProofEvidenceEvent: Codable, Equatable, Sendable {
    var timestamp: Date
    var eventName: String
    var nodeRole: CanonicalSwitchBackProofNodeRole
    var runID: String
    var status: String
    var rootKind: String
    var redactedRootToken: String
    var modeSequenceSummary: String
    var domainCounts: CanonicalSwitchBackProofDomainCounts
    var crashPointCounts: CanonicalSwitchBackProofCrashPointCounts
    var blockerEnums: [String]
    var evidenceKind: String
    var realDeviceEvidencePresent: Bool
    var relativeEvidencePath: String
}

nonisolated struct CanonicalSwitchBackProofUISummary: Codable, Equatable, Sendable {
    var status: CanonicalSwitchBackEvidenceStatus
    var rootSafetyStatus: String
    var cloneRootToken: String
    var domainMatrixSummary: String
    var crashRestartSummary: String
    var oldKernelReadResult: String
    var canonicalFullSyncResult: String
    var switchBackOldKernelResult: String
    var switchAgainCanonicalFullSyncResult: String
    var evidencePath: String
    var blockers: [String]
    var warning: String
    var realDeviceEvidence: Bool
    var diagnosticsSummary: String

    nonisolated var displayText: String {
        [
            "status=\(status.rawValue)",
            "rootSafety=\(rootSafetyStatus)",
            "cloneRootToken=\(cloneRootToken)",
            "domains=\(domainMatrixSummary)",
            "crashRestart=\(crashRestartSummary)",
            "oldKernelRead=\(oldKernelReadResult)",
            "canonicalFullSync=\(canonicalFullSyncResult)",
            "switchBackOldKernel=\(switchBackOldKernelResult)",
            "switchAgainCanonicalFullSync=\(switchAgainCanonicalFullSyncResult)",
            "evidence=\(evidencePath)",
            "realDeviceEvidence=\(realDeviceEvidence)",
            "blockers=\(blockers.joined(separator: "|"))",
            "warning=\(warning)"
        ].joined(separator: "\n")
    }
}

nonisolated struct CanonicalSwitchBackProofEvidenceJSONLWriter {
    nonisolated static let relativeEvidencePath = "Diagnostics/canonical-switch-back-proof.jsonl"

    private let fileManager: FileManager

    nonisolated init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    nonisolated func write(
        events: [CanonicalSwitchBackProofEvidenceEvent],
        evidenceRootURL: URL
    ) throws -> URL {
        let logURL = evidenceRootURL
            .standardizedFileURL
            .appendingPathComponent(Self.relativeEvidencePath, isDirectory: false)
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let lines = try events.map { event -> String in
            let data = try encoder.encode(event)
            let line = String(data: data, encoding: .utf8) ?? "{}"
            let redactionProbe = line.replacingOccurrences(of: "\\/", with: "/")
            if CanonicalSyncKernelEvidenceRedactor.containsSensitiveSignal(redactionProbe) {
                throw CanonicalSwitchBackProofEvidenceWriterError.redactionViolation
            }
            return line
        }
        guard !lines.isEmpty else { return logURL }

        let payload = Data((lines.joined(separator: "\n") + "\n").utf8)
        if fileManager.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            handle.seekToEndOfFile()
            handle.write(payload)
            handle.closeFile()
        } else {
            try payload.write(to: logURL, options: .atomic)
        }
        return logURL
    }
}

nonisolated enum CanonicalSwitchBackProofEvidenceWriterError: Error, Equatable {
    case redactionViolation
}

nonisolated struct CanonicalSwitchBackProofDebugRunner {
    private let fileManager: FileManager

    nonisolated init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    nonisolated func run(
        nodeRole: CanonicalSwitchBackProofNodeRole,
        appDataRootURL: URL,
        now: Date = Date(),
        runID: String = UUID().uuidString
    ) -> CanonicalSwitchBackProofUISummary {
        let sourceRoot = appDataRootURL.standardizedFileURL.resolvingSymlinksInPath()
        let sourceToken = redactedRootToken(sourceRoot)
        let driverTempRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("CanonicalSwitchBackProofDebugRunner", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let cloneRootURL = driverTempRootURL.appendingPathComponent("realistic-root-clone", isDirectory: true)
        let evidenceRootURL = driverTempRootURL
        var events: [CanonicalSwitchBackProofEvidenceEvent] = [
            event(
                "canonicalSwitchBackProofDriverStarted",
                nodeRole: nodeRole,
                runID: runID,
                status: "started",
                rootKind: "sourceRoot",
                rootToken: sourceToken,
                domainCounts: Self.emptyDomainCounts(),
                crashPointCounts: Self.emptyCrashPointCounts(),
                blockers: [],
                realDeviceEvidencePresent: false,
                timestamp: now
            )
        ]

        do {
            let result = try CanonicalRealisticRootSwitchBackProofDriver().run(
                appDataRootURL: sourceRoot,
                cloneRootURL: cloneRootURL,
                fileManager: fileManager,
                realDeviceEvidencePresent: false,
                ownerApprovedForManualGate: false,
                manualBackupAcknowledgedForManualGate: false
            )
            let domainCounts = Self.domainCounts(from: result.proof)
            let crashCounts = Self.crashPointCounts(from: result.proof)
            let blockers = Self.blockers(from: result)
            let status = Self.status(from: result)
            let rootKind = result.cloneRootSafety.accepted ? "tempClone" : "rejectedClone"

            if !result.cloneRootSafety.accepted {
                events.append(event(
                    "canonicalSwitchBackProofRootRejected",
                    nodeRole: nodeRole,
                    runID: runID,
                    status: "blocked",
                    rootKind: rootKind,
                    rootToken: result.cloneRootToken,
                    domainCounts: domainCounts,
                    crashPointCounts: crashCounts,
                    blockers: blockers,
                    realDeviceEvidencePresent: false,
                    timestamp: now
                ))
            }
            if result.cloneResult?.cloned == true {
                events.append(event(
                    "canonicalSwitchBackProofCloneCreated",
                    nodeRole: nodeRole,
                    runID: runID,
                    status: "passed",
                    rootKind: "tempClone",
                    rootToken: result.cloneRootToken,
                    domainCounts: domainCounts,
                    crashPointCounts: crashCounts,
                    blockers: blockers,
                    realDeviceEvidencePresent: false,
                    timestamp: now
                ))
                events.append(event(
                    "canonicalSwitchBackProofHarnessStarted",
                    nodeRole: nodeRole,
                    runID: runID,
                    status: "started",
                    rootKind: "tempClone",
                    rootToken: result.cloneRootToken,
                    domainCounts: domainCounts,
                    crashPointCounts: crashCounts,
                    blockers: blockers,
                    realDeviceEvidencePresent: false,
                    timestamp: now
                ))
            }
            if result.proof != nil {
                events.append(event(
                    "canonicalSwitchBackProofHarnessCompleted",
                    nodeRole: nodeRole,
                    runID: runID,
                    status: result.proof?.isProven == true ? "passed" : "failed",
                    rootKind: "tempClone",
                    rootToken: result.cloneRootToken,
                    domainCounts: domainCounts,
                    crashPointCounts: crashCounts,
                    blockers: blockers,
                    realDeviceEvidencePresent: false,
                    timestamp: now
                ))
            }
            events.append(event(
                status == .passed ? "canonicalSwitchBackProofDriverCompleted" : (status == .blocked ? "canonicalSwitchBackProofDriverBlocked" : "canonicalSwitchBackProofFailed"),
                nodeRole: nodeRole,
                runID: runID,
                status: status.rawValue,
                rootKind: rootKind,
                rootToken: result.cloneRootToken,
                domainCounts: domainCounts,
                crashPointCounts: crashCounts,
                blockers: blockers,
                realDeviceEvidencePresent: false,
                timestamp: now
            ))
            events.append(event(
                "canonicalSwitchBackProofRealDeviceEvidenceMissing",
                nodeRole: nodeRole,
                runID: runID,
                status: "skippedWithReason",
                rootKind: rootKind,
                rootToken: result.cloneRootToken,
                domainCounts: domainCounts,
                crashPointCounts: crashCounts,
                blockers: ["realDeviceEvidenceMissing"],
                realDeviceEvidencePresent: false,
                timestamp: now
            ))
            events.append(event(
                "canonicalSwitchBackProofEvidenceWritten",
                nodeRole: nodeRole,
                runID: runID,
                status: status.rawValue,
                rootKind: rootKind,
                rootToken: result.cloneRootToken,
                domainCounts: domainCounts,
                crashPointCounts: crashCounts,
                blockers: blockers,
                realDeviceEvidencePresent: false,
                timestamp: now
            ))

            do {
                _ = try CanonicalSwitchBackProofEvidenceJSONLWriter(fileManager: fileManager).write(
                    events: events,
                    evidenceRootURL: evidenceRootURL
                )
                return Self.summary(
                    from: result,
                    status: status,
                    evidencePath: Self.evidencePathText(runID: runID),
                    writerBlocker: nil
                )
            } catch {
                return Self.summary(
                    from: result,
                    status: .blocked,
                    evidencePath: Self.evidencePathText(runID: runID),
                    writerBlocker: Self.writerBlocker(from: error)
                )
            }
        } catch {
            let safeError = CanonicalSyncKernelEvidenceRedactor.redact(String(describing: error))
            events.append(event(
                "canonicalSwitchBackProofFailed",
                nodeRole: nodeRole,
                runID: runID,
                status: "blocked",
                rootKind: "sourceRoot",
                rootToken: sourceToken,
                domainCounts: Self.emptyDomainCounts(),
                crashPointCounts: Self.emptyCrashPointCounts(),
                blockers: ["driverException"],
                realDeviceEvidencePresent: false,
                timestamp: now
            ))
            _ = try? CanonicalSwitchBackProofEvidenceJSONLWriter(fileManager: fileManager).write(
                events: events,
                evidenceRootURL: evidenceRootURL
            )
            return blockedSummary(
                cloneRootToken: "unavailable",
                evidencePath: Self.evidencePathText(runID: runID),
                blockers: ["driverException"],
                warning: safeError
            )
        }
    }

    private nonisolated func redactedRootToken(_ url: URL) -> String {
        CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(url.path).value) ?? "root"
    }

    private nonisolated func event(
        _ name: String,
        nodeRole: CanonicalSwitchBackProofNodeRole,
        runID: String,
        status: String,
        rootKind: String,
        rootToken: String,
        domainCounts: CanonicalSwitchBackProofDomainCounts,
        crashPointCounts: CanonicalSwitchBackProofCrashPointCounts,
        blockers: [String],
        realDeviceEvidencePresent: Bool,
        timestamp: Date
    ) -> CanonicalSwitchBackProofEvidenceEvent {
        CanonicalSwitchBackProofEvidenceEvent(
            timestamp: timestamp,
            eventName: name,
            nodeRole: nodeRole,
            runID: runID,
            status: status,
            rootKind: rootKind,
            redactedRootToken: rootToken,
            modeSequenceSummary: "oldKernel>canonicalFullSync>oldKernel>canonicalFullSync",
            domainCounts: domainCounts,
            crashPointCounts: crashPointCounts,
            blockerEnums: Self.unique(blockers),
            evidenceKind: "realisticRoot",
            realDeviceEvidencePresent: realDeviceEvidencePresent,
            relativeEvidencePath: CanonicalSwitchBackProofEvidenceJSONLWriter.relativeEvidencePath
        )
    }

    private nonisolated static func summary(
        from result: CanonicalRealisticRootSwitchBackProofDriverResult,
        status: CanonicalSwitchBackEvidenceStatus,
        evidencePath: String,
        writerBlocker: String?
    ) -> CanonicalSwitchBackProofUISummary {
        let proof = result.proof
        let domainCounts = domainCounts(from: proof)
        let crashCounts = crashPointCounts(from: proof)
        var blockers = blockers(from: result)
        if let writerBlocker {
            blockers.append(writerBlocker)
        }
        blockers = unique(blockers)
        let switchBackProof = proof?.realisticHarnessResult.switchBackProof
        return CanonicalSwitchBackProofUISummary(
            status: writerBlocker == nil ? status : .blocked,
            rootSafetyStatus: result.cloneRootSafety.accepted ? "accepted" : "blocked",
            cloneRootToken: result.cloneRootToken,
            domainMatrixSummary: "proven=\(domainCounts.proven)/\(domainCounts.total),evidenceKind=realisticRoot",
            crashRestartSummary: "recovered=\(crashCounts.recovered)/\(crashCounts.total)",
            oldKernelReadResult: "legacyReadable=\(proof?.realisticHarnessResult.legacyReadableStateCount ?? 0)",
            canonicalFullSyncResult: "canonicalReadable=\(proof?.realisticHarnessResult.canonicalReadableStateCount ?? 0)",
            switchBackOldKernelResult: "passed=\(switchBackProof?.switchBackComparisonPassed == true)",
            switchAgainCanonicalFullSyncResult: "passed=\(switchBackProof?.switchForwardComparisonPassed == true)",
            evidencePath: evidencePath,
            blockers: blockers,
            warning: "realDeviceEvidence=false; realistic-root proof is not paired-device evidence",
            realDeviceEvidence: false,
            diagnosticsSummary: CanonicalSyncKernelEvidenceRedactor.redact(result.diagnosticsSummary)
        )
    }

    private nonisolated func blockedSummary(
        cloneRootToken: String,
        evidencePath: String,
        blockers: [String],
        warning: String
    ) -> CanonicalSwitchBackProofUISummary {
        CanonicalSwitchBackProofUISummary(
            status: .blocked,
            rootSafetyStatus: "blocked",
            cloneRootToken: cloneRootToken,
            domainMatrixSummary: "proven=0/0,evidenceKind=realisticRoot",
            crashRestartSummary: "recovered=0/0",
            oldKernelReadResult: "legacyReadable=0",
            canonicalFullSyncResult: "canonicalReadable=0",
            switchBackOldKernelResult: "passed=false",
            switchAgainCanonicalFullSyncResult: "passed=false",
            evidencePath: evidencePath,
            blockers: Self.unique(blockers),
            warning: warning,
            realDeviceEvidence: false,
            diagnosticsSummary: "canonicalSwitchBackProofDebugRunner=blocked,redacted=true"
        )
    }

    private nonisolated static func status(
        from result: CanonicalRealisticRootSwitchBackProofDriverResult
    ) -> CanonicalSwitchBackEvidenceStatus {
        if result.isProofComplete {
            return .passed
        }
        if result.blockers.contains(.proofFailed) || result.evidencePackage?.diagnosticsRedactionStatus == .failed {
            return .failed
        }
        return .blocked
    }

    private nonisolated static func domainCounts(
        from proof: CanonicalKernelSwitchBackProof?
    ) -> CanonicalSwitchBackProofDomainCounts {
        let total = proof?.domainMatrix.results.count ?? 0
        let proven = proof?.domainMatrix.results.filter(\.isProven).count ?? 0
        return CanonicalSwitchBackProofDomainCounts(total: total, proven: proven, blocked: max(total - proven, 0))
    }

    private nonisolated static func crashPointCounts(
        from proof: CanonicalKernelSwitchBackProof?
    ) -> CanonicalSwitchBackProofCrashPointCounts {
        let total = proof?.crashRecoveryProofs.count ?? 0
        let recovered = proof?.crashRecoveryProofs.filter(\.recoveredSafely).count ?? 0
        return CanonicalSwitchBackProofCrashPointCounts(total: total, recovered: recovered, blocked: max(total - recovered, 0))
    }

    private nonisolated static func emptyDomainCounts() -> CanonicalSwitchBackProofDomainCounts {
        CanonicalSwitchBackProofDomainCounts(total: 0, proven: 0, blocked: 0)
    }

    private nonisolated static func emptyCrashPointCounts() -> CanonicalSwitchBackProofCrashPointCounts {
        CanonicalSwitchBackProofCrashPointCounts(total: 0, recovered: 0, blocked: 0)
    }

    private nonisolated static func blockers(
        from result: CanonicalRealisticRootSwitchBackProofDriverResult
    ) -> [String] {
        unique(
            result.blockers.map(\.rawValue)
                + (result.evidencePackage?.blockers ?? [])
                + result.scorecard.blockers.map(\.rawValue)
        )
    }

    private nonisolated static func evidencePathText(runID: String) -> String {
        let token = CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(runID).value) ?? "temp"
        return "temp/CanonicalSwitchBackProofDebugRunner/\(token)/\(CanonicalSwitchBackProofEvidenceJSONLWriter.relativeEvidencePath)"
    }

    private nonisolated static func writerBlocker(from error: Error) -> String {
        if let evidenceError = error as? CanonicalSwitchBackProofEvidenceWriterError {
            switch evidenceError {
            case .redactionViolation:
                return "evidenceRedactionViolation"
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return "evidenceWriteCocoaError\(nsError.code)"
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return "evidenceWritePOSIXError\(nsError.code)"
        }
        return "evidenceWriteFailed"
    }

    private nonisolated static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in values where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            ordered.append(value)
        }
        return ordered
    }
}
#endif
