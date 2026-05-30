//
//  ContentView.swift
//  RokuricsMac
//
//  Created by Vita on 2026/5/10.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var secureReceiverService: SecureReceiverService

    var body: some View {
        MacRootView(secureReceiverService: secureReceiverService)
    }
}

#Preview {
    ContentView(secureReceiverService: SecureReceiverService())
}
