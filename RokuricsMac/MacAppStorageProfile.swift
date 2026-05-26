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
    private static let uiTestModeKey = "ROKURICS_UI_TEST_MODE"
    private static let uiTestAppSupportRootKey = "ROKURICS_UI_TEST_APP_SUPPORT_ROOT"
    private static let uiTestSecurityRootKey = "ROKURICS_UI_TEST_SECURITY_ROOT"
    private static let uiTestReceiverPortKey = "ROKURICS_UI_TEST_RECEIVER_PORT"
    private static let uiTestPreferredHostKey = "ROKURICS_UI_TEST_HOST"
    private static let uiTestStorageNamespaceKey = "ROKURICS_UI_TEST_STORAGE_NAMESPACE"

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

    static var receiverPort: Int {
        guard isUITestMode,
              let value = ProcessInfo.processInfo.environment[uiTestReceiverPortKey],
              let port = Int(value),
              (0...65_535).contains(port) else {
            return 8787
        }
        return port
    }

    static var uiTestPreferredHost: String? {
        guard isUITestMode,
              let host = ProcessInfo.processInfo.environment[uiTestPreferredHostKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        return host
    }

    static var tlsPrivateKeyTag: Data {
        Data("\(currentBundleIdentifier).tls.private-key".utf8)
    }

    static var tlsDataProtectionPrivateKeyTag: Data {
        Data("\(currentBundleIdentifier).tls.private-key.dp.noninteractive.v2".utf8)
    }

    static var tlsPrivateKeyLabel: String {
        isLocalBuild ? "RokuricsMac Local TLS Private Key" : "Rokurics Local Mac TLS Private Key"
    }

    static var tlsCertificateLabel: String {
        isLocalBuild ? "RokuricsMac Local TLS Certificate" : "Rokurics Local Mac TLS Certificate"
    }

    static var tlsDataProtectionPrivateKeyLabel: String {
        isLocalBuild ? "RokuricsMac Local TLS Private Key DP v2" : "Rokurics Local Mac TLS Private Key DP v2"
    }

    static var tlsDataProtectionCertificateLabel: String {
        isLocalBuild ? "RokuricsMac Local TLS Certificate DP v2" : "Rokurics Local Mac TLS Certificate DP v2"
    }

    static func applicationSupportRootURL(fileManager: FileManager = .default) -> URL {
        if let overrideURL = uiTestOverrideURL(for: uiTestAppSupportRootKey) {
            return overrideURL
        }

        let root = defaultApplicationSupportRootURL(fileManager: fileManager)
        if let namespace = uiTestStorageNamespace {
            return root
                .appendingPathComponent("UITests", isDirectory: true)
                .appendingPathComponent(namespace, isDirectory: true)
                .appendingPathComponent("Support", isDirectory: true)
        }

        return root
    }

    static func securityDirectoryURL(fileManager: FileManager = .default) -> URL {
        if let overrideURL = uiTestOverrideURL(for: uiTestSecurityRootKey) {
            return overrideURL
        }

        if let namespace = uiTestStorageNamespace {
            return defaultApplicationSupportRootURL(fileManager: fileManager)
                .appendingPathComponent("UITests", isDirectory: true)
                .appendingPathComponent(namespace, isDirectory: true)
                .appendingPathComponent("Security", isDirectory: true)
        }

        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupportURL
            .appendingPathComponent(macSecurityFolderName, isDirectory: true)
            .appendingPathComponent("Security", isDirectory: true)
            .standardizedFileURL
    }

    private static func defaultApplicationSupportRootURL(fileManager: FileManager) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupportURL
            .appendingPathComponent(applicationSupportFolderName, isDirectory: true)
            .standardizedFileURL
    }

    private static var isUITestMode: Bool {
        ProcessInfo.processInfo.environment[uiTestModeKey] == "1"
    }

    private static var uiTestStorageNamespace: String? {
        guard isUITestMode,
              let namespace = ProcessInfo.processInfo.environment[uiTestStorageNamespaceKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !namespace.isEmpty else {
            return nil
        }
        return namespace
    }

    private static func uiTestOverrideURL(for key: String) -> URL? {
        guard isUITestMode,
              let path = ProcessInfo.processInfo.environment[key],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}
