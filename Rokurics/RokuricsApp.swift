//
//  RokuricsApp.swift
//  Rokurics
//
//  Created by Vita on 2026/5/8.
//

import SwiftUI

@main
struct RokuricsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var localNetworkSyncService = LocalNetworkSyncAppService()

    init() {
        JetBrainsMonoFont.ensureAvailable()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    localNetworkSyncService.activate()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        localNetworkSyncService.activate()
                    } else {
                        localNetworkSyncService.suspend()
                    }
                }
        }
    }
}
