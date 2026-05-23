//
//  MacAppStorageProfile.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/22.
//

import Foundation

enum MacAppStorageProfile {
    static let productionBundleIdentifier = "com.Vita0818.RokuricsMac"
    static let localBundleIdentifier = "com.Vita0818.RokuricsMac.local"

    static var currentBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? productionBundleIdentifier
    }

    static var isLocalBuild: Bool {
        currentBundleIdentifier == localBundleIdentifier
    }

    static var applicationSupportFolderName: String {
        isLocalBuild ? "RokuricsLocal" : "Rokurics"
    }

    static var macSecurityFolderName: String {
        isLocalBuild ? "RokuricsMacLocal" : "RokuricsMac"
    }

    static var localRootDisplayPath: String {
        "~/Library/Application Support/\(applicationSupportFolderName)"
    }

    static var tlsPrivateKeyTag: Data {
        Data("\(currentBundleIdentifier).tls.private-key".utf8)
    }

    static var tlsPrivateKeyLabel: String {
        isLocalBuild ? "RokuricsMac Local TLS Private Key" : "Rokurics Local Mac TLS Private Key"
    }

    static var tlsCertificateLabel: String {
        isLocalBuild ? "RokuricsMac Local TLS Certificate" : "Rokurics Local Mac TLS Certificate"
    }

    static func applicationSupportRootURL(fileManager: FileManager = .default) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupportURL
            .appendingPathComponent(applicationSupportFolderName, isDirectory: true)
            .standardizedFileURL
    }

    static func securityDirectoryURL(fileManager: FileManager = .default) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupportURL
            .appendingPathComponent(macSecurityFolderName, isDirectory: true)
            .appendingPathComponent("Security", isDirectory: true)
            .standardizedFileURL
    }
}
