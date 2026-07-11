//
//  PairedDeviceStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Combine
import Foundation

enum PairedCredentialState: String, Codable, Equatable {
    case none
    case paired
    case invalid
    case revoked
    case fingerprintMismatch
}

enum UserConnectionIntent: String, Codable, Equatable {
    case wantsConnected
    case disconnectedByUser

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        if rawValue == "doesNotWantConnection" {
            self = .disconnectedByUser
        } else {
            self = UserConnectionIntent(rawValue: rawValue) ?? .wantsConnected
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct PairedDevice: Codable, Identifiable {
    let id: String
    let deviceName: String
    let sharedSecretBase64URL: String
    let pairedAt: Date
    var lastSeenAt: Date?
    var userConnectionIntent: UserConnectionIntent?

    var idPrefix: String {
        String(id.prefix(12))
    }

    var resolvedConnectionIntent: UserConnectionIntent {
        userConnectionIntent ?? .wantsConnected
    }

    var pairedCredentialState: PairedCredentialState {
        .paired
    }

    var wantsConnection: Bool {
        resolvedConnectionIntent == .wantsConnected
    }
}

@MainActor
final class PairedDeviceStore: ObservableObject {
    @Published private(set) var devices: [PairedDevice] = []
    @Published private(set) var lastError: String?

    private let fileManager: FileManager
    private let storeURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        storeURL = (rootURL ?? Self.securityDirectoryURL(fileManager: fileManager))
            .appendingPathComponent("paired-devices.json", isDirectory: false)
        load()
    }

    var deviceCount: Int {
        devices.count
    }

    var hasStoredDevices: Bool {
        !devices.isEmpty
    }

    var hasWantsConnectedDevice: Bool {
        devices.contains { $0.wantsConnection }
    }

    var hasPausedDevices: Bool {
        devices.contains { $0.resolvedConnectionIntent == .disconnectedByUser }
    }

    var displayPath: String {
        storeURL.path
    }

    func device(for id: String) -> PairedDevice? {
        devices.first { $0.id == id }
    }

    func upsert(_ device: PairedDevice) {
        if let existingIndex = devices.firstIndex(where: { $0.id == device.id }) {
            devices[existingIndex] = device
        } else {
            devices.append(device)
        }

        save()
    }

    /// Commits a pairing only when the atomic store write succeeds. On failure
    /// the in-memory view is rolled back so the caller cannot return a secret for
    /// a credential that will disappear on restart.
    @discardableResult
    func upsertPersisted(_ device: PairedDevice) -> Bool {
        let previousDevices = devices
        if let existingIndex = devices.firstIndex(where: { $0.id == device.id }) {
            devices[existingIndex] = device
        } else {
            devices.append(device)
        }
        guard save() else {
            devices = previousDevices
            return false
        }
        return true
    }

    func markSeen(deviceID: String, at date: Date = Date()) {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else {
            return
        }

        devices[index].lastSeenAt = date
        save()
    }

    func setUserConnectionIntent(_ intent: UserConnectionIntent, for deviceID: String) {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else {
            return
        }

        devices[index].userConnectionIntent = intent
        save()
    }

    func setUserConnectionIntentForAll(_ intent: UserConnectionIntent) {
        guard !devices.isEmpty else {
            return
        }

        for index in devices.indices {
            devices[index].userConnectionIntent = intent
        }
        save()
    }

    func clearAll() {
        devices.removeAll()
        save()
    }

    @discardableResult
    func removeDevice(id: String) -> Bool {
        guard let index = devices.firstIndex(where: { $0.id == id }) else {
            return false
        }
        devices.remove(at: index)
        save()
        return true
    }

    private func load() {
        do {
            try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fileManager.fileExists(atPath: storeURL.path) else {
                devices = []
                print("[RokuricsPairing] paired device store ready: \(storeURL.path)")
                return
            }

            let data = try Data(contentsOf: storeURL)
            devices = try JSONDecoder().decode([PairedDevice].self, from: data)
            print("[RokuricsPairing] loaded paired devices: \(devices.count)")
        } catch {
            lastError = "Paired device store load failed: \(error.localizedDescription)"
            print("[RokuricsPairing] errors: \(lastError ?? "unknown paired device store error")")
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(devices)
            try data.write(to: storeURL, options: .atomic)
            lastError = nil
            print("[RokuricsPairing] saved paired devices: \(devices.count)")
            return true
        } catch {
            lastError = "Paired device store save failed: \(error.localizedDescription)"
            print("[RokuricsPairing] errors: \(lastError ?? "unknown paired device save error")")
            return false
        }
    }

    private static func securityDirectoryURL(fileManager: FileManager) -> URL {
        MacAppStorageProfile.securityDirectoryURL(fileManager: fileManager)
    }
}
