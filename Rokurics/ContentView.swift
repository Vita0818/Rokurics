//
//  ContentView.swift
//  Rokurics
//
//  Created by Vita on 2026/5/8.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var macConnectionStore = SecureMacConnectionStore()
    @StateObject private var userProfileStore = UserProfileStore()

    var body: some View {
        NavigationStack {
            RokuricsHomeView(
                recordingManager: recordingManager,
                macConnectionStore: macConnectionStore,
                userProfileStore: userProfileStore
            )
        }
    }
}

#Preview {
    ContentView()
}
