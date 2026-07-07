//
//  CanonicalAsyncDiagnosticsWriter.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated protocol CanonicalAsyncDiagnosticsSink: Sendable {
    func writeJSONLLine(_ data: Data) async throws
}

actor CanonicalInMemoryDiagnosticsSink: CanonicalAsyncDiagnosticsSink {
    private var lines: [String] = []

    func writeJSONLLine(_ data: Data) async throws {
        lines.append(String(data: data, encoding: .utf8) ?? "")
    }

    func allLines() -> [String] {
        lines
    }
}

nonisolated struct CanonicalAsyncDiagnosticsWriterConfiguration: Codable, Equatable, Hashable, Sendable {
    var maxQueuedEvents: Int
    var dropNewestWhenFull: Bool
    var automaticallyFlush: Bool

    nonisolated init(
        maxQueuedEvents: Int = 256,
        dropNewestWhenFull: Bool = true,
        automaticallyFlush: Bool = true
    ) {
        self.maxQueuedEvents = max(1, maxQueuedEvents)
        self.dropNewestWhenFull = dropNewestWhenFull
        self.automaticallyFlush = automaticallyFlush
    }
}

nonisolated enum CanonicalAsyncDiagnosticsEnqueueDisposition: String, Codable, Equatable, Hashable, Sendable {
    case enqueued
    case droppedBackpressure
    case rejectedRedaction
}

nonisolated struct CanonicalAsyncDiagnosticsWriterMetrics: Codable, Equatable, Hashable, Sendable {
    var enqueuedCount: Int = 0
    var writtenCount: Int = 0
    var droppedCount: Int = 0
    var rejectedCount: Int = 0
    var diagnosticsWriteDurationMs: Int = 0
}

actor CanonicalFileDiagnosticsSink: CanonicalAsyncDiagnosticsSink {
    private let logURL: URL
    private let fileManager: FileManager
    private let maxPersistedLines: Int
    private var writesSinceCompaction = 0

    init(
        logURL: URL,
        fileManager: FileManager = .default,
        maxPersistedLines: Int = 200
    ) {
        self.logURL = logURL
        self.fileManager = fileManager
        self.maxPersistedLines = max(1, maxPersistedLines)
    }

    func writeJSONLLine(_ data: Data) async throws {
        try fileManager.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: logURL)
        }
        writesSinceCompaction += 1
        if writesSinceCompaction >= maxPersistedLines {
            try compactToMostRecentLines()
            writesSinceCompaction = 0
        }
    }

    private func compactToMostRecentLines() throws {
        guard fileManager.fileExists(atPath: logURL.path),
              let rawText = try? String(contentsOf: logURL, encoding: .utf8) else {
            return
        }
        let lines = rawText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(maxPersistedLines)
        let compacted = lines.joined(separator: "\n")
        try Data((compacted + "\n").utf8).write(to: logURL, options: .atomic)
    }
}

private enum CanonicalAsyncDiagnosticsPayload: Sendable {
    case kernelRecord(CanonicalKernelDiagnosticRecord)
    case rawJSONLLine(Data)
}

actor CanonicalAsyncDiagnosticsWriter {
    private let sink: any CanonicalAsyncDiagnosticsSink
    private let configuration: CanonicalAsyncDiagnosticsWriterConfiguration
    private let clock: CanonicalInventoryRuntimeClock
    private var queue: [CanonicalAsyncDiagnosticsPayload] = []
    private var flushing = false
    private var metrics = CanonicalAsyncDiagnosticsWriterMetrics()

    init(
        sink: any CanonicalAsyncDiagnosticsSink,
        configuration: CanonicalAsyncDiagnosticsWriterConfiguration = CanonicalAsyncDiagnosticsWriterConfiguration(),
        clock: CanonicalInventoryRuntimeClock = .system
    ) {
        self.sink = sink
        self.configuration = configuration
        self.clock = clock
    }

    func enqueue(_ record: CanonicalKernelDiagnosticRecord) -> CanonicalAsyncDiagnosticsEnqueueDisposition {
        if let detail = record.redactedDetail,
           !CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(detail) {
            metrics.rejectedCount += 1
            return .rejectedRedaction
        }
        return enqueuePayload(.kernelRecord(record))
    }

    func enqueueJSONLLine(_ data: Data) -> CanonicalAsyncDiagnosticsEnqueueDisposition {
        guard let encoded = String(data: data, encoding: .utf8),
              CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(encoded) else {
            metrics.rejectedCount += 1
            return .rejectedRedaction
        }
        return enqueuePayload(.rawJSONLLine(data))
    }

    private func enqueuePayload(_ payload: CanonicalAsyncDiagnosticsPayload) -> CanonicalAsyncDiagnosticsEnqueueDisposition {
        guard queue.count < configuration.maxQueuedEvents else {
            metrics.droppedCount += 1
            if configuration.dropNewestWhenFull {
                return .droppedBackpressure
            }
            queue.removeFirst()
            queue.append(payload)
            metrics.enqueuedCount += 1
            startFlushIfNeeded()
            return .enqueued
        }
        queue.append(payload)
        metrics.enqueuedCount += 1
        startFlushIfNeeded()
        return .enqueued
    }

    func drain() async {
        await flush()
    }

    func flushForTests() async {
        await flush()
    }

    func drainForTests() async {
        await flush()
    }

    func currentMetrics() -> CanonicalAsyncDiagnosticsWriterMetrics {
        metrics
    }

    private func startFlushIfNeeded() {
        guard configuration.automaticallyFlush else {
            return
        }
        guard !flushing else {
            return
        }
        flushing = true
        Task {
            await self.flush()
        }
    }

    private func flush() async {
        while !queue.isEmpty {
            let payload = queue.removeFirst()
            let startedAt = clock.now()
            do {
                let data = try Self.data(for: payload)
                if let encoded = String(data: data, encoding: .utf8),
                   !CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(encoded) {
                    metrics.rejectedCount += 1
                    continue
                }
                try await sink.writeJSONLLine(data)
                metrics.writtenCount += 1
            } catch {
                metrics.droppedCount += 1
            }
            metrics.diagnosticsWriteDurationMs += max(0, Int(clock.now().timeIntervalSince(startedAt) * 1_000))
        }
        flushing = false
    }

    private nonisolated static func data(for payload: CanonicalAsyncDiagnosticsPayload) throws -> Data {
        switch payload {
        case .kernelRecord(let record):
            return try encodeJSONL(record)
        case .rawJSONLLine(let data):
            if data.last == 0x0A {
                return data
            }
            var line = data
            line.append(0x0A)
            return line
        }
    }

    private nonisolated static func encodeJSONL(_ record: CanonicalKernelDiagnosticRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(record)
        data.append(0x0A)
        return data
    }
}
