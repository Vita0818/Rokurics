//
//  IPhoneCanonicalSwitchBackProofDriver.swift
//  Rokurics
//
//  Created by Codex on 2026/6/12.
//

import Foundation

#if DEBUG
struct IPhoneCanonicalSwitchBackProofDriver {
    private let appDataRootURL: URL

    init(fileManager: FileManager = .default) {
        self.appDataRootURL = Self.appDataRootURL(fileManager: fileManager)
    }

    func run() async -> CanonicalSwitchBackProofUISummary {
        let appDataRootURL = appDataRootURL
        return await Task.detached(priority: .userInitiated) {
            CanonicalSwitchBackProofDebugRunner().run(
                nodeRole: .iPhone,
                appDataRootURL: appDataRootURL
            )
        }.value
    }

    static func appDataRootURL(fileManager: FileManager = .default) -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return documentsURL
            .appendingPathComponent("Rokurics", isDirectory: true)
            .standardizedFileURL
    }
}
#endif
