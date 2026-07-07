//
//  CanonicalKernelProtocols.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalKernelStringSanitizer {
    nonisolated static func optional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    nonisolated static func required(_ value: String, fallback: String) -> String {
        optional(value) ?? fallback
    }
}

nonisolated struct CanonicalNodeID: Codable, Equatable, Hashable, Comparable, Sendable {
    var rawValue: String

    nonisolated init(_ rawValue: String) {
        self.rawValue = Self.normalized(rawValue, fallback: "node-unknown")
    }

    nonisolated static func < (left: CanonicalNodeID, right: CanonicalNodeID) -> Bool {
        left.rawValue < right.rawValue
    }

    private nonisolated static func normalized(_ value: String, fallback: String) -> String {
        CanonicalKernelStringSanitizer.required(value, fallback: fallback)
    }
}

nonisolated enum CanonicalNodeRole: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case iPhone
    case mac
    case liveActivityExtension
    case testHarness
    case unknown
}

nonisolated struct CanonicalNodeIdentity: Codable, Equatable, Hashable, Sendable {
    var nodeID: CanonicalNodeID
    var role: CanonicalNodeRole
    var displayName: String?
    var protocolVersion: CanonicalProtocolVersion
    var domains: [CanonicalDomain]

    nonisolated init(
        nodeID: CanonicalNodeID,
        role: CanonicalNodeRole,
        displayName: String? = nil,
        protocolVersion: CanonicalProtocolVersion = .v900,
        domains: [CanonicalDomain] = CanonicalDomain.allCases
    ) {
        self.nodeID = nodeID
        self.role = role
        self.displayName = CanonicalKernelStringSanitizer.optional(displayName)
        self.protocolVersion = protocolVersion
        self.domains = Array(Set(domains)).sorted { $0.rawValue < $1.rawValue }
    }
}

nonisolated struct CanonicalLogicalTime: Codable, Equatable, Hashable, Comparable, Sendable {
    var counter: UInt64
    var nodeID: CanonicalNodeID

    nonisolated init(counter: UInt64 = 0, nodeID: CanonicalNodeID) {
        self.counter = counter
        self.nodeID = nodeID
    }

    nonisolated func advanced(by delta: UInt64 = 1) -> CanonicalLogicalTime {
        CanonicalLogicalTime(counter: counter + delta, nodeID: nodeID)
    }

    nonisolated static func < (left: CanonicalLogicalTime, right: CanonicalLogicalTime) -> Bool {
        if left.counter != right.counter {
            return left.counter < right.counter
        }
        return left.nodeID < right.nodeID
    }
}

nonisolated struct CanonicalSequence: Codable, Equatable, Hashable, Comparable, Sendable {
    var rawValue: UInt64

    nonisolated init(_ rawValue: UInt64 = 0) {
        self.rawValue = rawValue
    }

    nonisolated var next: CanonicalSequence {
        CanonicalSequence(rawValue + 1)
    }

    nonisolated static func < (left: CanonicalSequence, right: CanonicalSequence) -> Bool {
        left.rawValue < right.rawValue
    }
}

nonisolated struct CanonicalProtocolVersion: Codable, Equatable, Hashable, Comparable, Sendable {
    var major: Int
    var minor: Int
    var patch: Int

    nonisolated init(major: Int, minor: Int, patch: Int = 0) {
        self.major = max(0, major)
        self.minor = max(0, minor)
        self.patch = max(0, patch)
    }

    nonisolated static let v900 = CanonicalProtocolVersion(major: 9, minor: 0, patch: 0)

    nonisolated static func < (left: CanonicalProtocolVersion, right: CanonicalProtocolVersion) -> Bool {
        if left.major != right.major {
            return left.major < right.major
        }
        if left.minor != right.minor {
            return left.minor < right.minor
        }
        return left.patch < right.patch
    }
}

nonisolated struct CanonicalObjectID: Codable, Equatable, Hashable, Comparable, Sendable {
    var rawValue: String

    nonisolated init(_ rawValue: String) {
        self.rawValue = CanonicalKernelStringSanitizer.required(rawValue, fallback: "object-unknown")
    }

    nonisolated static func < (left: CanonicalObjectID, right: CanonicalObjectID) -> Bool {
        left.rawValue < right.rawValue
    }
}

nonisolated enum CanonicalDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case connection
    case transfer
    case sync
    case file
}

nonisolated enum CanonicalKernelModeMirror: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case oldKernel
    case diagnosticsOnly
    case canonicalShadow
    case canonicalDecisionOnly
    case canonicalApplyNoAudio
    case canonicalFullSync
    case blocked

    nonisolated init(switchMode: CanonicalKernelSwitchMode) {
        switch switchMode {
        case .oldKernel:
            self = .oldKernel
        case .diagnosticsOnly:
            self = .diagnosticsOnly
        case .canonicalShadow:
            self = .canonicalShadow
        case .canonicalDecisionOnly:
            self = .canonicalDecisionOnly
        case .canonicalApplyNoAudio:
            self = .canonicalApplyNoAudio
        case .canonicalFullSync:
            self = .canonicalFullSync
        case .blocked:
            self = .blocked
        }
    }

    nonisolated var switchMode: CanonicalKernelSwitchMode {
        switch self {
        case .oldKernel:
            return .oldKernel
        case .diagnosticsOnly:
            return .diagnosticsOnly
        case .canonicalShadow:
            return .canonicalShadow
        case .canonicalDecisionOnly:
            return .canonicalDecisionOnly
        case .canonicalApplyNoAudio:
            return .canonicalApplyNoAudio
        case .canonicalFullSync:
            return .canonicalFullSync
        case .blocked:
            return .blocked
        }
    }

    nonisolated static let mirrorsCanonicalKernelSwitchSemanticsOnly = true
    nonisolated var replacesCanonicalKernelSwitch: Bool { false }
}

nonisolated enum CanonicalKernelPortableBoundary: Codable, Equatable, Sendable {
    case v900ContractOnly

    nonisolated static let requiredImports: [String] = ["Foundation"]
    nonisolated static let adapterSpecificRuntimeBindingCount = 0
    nonisolated static let mutatesApplicationRuntime = false
}
