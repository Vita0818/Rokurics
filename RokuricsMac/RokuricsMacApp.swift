//
//  RokuricsMacApp.swift
//  RokuricsMac
//
//  Created by Vita on 2026/5/10.
//

import SwiftUI

@main
struct RokuricsMacApp: App {
    @StateObject private var secureReceiverService = Self.makeSecureReceiverService()

    var body: some Scene {
        WindowGroup {
            ContentView(secureReceiverService: secureReceiverService)
        }
    }

    private static func makeSecureReceiverService() -> SecureReceiverService {
        if let uiTestHost = MacAppStorageProfile.uiTestPreferredHost {
            return SecureReceiverService(
                port: MacAppStorageProfile.receiverPort,
                preferredIPAddressProvider: { uiTestHost }
            )
        }

        return SecureReceiverService(port: MacAppStorageProfile.receiverPort)
    }
}
