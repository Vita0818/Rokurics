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

nonisolated enum CanonicalAsyncDiagnosticsPriority: Int, Codable, Equatable, Hashable, Sendable {
    case normal
    case critical
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

private enum CanonicalAsyncDiagnosticsPayloadBody: Sendable {
    case kernelRecord(CanonicalKernelDiagnosticRecord)
    case rawJSONLLine(Data)
}

private struct CanonicalAsyncDiagnosticsPayload: Sendable {
    var body: CanonicalAsyncDiagnosticsPayloadBody
    var priority: CanonicalAsyncDiagnosticsPriority
}

actor CanonicalAsyncDiagnosticsWriter {
    private let sink: any CanonicalAsyncDiagnosticsSink
    private let configuration: CanonicalAsyncDiagnosticsWriterConfiguration
    private let clock: CanonicalInventoryRuntimeClock
    private var queue: [CanonicalAsyncDiagnosticsPayload] = []
    private var automaticFlushTask: Task<Void, Never>?
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

    func enqueue(
        _ record: CanonicalKernelDiagnosticRecord,
        priority: CanonicalAsyncDiagnosticsPriority = .normal
    ) -> CanonicalAsyncDiagnosticsEnqueueDisposition {
        if let detail = record.redactedDetail,
           !CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(detail) {
            metrics.rejectedCount += 1
            return .rejectedRedaction
        }
        return enqueuePayload(CanonicalAsyncDiagnosticsPayload(body: .kernelRecord(record), priority: priority))
    }

    func enqueueJSONLLine(
        _ data: Data,
        priority: CanonicalAsyncDiagnosticsPriority = .normal
    ) -> CanonicalAsyncDiagnosticsEnqueueDisposition {
        guard let encoded = String(data: data, encoding: .utf8),
              CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(encoded) else {
            metrics.rejectedCount += 1
            return .rejectedRedaction
        }
        return enqueuePayload(CanonicalAsyncDiagnosticsPayload(body: .rawJSONLLine(data), priority: priority))
    }

    private func enqueuePayload(_ payload: CanonicalAsyncDiagnosticsPayload) -> CanonicalAsyncDiagnosticsEnqueueDisposition {
        guard queue.count < configuration.maxQueuedEvents else {
            if payload.priority == .critical {
                let evictionIndex = queue.firstIndex { $0.priority == .normal } ?? queue.startIndex
                queue.remove(at: evictionIndex)
                queue.append(payload)
                metrics.droppedCount += 1
                metrics.enqueuedCount += 1
                startFlushIfNeeded()
                return .enqueued
            }

            guard configuration.dropNewestWhenFull == false,
                  let evictionIndex = queue.firstIndex(where: { $0.priority == .normal }) else {
                metrics.droppedCount += 1
                return .droppedBackpressure
            }
            queue.remove(at: evictionIndex)
            queue.append(payload)
            metrics.droppedCount += 1
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
        await flushUntilIdle()
    }

    func flushForTests() async {
        await flushUntilIdle()
    }

    func drainForTests() async {
        await flushUntilIdle()
    }

    func currentMetrics() -> CanonicalAsyncDiagnosticsWriterMetrics {
        metrics
    }

    private func startFlushIfNeeded() {
        guard configuration.automaticallyFlush else {
            return
        }
        guard automaticFlushTask == nil else {
            return
        }
        automaticFlushTask = Task { await self.runAutomaticFlush() }
    }

    private func runAutomaticFlush() async {
        await flushQueue()
        automaticFlushTask = nil
        if !queue.isEmpty {
            startFlushIfNeeded()
        }
    }

    /// Waits for the automatic worker that may already own an in-flight sink
    /// write. Calling `flushQueue()` concurrently used to let this method
    /// observe an empty queue and return while the worker's final write was
    /// still suspended in the sink, so callers could read a truncated log.
    private func flushUntilIdle() async {
        while true {
            if let task = automaticFlushTask {
                await task.value
                continue
            }
            guard !queue.isEmpty else {
                return
            }
            await flushQueue()
        }
    }

    private func flushQueue() async {
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
    }

    private nonisolated static func data(for payload: CanonicalAsyncDiagnosticsPayload) throws -> Data {
        switch payload.body {
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
