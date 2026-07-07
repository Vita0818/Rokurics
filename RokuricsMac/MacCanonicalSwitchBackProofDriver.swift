//
//  MacCanonicalSwitchBackProofDriver.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/12.
//

import Foundation

#if DEBUG
struct MacCanonicalSwitchBackProofDriver {
    private let appDataRootURL: URL

    init(fileManager: FileManager = .default) {
        self.appDataRootURL = MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
    }

    func run() async -> CanonicalSwitchBackProofUISummary {
        let appDataRootURL = appDataRootURL
        return await Task.detached(priority: .userInitiated) {
            CanonicalSwitchBackProofDebugRunner().run(
                nodeRole: .mac,
                appDataRootURL: appDataRootURL
            )
        }.value
    }
}
#endif
