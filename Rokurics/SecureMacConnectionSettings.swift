//
//  SecureMacConnectionSettings.swift
//  Rokurics
//
//  Created by Codex on 2026/5/10.
//

import Foundation

struct SecureMacConnectionSnapshot {
    let macHost: String
    let macPort: Int
    let macFingerprint: String
    let deviceID: String
    let sharedSecretBase64URL: String
    let pairedAt: String

    var isPaired: Bool {
        !macHost.isEmpty
            && macPort > 0
            && !macFingerprint.isEmpty
            && !deviceID.isEmpty
            && !sharedSecretBase64URL.isEmpty
    }
}

enum SecureMacConnectionSettings {
    static let macHostKey = "rokurics.secure.macHost"
    static let macPortKey = "rokurics.secure.macPort"
    static let macFingerprintKey = "rokurics.secure.macFingerprint"
    static let deviceIDKey = "rokurics.secure.deviceID"
    static let sharedSecretKey = "rokurics.secure.sharedSecret"
    static let pairedAtKey = "rokurics.secure.pairedAt"
    static let keychainService = "com.Vita0818.Rokurics.secure-mac"
    static let defaultPort = 8787

    static func clearPrototypeSharedSecretFromDefaults(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: sharedSecretKey)
    }
}
