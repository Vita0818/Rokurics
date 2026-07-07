//
//  IPhoneCanonicalFileRuntimeAdapter.swift
//  Rokurics
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated struct IPhoneCanonicalFileRuntimeAdapter: CanonicalFileSnapshotRuntimeAdapter {
    private let adapter: CanonicalStaticFileSnapshotAdapter

    nonisolated init(entries: [CanonicalFileSnapshotSourceEntry]) {
        self.adapter = CanonicalStaticFileSnapshotAdapter(entries: entries)
    }

    nonisolated func listFileSnapshotEntries(
        scope: CanonicalFileSnapshotScope
    ) async throws -> [CanonicalFileSnapshotSourceEntry] {
        try await adapter.listFileSnapshotEntries(scope: scope)
    }
}

