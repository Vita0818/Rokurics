//
//  CanonicalPerfLog.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/20.
//

import Foundation

nonisolated enum CanonicalPerfLog {
    static let defaultJankThresholdMs = 800

    nonisolated enum Operation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
        case enterStudyLibrary
        case immediateSync
        case upload
    }

    nonisolated enum Subphase: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
        case inventoryBuildMs
        case projectionRebuildMs
        case hashMs
        case applyMs
        case waitBackgroundMs
    }

    nonisolated struct StageDurations: Codable, Equatable, Hashable, Sendable {
        var inventoryBuildMs: Int?
        var projectionRebuildMs: Int?
        var hashMs: Int?
        var applyMs: Int?
        var waitBackgroundMs: Int?

        nonisolated init(
            inventoryBuildMs: Int? = nil,
            projectionRebuildMs: Int? = nil,
            hashMs: Int? = nil,
            applyMs: Int? = nil,
            waitBackgroundMs: Int? = nil
        ) {
            self.inventoryBuildMs = inventoryBuildMs.map(Self.clamped)
            self.projectionRebuildMs = projectionRebuildMs.map(Self.clamped)
            self.hashMs = hashMs.map(Self.clamped)
            self.applyMs = applyMs.map(Self.clamped)
            self.waitBackgroundMs = waitBackgroundMs.map(Self.clamped)
        }

        nonisolated static var empty: StageDurations {
            StageDurations()
        }

        nonisolated var isEmpty: Bool {
            Self.orderedSubphases.allSatisfy { duration(for: $0) == nil }
        }

        nonisolated func duration(for subphase: Subphase) -> Int? {
            switch subphase {
            case .inventoryBuildMs:
                return inventoryBuildMs
            case .projectionRebuildMs:
                return projectionRebuildMs
            case .hashMs:
                return hashMs
            case .applyMs:
                return applyMs
            case .waitBackgroundMs:
                return waitBackgroundMs
            }
        }

        nonisolated mutating func set(_ subphase: Subphase, durationMs: Int?) {
            let value = durationMs.map(Self.clamped)
            switch subphase {
            case .inventoryBuildMs:
                inventoryBuildMs = value
            case .projectionRebuildMs:
                projectionRebuildMs = value
            case .hashMs:
                hashMs = value
            case .applyMs:
                applyMs = value
            case .waitBackgroundMs:
                waitBackgroundMs = value
            }
        }

        nonisolated mutating func mergeMax(_ other: StageDurations) {
            for subphase in Self.orderedSubphases {
                guard let otherDuration = other.duration(for: subphase) else {
                    continue
                }
                let current = duration(for: subphase) ?? 0
                set(subphase, durationMs: max(current, otherDuration))
            }
        }

        nonisolated func normalized(totalMs: Int?) -> StageDurations {
            guard let totalMs else {
                return self
            }
            var next = self
            let knownBackgroundMs = [
                inventoryBuildMs,
                projectionRebuildMs,
                hashMs,
                applyMs
            ]
            .compactMap { $0 }
            .reduce(0, +)

            if next.waitBackgroundMs == nil {
                next.waitBackgroundMs = max(0, totalMs - knownBackgroundMs)
            }
            if next.isEmpty {
                next.waitBackgroundMs = max(0, totalMs)
            }
            return next
        }

        nonisolated var dominant: (subphase: Subphase, durationMs: Int)? {
            Self.orderedSubphases
                .compactMap { subphase -> (Subphase, Int)? in
                    guard let duration = duration(for: subphase) else {
                        return nil
                    }
                    return (subphase, duration)
                }
                .max { left, right in
                    if left.1 == right.1 {
                        return Self.rank(left.0) > Self.rank(right.0)
                    }
                    return left.1 < right.1
                }
                .map { ($0.0, $0.1) }
        }

        private nonisolated static let orderedSubphases: [Subphase] = [
            .inventoryBuildMs,
            .projectionRebuildMs,
            .hashMs,
            .applyMs,
            .waitBackgroundMs
        ]

        private nonisolated static func rank(_ subphase: Subphase) -> Int {
            orderedSubphases.firstIndex(of: subphase) ?? orderedSubphases.count
        }

        private nonisolated static func clamped(_ value: Int) -> Int {
            max(0, value)
        }
    }

    nonisolated struct Record: Codable, Equatable, Hashable, Sendable {
        var phase: String
        var operation: Operation?
        var totalMs: Int?
        var dominantSubphase: Subphase?
        var dominantSubphaseMs: Int?
        var inventoryBuildMs: Int?
        var projectionRebuildMs: Int?
        var hashMs: Int?
        var applyMs: Int?
        var waitBackgroundMs: Int?
        var result: String?

        nonisolated init(
            phase: String,
            operation: Operation?,
            totalMs: Int?,
            stages: StageDurations = .empty,
            result: String? = nil
        ) {
            let normalizedTotalMs = totalMs.map { max(0, $0) }
            let normalizedStages = stages.normalized(totalMs: normalizedTotalMs)
            let dominant = normalizedStages.dominant
            self.phase = phase
            self.operation = operation
            self.totalMs = normalizedTotalMs
            self.dominantSubphase = dominant?.subphase
            self.dominantSubphaseMs = dominant?.durationMs
            self.inventoryBuildMs = normalizedStages.inventoryBuildMs
            self.projectionRebuildMs = normalizedStages.projectionRebuildMs
            self.hashMs = normalizedStages.hashMs
            self.applyMs = normalizedStages.applyMs
            self.waitBackgroundMs = normalizedStages.waitBackgroundMs
            self.result = CanonicalKernelStringSanitizer.optional(result)
        }
    }

    nonisolated static func started(
        operation: Operation,
        result: String? = nil
    ) -> Record {
        Record(
            phase: "operationStarted",
            operation: operation,
            totalMs: 0,
            result: result
        )
    }

    nonisolated static func finishedRecords(
        operation: Operation,
        totalMs: Int,
        stages: StageDurations = .empty,
        result: String? = nil,
        jankThresholdMs: Int = defaultJankThresholdMs
    ) -> [Record] {
        let finished = Record(
            phase: "operationFinished",
            operation: operation,
            totalMs: totalMs,
            stages: stages,
            result: result
        )
        guard totalMs > jankThresholdMs else {
            return [finished]
        }
        let jank = Record(
            phase: "jankDetected",
            operation: operation,
            totalMs: totalMs,
            stages: stages,
            result: finished.dominantSubphase?.rawValue ?? result
        )
        return [finished, jank]
    }

    nonisolated static func subphaseMeasured(
        operation: Operation?,
        subphase: Subphase,
        durationMs: Int,
        result: String? = nil
    ) -> Record {
        var stages = StageDurations.empty
        stages.set(subphase, durationMs: durationMs)
        return Record(
            phase: "subphaseMeasured",
            operation: operation,
            totalMs: durationMs,
            stages: stages,
            result: result ?? subphase.rawValue
        )
    }

    nonisolated static func elapsedMs(since startedAt: Date, now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(startedAt) * 1_000))
    }
}
