//
//  PairedDeviceStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Combine
import Foundation

struct PairedDevice: Codable, Identifiable {
    let id: String
    let deviceName: String
    let sharedSecretBase64URL: String
    let pairedAt: Date
    var lastSeenAt: Date?

    var tokenPrefix: String {
        String(sharedSecretBase64URL.prefix(8))
    }

    var idPrefix: String {
        String(id.prefix(12))
    }
}

@MainActor
final class PairedDeviceStore: ObservableObject {
    @Published private(set) var devices: [PairedDevice] = []
    @Published private(set) var lastError: String?

    private let fileManager: FileManager
    private let storeURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        storeURL = Self.securityDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("paired-devices.json", isDirectory: false)
        load()
    }

    var deviceCount: Int {
        devices.count
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

    func markSeen(deviceID: String, at date: Date = Date()) {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else {
            return
        }

        devices[index].lastSeenAt = date
        save()
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

    private func save() {
        do {
            try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(devices)
            try data.write(to: storeURL, options: .atomic)
            print("[RokuricsPairing] saved paired devices: \(devices.count)")
        } catch {
            lastError = "Paired device store save failed: \(error.localizedDescription)"
            print("[RokuricsPairing] errors: \(lastError ?? "unknown paired device save error")")
        }
    }

    private static func securityDirectoryURL(fileManager: FileManager) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        return applicationSupportURL
            .appendingPathComponent("RokuricsMac", isDirectory: true)
            .appendingPathComponent("Security", isDirectory: true)
    }
}
