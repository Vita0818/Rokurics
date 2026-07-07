//
//  IPhoneAudioUploadNoCommitExecutor.swift
//  Rokurics
//
//  Created by Codex on 2026/6/4.
//

import Foundation

nonisolated struct IPhoneAudioUploadNoCommitExecutor: CanonicalAudioUploadNoCommitExecutor {
    nonisolated init() {}

    nonisolated func stageAudioUploadNoCommit(
        _ candidate: CanonicalAudioUploadNoCommitCandidate
    ) -> CanonicalAudioUploadNoCommitResult {
        CanonicalAudioUploadNoCommitResult(
            candidate: candidate.cutoverCandidate,
            nodeRole: .iPhone
        )
    }
}
