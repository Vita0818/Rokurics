//
//  MacCanonicalLiveReadOnlyTransportProbeAudit.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/3.
//

import Foundation

struct MacCanonicalReadOnlyProbeClassifier {
    func gate(
        policy: CanonicalLiveReadOnlyTransportProbePolicy,
        method: String,
        path: String,
        bodyByteCount: Int
    ) -> CanonicalLiveReadOnlyTransportProbeGate {
        var policy = policy
        policy.route = CanonicalLiveReadOnlyTransportProbeRoute(method: method, path: path)
        return CanonicalLiveReadOnlyTransportProbeGate.evaluate(policy: policy, bodyByteCount: bodyByteCount)
    }
}

struct MacCanonicalReadOnlyProbeStateSnapshot: Equatable {
    var receiveRecordCount: Int?
    var uploadSessionCount: Int?
    var pendingSyncRequestCount: Int?
    var studyManifestChecksum: String?
    var unavailableReasons: [String]

    var hasUnavailableValue: Bool {
        !unavailableReasons.isEmpty
    }

    func verifiesNoMutation(comparedTo after: MacCanonicalReadOnlyProbeStateSnapshot) -> Bool {
        guard !hasUnavailableValue, !after.hasUnavailableValue else {
            return false
        }
        return receiveRecordCount == after.receiveRecordCount
            && uploadSessionCount == after.uploadSessionCount
            && pendingSyncRequestCount == after.pendingSyncRequestCount
            && studyManifestChecksum == after.studyManifestChecksum
    }

    var diagnosticsSummary: String {
        [
            "receiveRecords=\(receiveRecordCount.map(String.init) ?? "unavailable")",
            "uploadSessions=\(uploadSessionCount.map(String.init) ?? "unavailable")",
            "pendingSync=\(pendingSyncRequestCount.map(String.init) ?? "unavailable")",
            "studyManifestHashPrefix=\(CanonicalProductionRedaction.hashPrefix(studyManifestChecksum) ?? "unavailable")",
            "unavailable=\(unavailableReasons.isEmpty ? "none" : unavailableReasons.joined(separator: "+"))"
        ].joined(separator: ",")
    }

    static func capture(
        recordingFileStore: MacRecordingFileStore,
        studyLibraryStore: StudyLibraryStore,
        deviceConnectionStatusStore: DeviceConnectionStatusStore,
        localSyncDeviceID: String,
        manifestGeneratedAt: Date
    ) -> MacCanonicalReadOnlyProbeStateSnapshot {
        var unavailable: [String] = []
        let receiveRecordCount = recordingFileStore.receiveRecordCountForDiagnostics()
        let uploadSessionCount = recordingFileStore.uploadSessionCountForDiagnostics()
        if uploadSessionCount == nil {
            unavailable.append("uploadSessionCount")
        }
        let pendingSyncCount = deviceConnectionStatusStore.pendingSyncRequestCountForDiagnostics
        let manifest = studyLibraryStore.makeSyncManifest(
            deviceID: localSyncDeviceID,
            generatedAt: manifestGeneratedAt
        )
        let checksum = manifest.checksum.trimmingCharacters(in: .whitespacesAndNewlines)
        if checksum.isEmpty {
            unavailable.append("studyManifestChecksum")
        }
        return MacCanonicalReadOnlyProbeStateSnapshot(
            receiveRecordCount: receiveRecordCount,
            uploadSessionCount: uploadSessionCount,
            pendingSyncRequestCount: pendingSyncCount,
            studyManifestChecksum: checksum.isEmpty ? nil : checksum,
            unavailableReasons: unavailable.sorted()
        )
    }
}

struct MacCanonicalReadOnlyTransportProbeAudit {
    var gate: CanonicalLiveReadOnlyTransportProbeGate
    var before: MacCanonicalReadOnlyProbeStateSnapshot
    var after: MacCanonicalReadOnlyProbeStateSnapshot?

    var noMutationVerified: Bool {
        guard let after else {
            return false
        }
        return before.verifiesNoMutation(comparedTo: after)
    }

    var stateSnapshotUnavailable: Bool {
        before.hasUnavailableValue || (after?.hasUnavailableValue ?? false)
    }

    var diagnosticsSummary: String {
        [
            "mode=\(gate.mode.rawValue)",
            "route=\(gate.route.method) \(gate.route.path)",
            "routeStatus=\(gate.routeStatus.rawValue)",
            "blocked=\(gate.blocked)",
            "noMutationVerified=\(noMutationVerified)",
            "before={\(before.diagnosticsSummary)}",
            "after={\(after?.diagnosticsSummary ?? "unavailable")}",
            "reason=\(gate.reason)"
        ].joined(separator: ",")
    }
}
