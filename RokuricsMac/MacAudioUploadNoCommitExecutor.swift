//
//  MacAudioUploadNoCommitExecutor.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/4.
//

import Foundation

nonisolated struct MacAudioUploadNoCommitExecutor: CanonicalAudioUploadNoCommitExecutor {
    nonisolated init() {}

    nonisolated func stageAudioUploadNoCommit(
        _ candidate: CanonicalAudioUploadNoCommitCandidate
    ) -> CanonicalAudioUploadNoCommitResult {
        CanonicalAudioUploadNoCommitResult(
            candidate: candidate.cutoverCandidate,
            nodeRole: .mac
        )
    }
}
