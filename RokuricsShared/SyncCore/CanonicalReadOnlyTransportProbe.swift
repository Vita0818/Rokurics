//
//  CanonicalReadOnlyTransportProbe.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/3.
//

import Foundation

nonisolated enum CanonicalReadOnlyTransportProbeRouteStatus: String, Codable, Equatable, Hashable, Sendable {
    case allowedReadOnly
    case rejectedMutating
    case rejectedUnknown
    case suppressedDisabled
}

nonisolated enum CanonicalReadOnlyTransportProbeFailure: String, Codable, Equatable, Hashable, Sendable {
    case disabled
    case mutatingRouteRejected
    case unknownRouteRejected
    case artifactFetchNotAllowed
    case artifactFetchTooLarge
    case authBoundaryMissing
    case manifestHashUsedAsAuth
    case networkSuppressed
    case sendFailed
}

nonisolated enum CanonicalLiveReadOnlyTransportProbeMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case classifyOnly
    case buildSignedEnvelopeOnly
    case sendReadOnlyProbe
    case blockedMutatingRoute
}

typealias CanonicalLiveReadOnlyTransportProbeRoute = CanonicalReadOnlyTransportProbeRoute

nonisolated enum CanonicalLiveReadOnlyTransportProbeFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case mutatingRouteRejected
    case unknownRouteRejected
    case artifactFetchNotAllowed
    case artifactFetchTooLarge
    case internalConfigurationMissing
    case authBoundaryMissing
    case manifestHashUsedAsAuth
    case signedEnvelopeBuildFailed
    case networkSuppressed
    case sendFailed
    case responseRejected
}

nonisolated enum CanonicalLiveReadOnlyTransportProbeDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalLiveReadOnlyProbePolicyEvaluated
    case canonicalLiveReadOnlyProbeRouteAllowed
    case canonicalLiveReadOnlyProbeRouteRejected
    case canonicalLiveReadOnlyProbeEnvelopeBuilt
    case canonicalLiveReadOnlyProbeSendSuppressed
    case canonicalLiveReadOnlyProbeSendStarted
    case canonicalLiveReadOnlyProbeSendCompleted
    case canonicalLiveReadOnlyProbeSendFailed
    case canonicalLiveReadOnlyProbeAuthBoundaryPreserved
    case canonicalLiveReadOnlyProbeMacAuditStarted
    case canonicalLiveReadOnlyProbeMacAuditCompleted
    case canonicalLiveReadOnlyProbeNoMutationVerified
    case canonicalLiveReadOnlyProbeMutationRiskBlocked
    case canonicalLiveReadOnlyProbeStateSnapshotUnavailable
}

nonisolated enum CanonicalLiveReadOnlyTransportProbeHTTP {
    static let markerHeader = "X-Rokurics-Canonical-Probe"
    static let markerValue = "live-read-only-v8.1"
    static let modeHeader = "X-Rokurics-Canonical-Probe-Mode"
    static let routeHeader = "X-Rokurics-Canonical-Probe-Route"
    static let syncRunIDHeader = "X-Rokurics-Canonical-Probe-Sync-Run-ID"

    nonisolated static func markerHeaders(
        mode: CanonicalLiveReadOnlyTransportProbeMode,
        route: CanonicalLiveReadOnlyTransportProbeRoute,
        syncRunID: String?
    ) -> [String: String] {
        var headers = [
            markerHeader: markerValue,
            modeHeader: mode.rawValue,
            routeHeader: "\(route.method) \(route.path)"
        ]
        if let syncRunID = CanonicalShadowMigrationRedaction.safeIdentifier(syncRunID) {
            headers[syncRunIDHeader] = syncRunID
        }
        return headers
    }

    nonisolated static func isMarked(headers: [String: String]) -> Bool {
        normalized(headers)[markerHeader.lowercased()] == markerValue
    }

    nonisolated static func syncRunID(headers: [String: String]) -> String? {
        CanonicalShadowMigrationRedaction.safeIdentifier(normalized(headers)[syncRunIDHeader.lowercased()])
    }

    private nonisolated static func normalized(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [String: String]()) { result, header in
            result[header.key.lowercased()] = header.value
        }
    }
}

nonisolated struct CanonicalReadOnlyTransportProbeRoute: Codable, Equatable, Hashable, Sendable {
    var method: String
    var path: String

    nonisolated init(method: String, path: String) {
        self.method = method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.path = CanonicalShadowMigrationRedaction.safeText(path) ?? "/unknown"
    }

    nonisolated static let health = CanonicalReadOnlyTransportProbeRoute(method: "GET", path: "/health")
    nonisolated static let fingerprint = CanonicalReadOnlyTransportProbeRoute(method: "GET", path: "/fingerprint")
    nonisolated static let syncStatus = CanonicalReadOnlyTransportProbeRoute(method: "POST", path: "/sync/status")
    nonisolated static let syncInventory = CanonicalReadOnlyTransportProbeRoute(method: "POST", path: "/sync/inventory")
    nonisolated static let deviceStatus = CanonicalReadOnlyTransportProbeRoute(method: "POST", path: "/device/status")
    nonisolated static let artifactRequest = CanonicalReadOnlyTransportProbeRoute(method: "POST", path: "/sync/artifact-request")
}

nonisolated struct CanonicalLiveReadOnlyTransportProbePolicy: Codable, Equatable, Sendable {
    var mode: CanonicalLiveReadOnlyTransportProbeMode
    var route: CanonicalLiveReadOnlyTransportProbeRoute
    var allowBoundedArtifactFetch: Bool
    var artifactFetchMaxBytes: Int
    var internalConfigurationEnabled: Bool
    var requestTimeoutSeconds: TimeInterval
    var resourceTimeoutSeconds: TimeInterval

    nonisolated init(
        mode: CanonicalLiveReadOnlyTransportProbeMode = .disabled,
        route: CanonicalLiveReadOnlyTransportProbeRoute = .syncInventory,
        allowBoundedArtifactFetch: Bool = false,
        artifactFetchMaxBytes: Int = 256 * 1024,
        internalConfigurationEnabled: Bool = false,
        requestTimeoutSeconds: TimeInterval = 5,
        resourceTimeoutSeconds: TimeInterval = 8
    ) {
        self.mode = mode
        self.route = route
        self.allowBoundedArtifactFetch = allowBoundedArtifactFetch
        self.artifactFetchMaxBytes = max(0, artifactFetchMaxBytes)
        self.internalConfigurationEnabled = internalConfigurationEnabled
        self.requestTimeoutSeconds = max(1, requestTimeoutSeconds)
        self.resourceTimeoutSeconds = max(self.requestTimeoutSeconds, resourceTimeoutSeconds)
    }

    nonisolated static let disabled = CanonicalLiveReadOnlyTransportProbePolicy()

    nonisolated static func classifyOnly(
        route: CanonicalLiveReadOnlyTransportProbeRoute = .syncInventory,
        allowBoundedArtifactFetch: Bool = false
    ) -> CanonicalLiveReadOnlyTransportProbePolicy {
        CanonicalLiveReadOnlyTransportProbePolicy(
            mode: .classifyOnly,
            route: route,
            allowBoundedArtifactFetch: allowBoundedArtifactFetch
        )
    }

    nonisolated static func buildSignedEnvelopeOnly(
        route: CanonicalLiveReadOnlyTransportProbeRoute = .syncInventory,
        allowBoundedArtifactFetch: Bool = false,
        internalConfigurationEnabled: Bool = true
    ) -> CanonicalLiveReadOnlyTransportProbePolicy {
        CanonicalLiveReadOnlyTransportProbePolicy(
            mode: .buildSignedEnvelopeOnly,
            route: route,
            allowBoundedArtifactFetch: allowBoundedArtifactFetch,
            internalConfigurationEnabled: internalConfigurationEnabled
        )
    }

    nonisolated static func sendReadOnlyProbe(
        route: CanonicalLiveReadOnlyTransportProbeRoute = .syncInventory,
        allowBoundedArtifactFetch: Bool = false,
        internalConfigurationEnabled: Bool = true
    ) -> CanonicalLiveReadOnlyTransportProbePolicy {
        CanonicalLiveReadOnlyTransportProbePolicy(
            mode: .sendReadOnlyProbe,
            route: route,
            allowBoundedArtifactFetch: allowBoundedArtifactFetch,
            internalConfigurationEnabled: internalConfigurationEnabled
        )
    }

    nonisolated var classificationPolicy: CanonicalReadOnlyTransportProbePolicy {
        CanonicalReadOnlyTransportProbePolicy.enabled(
            allowBoundedArtifactFetch: allowBoundedArtifactFetch,
            allowNetworkSend: mode == .sendReadOnlyProbe && internalConfigurationEnabled
        )
    }
}

nonisolated struct CanonicalLiveReadOnlyTransportProbeGate: Codable, Equatable, Sendable {
    var mode: CanonicalLiveReadOnlyTransportProbeMode
    var route: CanonicalLiveReadOnlyTransportProbeRoute
    var routeStatus: CanonicalReadOnlyTransportProbeRouteStatus
    var shouldClassify: Bool
    var shouldBuildEnvelope: Bool
    var shouldSend: Bool
    var blocked: Bool
    var suppressed: Bool
    var failure: CanonicalLiveReadOnlyTransportProbeFailure?
    var reason: String

    nonisolated init(
        mode: CanonicalLiveReadOnlyTransportProbeMode,
        route: CanonicalLiveReadOnlyTransportProbeRoute,
        routeStatus: CanonicalReadOnlyTransportProbeRouteStatus,
        shouldClassify: Bool,
        shouldBuildEnvelope: Bool,
        shouldSend: Bool,
        blocked: Bool,
        suppressed: Bool,
        failure: CanonicalLiveReadOnlyTransportProbeFailure?,
        reason: String
    ) {
        self.mode = mode
        self.route = route
        self.routeStatus = routeStatus
        self.shouldClassify = shouldClassify
        self.shouldBuildEnvelope = shouldBuildEnvelope
        self.shouldSend = shouldSend
        self.blocked = blocked
        self.suppressed = suppressed
        self.failure = failure
        self.reason = CanonicalShadowMigrationRedaction.safeText(reason) ?? failure?.rawValue ?? mode.rawValue
    }

    nonisolated static func evaluate(
        policy: CanonicalLiveReadOnlyTransportProbePolicy,
        bodyByteCount: Int
    ) -> CanonicalLiveReadOnlyTransportProbeGate {
        guard policy.mode != .disabled else {
            return CanonicalLiveReadOnlyTransportProbeGate(
                mode: .disabled,
                route: policy.route,
                routeStatus: .suppressedDisabled,
                shouldClassify: false,
                shouldBuildEnvelope: false,
                shouldSend: false,
                blocked: false,
                suppressed: true,
                failure: .disabled,
                reason: "liveReadOnlyProbeDisabled"
            )
        }

        let routeDecision = policy.classificationPolicy.routeStatus(for: policy.route, bodyByteCount: bodyByteCount)
        if routeDecision.0 == .rejectedMutating || policy.mode == .blockedMutatingRoute {
            return CanonicalLiveReadOnlyTransportProbeGate(
                mode: .blockedMutatingRoute,
                route: policy.route,
                routeStatus: .rejectedMutating,
                shouldClassify: true,
                shouldBuildEnvelope: false,
                shouldSend: false,
                blocked: true,
                suppressed: true,
                failure: .mutatingRouteRejected,
                reason: "mutatingRouteProbeBlocked"
            )
        }

        if let failure = routeDecision.1 {
            return CanonicalLiveReadOnlyTransportProbeGate(
                mode: policy.mode,
                route: policy.route,
                routeStatus: routeDecision.0,
                shouldClassify: true,
                shouldBuildEnvelope: false,
                shouldSend: false,
                blocked: true,
                suppressed: true,
                failure: CanonicalLiveReadOnlyTransportProbeFailure(readOnlyFailure: failure),
                reason: failure.rawValue
            )
        }

        if policy.mode == .sendReadOnlyProbe, !policy.internalConfigurationEnabled {
            return CanonicalLiveReadOnlyTransportProbeGate(
                mode: policy.mode,
                route: policy.route,
                routeStatus: routeDecision.0,
                shouldClassify: true,
                shouldBuildEnvelope: false,
                shouldSend: false,
                blocked: true,
                suppressed: true,
                failure: .internalConfigurationMissing,
                reason: "internalConfigurationMissing"
            )
        }

        switch policy.mode {
        case .classifyOnly:
            return CanonicalLiveReadOnlyTransportProbeGate(
                mode: policy.mode,
                route: policy.route,
                routeStatus: routeDecision.0,
                shouldClassify: true,
                shouldBuildEnvelope: false,
                shouldSend: false,
                blocked: false,
                suppressed: true,
                failure: .networkSuppressed,
                reason: "classifyOnly"
            )
        case .buildSignedEnvelopeOnly:
            return CanonicalLiveReadOnlyTransportProbeGate(
                mode: policy.mode,
                route: policy.route,
                routeStatus: routeDecision.0,
                shouldClassify: true,
                shouldBuildEnvelope: true,
                shouldSend: false,
                blocked: false,
                suppressed: true,
                failure: .networkSuppressed,
                reason: "buildSignedEnvelopeOnly"
            )
        case .sendReadOnlyProbe:
            return CanonicalLiveReadOnlyTransportProbeGate(
                mode: policy.mode,
                route: policy.route,
                routeStatus: routeDecision.0,
                shouldClassify: true,
                shouldBuildEnvelope: true,
                shouldSend: true,
                blocked: false,
                suppressed: false,
                failure: nil,
                reason: "sendReadOnlyProbe"
            )
        case .disabled, .blockedMutatingRoute:
            return CanonicalLiveReadOnlyTransportProbeGate(
                mode: .disabled,
                route: policy.route,
                routeStatus: .suppressedDisabled,
                shouldClassify: false,
                shouldBuildEnvelope: false,
                shouldSend: false,
                blocked: false,
                suppressed: true,
                failure: .disabled,
                reason: "liveReadOnlyProbeDisabled"
            )
        }
    }
}

nonisolated struct CanonicalLiveReadOnlyTransportProbeResult: Codable, Equatable, Sendable {
    var mode: CanonicalLiveReadOnlyTransportProbeMode
    var route: CanonicalLiveReadOnlyTransportProbeRoute
    var routeStatus: CanonicalReadOnlyTransportProbeRouteStatus
    var envelopeBuilt: Bool
    var sentNetwork: Bool
    var completed: Bool
    var blocked: Bool
    var suppressed: Bool
    var authBoundaryPreserved: Bool
    var failure: CanonicalLiveReadOnlyTransportProbeFailure?
    var httpStatusCode: Int?
    var responseByteCount: Int?
    var diagnostics: [CanonicalLiveReadOnlyTransportProbeDiagnosticKind]
    var reason: String

    nonisolated init(
        mode: CanonicalLiveReadOnlyTransportProbeMode,
        route: CanonicalLiveReadOnlyTransportProbeRoute,
        routeStatus: CanonicalReadOnlyTransportProbeRouteStatus,
        envelopeBuilt: Bool = false,
        sentNetwork: Bool = false,
        completed: Bool = false,
        blocked: Bool = false,
        suppressed: Bool = true,
        authBoundaryPreserved: Bool = false,
        failure: CanonicalLiveReadOnlyTransportProbeFailure? = nil,
        httpStatusCode: Int? = nil,
        responseByteCount: Int? = nil,
        diagnostics: [CanonicalLiveReadOnlyTransportProbeDiagnosticKind] = [],
        reason: String
    ) {
        self.mode = mode
        self.route = route
        self.routeStatus = routeStatus
        self.envelopeBuilt = envelopeBuilt
        self.sentNetwork = sentNetwork
        self.completed = completed
        self.blocked = blocked
        self.suppressed = suppressed
        self.authBoundaryPreserved = authBoundaryPreserved
        self.failure = failure
        self.httpStatusCode = httpStatusCode
        self.responseByteCount = responseByteCount
        self.diagnostics = Array(Set(diagnostics)).sorted { $0.rawValue < $1.rawValue }
        self.reason = CanonicalShadowMigrationRedaction.safeText(reason) ?? failure?.rawValue ?? mode.rawValue
    }

    nonisolated var diagnosticsSummary: String {
        [
            "mode=\(mode.rawValue)",
            "route=\(route.method) \(route.path)",
            "routeStatus=\(routeStatus.rawValue)",
            "envelopeBuilt=\(envelopeBuilt)",
            "sent=\(sentNetwork)",
            "completed=\(completed)",
            "blocked=\(blocked)",
            "suppressed=\(suppressed)",
            "authBoundaryPreserved=\(authBoundaryPreserved)",
            "httpStatus=\(httpStatusCode.map(String.init) ?? "none")",
            "responseBytes=\(responseByteCount.map(String.init) ?? "none")",
            "failure=\(failure?.rawValue ?? "none")",
            "reason=\(reason)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalReadOnlyTransportProbePolicy: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var allowBoundedArtifactFetch: Bool
    var artifactFetchMaxBytes: Int
    var allowNetworkSend: Bool
    var allowedRoutes: [CanonicalReadOnlyTransportProbeRoute]

    nonisolated init(
        isEnabled: Bool = false,
        allowBoundedArtifactFetch: Bool = false,
        artifactFetchMaxBytes: Int = 256 * 1024,
        allowNetworkSend: Bool = false,
        allowedRoutes: [CanonicalReadOnlyTransportProbeRoute] = [
            .health,
            .fingerprint,
            .syncInventory
        ]
    ) {
        self.isEnabled = isEnabled
        self.allowBoundedArtifactFetch = allowBoundedArtifactFetch
        self.artifactFetchMaxBytes = max(0, artifactFetchMaxBytes)
        self.allowNetworkSend = allowNetworkSend
        self.allowedRoutes = Array(Set(allowedRoutes)).sorted { "\($0.method) \($0.path)" < "\($1.method) \($1.path)" }
    }

    nonisolated static let disabled = CanonicalReadOnlyTransportProbePolicy()

    nonisolated static func enabled(
        allowBoundedArtifactFetch: Bool = false,
        allowNetworkSend: Bool = false
    ) -> CanonicalReadOnlyTransportProbePolicy {
        var routes: [CanonicalReadOnlyTransportProbeRoute] = [
            .health,
            .fingerprint,
            .syncInventory
        ]
        if allowBoundedArtifactFetch {
            routes.append(.artifactRequest)
        }
        return CanonicalReadOnlyTransportProbePolicy(
            isEnabled: true,
            allowBoundedArtifactFetch: allowBoundedArtifactFetch,
            allowNetworkSend: allowNetworkSend,
            allowedRoutes: routes
        )
    }

    nonisolated func routeStatus(for route: CanonicalReadOnlyTransportProbeRoute, bodyByteCount: Int) -> (CanonicalReadOnlyTransportProbeRouteStatus, CanonicalReadOnlyTransportProbeFailure?) {
        guard isEnabled else {
            return (.suppressedDisabled, .disabled)
        }
        guard route.isKnownReadOnlyRoute else {
            return (route.isKnownMutatingRoute ? .rejectedMutating : .rejectedUnknown, route.isKnownMutatingRoute ? .mutatingRouteRejected : .unknownRouteRejected)
        }
        if route == .artifactRequest {
            guard allowBoundedArtifactFetch else {
                return (.rejectedMutating, .artifactFetchNotAllowed)
            }
            guard bodyByteCount <= artifactFetchMaxBytes else {
                return (.rejectedMutating, .artifactFetchTooLarge)
            }
        }
        guard allowedRoutes.contains(route) else {
            return (.rejectedUnknown, .unknownRouteRejected)
        }
        return (.allowedReadOnly, nil)
    }
}

extension CanonicalLiveReadOnlyTransportProbeFailure {
    nonisolated init(readOnlyFailure: CanonicalReadOnlyTransportProbeFailure) {
        switch readOnlyFailure {
        case .disabled:
            self = .disabled
        case .mutatingRouteRejected:
            self = .mutatingRouteRejected
        case .unknownRouteRejected:
            self = .unknownRouteRejected
        case .artifactFetchNotAllowed:
            self = .artifactFetchNotAllowed
        case .artifactFetchTooLarge:
            self = .artifactFetchTooLarge
        case .authBoundaryMissing:
            self = .authBoundaryMissing
        case .manifestHashUsedAsAuth:
            self = .manifestHashUsedAsAuth
        case .networkSuppressed:
            self = .networkSuppressed
        case .sendFailed:
            self = .sendFailed
        }
    }
}

extension CanonicalReadOnlyTransportProbeRoute {
    nonisolated var isKnownReadOnlyRoute: Bool {
        switch (method, path) {
        case ("GET", "/health"),
             ("GET", "/fingerprint"),
             ("POST", "/sync/inventory"):
            return true
        case ("POST", "/sync/artifact-request"):
            return true
        default:
            return false
        }
    }

    nonisolated var isKnownMutatingRoute: Bool {
        switch (method, path) {
        case ("POST", "/pair"),
             ("POST", "/upload-secure-test"),
             ("POST", "/upload-recording-metadata"),
             ("POST", "/upload-recording-audio"),
             ("POST", "/upload-recording-audio-session/start"),
             ("POST", "/upload-recording-audio-session/status"),
             ("POST", "/upload-recording-audio-session/chunk"),
             ("POST", "/upload-recording-audio-session/finalize"),
             ("POST", "/device/status"),
             ("POST", "/sync/status"),
             ("POST", "/sync/apply"),
             ("POST", "/sync/apply-metadata"),
             ("POST", "/sync/manifest"):
            return true
        default:
            return false
        }
    }
}

nonisolated struct CanonicalReadOnlyTransportProbeRequest: Codable, Equatable, Sendable {
    var route: CanonicalReadOnlyTransportProbeRoute
    var bodyByteCount: Int
    var bodyHashPrefix: String?
    var timestampPresent: Bool
    var noncePresent: Bool
    var signaturePresent: Bool
    var tlsPinningPreserved: Bool
    var hmacPreserved: Bool
    var bodyHashPreserved: Bool
    var manifestHashPresent: Bool
    var manifestHashUsedAsAuth: Bool

    nonisolated init(
        route: CanonicalReadOnlyTransportProbeRoute,
        bodyByteCount: Int = 0,
        bodyHash: CanonicalHash? = nil,
        timestampPresent: Bool = true,
        noncePresent: Bool = true,
        signaturePresent: Bool = true,
        tlsPinningPreserved: Bool = true,
        hmacPreserved: Bool = true,
        bodyHashPreserved: Bool = true,
        manifestHashPresent: Bool = false,
        manifestHashUsedAsAuth: Bool = false
    ) {
        self.route = route
        self.bodyByteCount = max(0, bodyByteCount)
        self.bodyHashPrefix = bodyHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.timestampPresent = timestampPresent
        self.noncePresent = noncePresent
        self.signaturePresent = signaturePresent
        self.tlsPinningPreserved = tlsPinningPreserved
        self.hmacPreserved = hmacPreserved
        self.bodyHashPreserved = bodyHashPreserved
        self.manifestHashPresent = manifestHashPresent
        self.manifestHashUsedAsAuth = manifestHashUsedAsAuth
    }

    nonisolated var authBoundaryPreserved: Bool {
        tlsPinningPreserved && hmacPreserved && bodyHashPreserved && timestampPresent && noncePresent && signaturePresent && !manifestHashUsedAsAuth
    }
}

nonisolated struct CanonicalReadOnlyTransportProbeAudit: Codable, Equatable, Sendable {
    var route: CanonicalReadOnlyTransportProbeRoute
    var routeStatus: CanonicalReadOnlyTransportProbeRouteStatus
    var requestSent: Bool
    var requestSuppressed: Bool
    var authBoundaryPreserved: Bool
    var manifestHashUsedAsAuth: Bool
    var reason: String

    nonisolated init(
        route: CanonicalReadOnlyTransportProbeRoute,
        routeStatus: CanonicalReadOnlyTransportProbeRouteStatus,
        requestSent: Bool,
        requestSuppressed: Bool,
        authBoundaryPreserved: Bool,
        manifestHashUsedAsAuth: Bool,
        reason: String
    ) {
        self.route = route
        self.routeStatus = routeStatus
        self.requestSent = requestSent
        self.requestSuppressed = requestSuppressed
        self.authBoundaryPreserved = authBoundaryPreserved
        self.manifestHashUsedAsAuth = manifestHashUsedAsAuth
        self.reason = CanonicalShadowMigrationRedaction.safeText(reason) ?? routeStatus.rawValue
    }
}

nonisolated struct CanonicalReadOnlyTransportProbeResult: Codable, Equatable, Sendable {
    var status: String
    var routeStatus: CanonicalReadOnlyTransportProbeRouteStatus
    var sentNetwork: Bool
    var blocked: Bool
    var suppressed: Bool
    var authBoundaryPreserved: Bool
    var failure: CanonicalReadOnlyTransportProbeFailure?
    var audit: CanonicalReadOnlyTransportProbeAudit

    nonisolated init(
        status: String,
        routeStatus: CanonicalReadOnlyTransportProbeRouteStatus,
        sentNetwork: Bool,
        blocked: Bool,
        suppressed: Bool,
        authBoundaryPreserved: Bool,
        failure: CanonicalReadOnlyTransportProbeFailure?,
        audit: CanonicalReadOnlyTransportProbeAudit
    ) {
        self.status = CanonicalShadowMigrationRedaction.safeText(status) ?? routeStatus.rawValue
        self.routeStatus = routeStatus
        self.sentNetwork = sentNetwork
        self.blocked = blocked
        self.suppressed = suppressed
        self.authBoundaryPreserved = authBoundaryPreserved
        self.failure = failure
        self.audit = audit
    }

    nonisolated var diagnosticsSummary: String {
        [
            "probe=\(status)",
            "route=\(audit.route.method) \(audit.route.path)",
            "routeStatus=\(routeStatus.rawValue)",
            "sent=\(sentNetwork)",
            "suppressed=\(suppressed)",
            "blocked=\(blocked)",
            "authBoundaryPreserved=\(authBoundaryPreserved)",
            "manifestHashAuth=\(audit.manifestHashUsedAsAuth)",
            "failure=\(failure?.rawValue ?? "none")"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalReadOnlyTransportProbe: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        request: CanonicalReadOnlyTransportProbeRequest,
        policy: CanonicalReadOnlyTransportProbePolicy = .disabled
    ) -> CanonicalReadOnlyTransportProbeResult {
        let routeDecision = policy.routeStatus(for: request.route, bodyByteCount: request.bodyByteCount)
        if request.manifestHashUsedAsAuth {
            return result(
                request: request,
                routeStatus: routeDecision.0,
                sentNetwork: false,
                blocked: true,
                suppressed: true,
                failure: .manifestHashUsedAsAuth,
                reason: "manifestHashNotAuth"
            )
        }
        guard request.authBoundaryPreserved else {
            return result(
                request: request,
                routeStatus: routeDecision.0,
                sentNetwork: false,
                blocked: true,
                suppressed: true,
                failure: .authBoundaryMissing,
                reason: "authBoundaryMissing"
            )
        }
        if let failure = routeDecision.1 {
            return result(
                request: request,
                routeStatus: routeDecision.0,
                sentNetwork: false,
                blocked: routeDecision.0 != .suppressedDisabled,
                suppressed: true,
                failure: failure,
                reason: failure.rawValue
            )
        }
        let shouldSend = policy.allowNetworkSend
        return result(
            request: request,
            routeStatus: routeDecision.0,
            sentNetwork: shouldSend,
            blocked: false,
            suppressed: !shouldSend,
            failure: shouldSend ? nil : .networkSuppressed,
            reason: shouldSend ? "readOnlyProbeSent" : "readOnlyProbeSuppressed"
        )
    }

    nonisolated func request(
        signedRequest: CanonicalProductionSignedRequest,
        route: CanonicalReadOnlyTransportProbeRoute,
        tlsPinningPreserved: Bool = true,
        hmacPreserved: Bool = true,
        manifestHashPresent: Bool = false,
        manifestHashUsedAsAuth: Bool = false
    ) -> CanonicalReadOnlyTransportProbeRequest {
        CanonicalReadOnlyTransportProbeRequest(
            route: route,
            bodyByteCount: signedRequest.buildRequest.body.count,
            bodyHash: signedRequest.bodyHash,
            timestampPresent: true,
            noncePresent: !signedRequest.buildRequest.nonce.isEmpty,
            signaturePresent: signedRequest.signaturePrefix != nil || signedRequest.signerDescription != nil,
            tlsPinningPreserved: tlsPinningPreserved,
            hmacPreserved: hmacPreserved,
            bodyHashPreserved: CanonicalTransportEnvelope.hash(signedRequest.buildRequest.body) == signedRequest.bodyHash,
            manifestHashPresent: manifestHashPresent,
            manifestHashUsedAsAuth: manifestHashUsedAsAuth
        )
    }

    private nonisolated func result(
        request: CanonicalReadOnlyTransportProbeRequest,
        routeStatus: CanonicalReadOnlyTransportProbeRouteStatus,
        sentNetwork: Bool,
        blocked: Bool,
        suppressed: Bool,
        failure: CanonicalReadOnlyTransportProbeFailure?,
        reason: String
    ) -> CanonicalReadOnlyTransportProbeResult {
        let status: String
        if blocked {
            status = "blocked"
        } else if sentNetwork {
            status = "completed"
        } else if suppressed {
            status = routeStatus == .suppressedDisabled ? "disabled" : "suppressed"
        } else {
            status = "completed"
        }
        let audit = CanonicalReadOnlyTransportProbeAudit(
            route: request.route,
            routeStatus: routeStatus,
            requestSent: sentNetwork,
            requestSuppressed: suppressed,
            authBoundaryPreserved: request.authBoundaryPreserved,
            manifestHashUsedAsAuth: request.manifestHashUsedAsAuth,
            reason: reason
        )
        return CanonicalReadOnlyTransportProbeResult(
            status: status,
            routeStatus: routeStatus,
            sentNetwork: sentNetwork,
            blocked: blocked,
            suppressed: suppressed,
            authBoundaryPreserved: request.authBoundaryPreserved,
            failure: failure,
            audit: audit
        )
    }
}

extension CanonicalShadowTransportProbe {
    nonisolated func projectReadOnly(
        signedRequest: CanonicalProductionSignedRequest,
        route: CanonicalReadOnlyTransportProbeRoute,
        policy: CanonicalReadOnlyTransportProbePolicy
    ) -> CanonicalReadOnlyTransportProbeResult {
        let request = CanonicalReadOnlyTransportProbe().request(
            signedRequest: signedRequest,
            route: route
        )
        return CanonicalReadOnlyTransportProbe().evaluate(request: request, policy: policy)
    }
}
